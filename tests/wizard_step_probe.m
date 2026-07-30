// wizard_step_probe.m — walks every setup-guide screen, at several window sizes.
//
// The wizard is the first thing a beginner sees, so the failures that matter
// are the silent ones: a screen that lays out with conflicting constraints
// (AppKit logs "Unable to simultaneously satisfy constraints" and drops one),
// a step that resumes in the wrong place, or an Install button that is live
// before the server has been asked what it has room for.
//
// This drives the state machine directly rather than clicking, so it runs
// without a server and without accessibility permission.
//
//   clang -fobjc-arc -framework AppKit -framework CoreText -I packaging \
//     tests/wizard_step_probe.m packaging/SlopNetWizard.m -o /tmp/wizard_probe \
//     && /tmp/wizard_probe
#import <Cocoa/Cocoa.h>
#import "SlopNetWizard.h"

static int failures = 0;

static void check(BOOL ok, const char *what) {
    fprintf(stderr, "%s %s\n", ok ? "ok  " : "FAIL", what);
    if (!ok) failures++;
}

/// Every button on the current screen, by title.
static NSArray<NSButton *> *buttonsIn(NSView *view) {
    NSMutableArray<NSButton *> *found = [NSMutableArray array];
    if ([view isKindOfClass:NSButton.class]) [found addObject:(NSButton *)view];
    for (NSView *child in view.subviews) [found addObjectsFromArray:buttonsIn(child)];
    return found;
}

static NSButton *buttonTitled(NSWindow *window, NSString *title) {
    for (NSButton *button in buttonsIn(window.contentView)) {
        if ([button.title isEqualToString:title]) return button;
    }
    return nil;
}

static BOOL anyTextContains(NSView *view, NSString *needle) {
    if ([view isKindOfClass:NSTextField.class]) {
        NSString *value = ((NSTextField *)view).stringValue;
        if ([value rangeOfString:needle].location != NSNotFound) return YES;
    }
    for (NSView *child in view.subviews) {
        if (anyTextContains(child, needle)) return YES;
    }
    return NO;
}

@interface Silent : NSObject <SlopNetWizardDelegate>
@property(nonatomic, assign) BOOL askedToPrepare;
@property(nonatomic, assign) BOOL askedToInstall;
@property(nonatomic, copy) NSString *model;
@end

@implementation Silent
- (void)wizard:(SlopNetWizard *)w connectToHost:(NSString *)h port:(NSString *)p user:(NSString *)u {
    self.askedToPrepare = YES;
}
- (void)wizard:(SlopNetWizard *)w installGuideModel:(NSString *)m {
    self.askedToInstall = YES;
    self.model = m;
}
- (void)wizard:(SlopNetWizard *)w rememberHost:(NSString *)h port:(NSString *)p user:(NSString *)u {}
- (void)wizardOpenSettings:(SlopNetWizard *)w {}
- (void)wizardStartChat:(SlopNetWizard *)w {}
- (void)wizardDidFinish:(SlopNetWizard *)w {}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        Silent *silent = [Silent new];

        // Resume rules: never make someone redo a step that already passed.
        check([SlopNetWizard resumeStepForServerReady:NO guideReady:NO]
              == SlopNetWizardStepWelcome, "nothing done yet resumes at welcome");
        check([SlopNetWizard resumeStepForServerReady:YES guideReady:NO]
              == SlopNetWizardStepGuide, "prepared server resumes at the guide step");
        check([SlopNetWizard resumeStepForServerReady:YES guideReady:YES]
              == SlopNetWizardStepReady, "proved guide resumes at the last screen");

        SlopNetWizard *wizard = [[SlopNetWizard alloc]
            initWithHost:@"" port:@"22" user:@"root" serverReady:NO guideReady:NO];
        wizard.delegate = silent;
        NSWindow *window = wizard.window;

        // Every screen, at sizes including smaller than it opens at. A
        // conflicting constraint prints to stderr right here.
        CGFloat sizes[][2] = {{620, 500}, {520, 380}, {900, 700}, {520, 380}};
        SlopNetWizardStep steps[] = {
            SlopNetWizardStepWelcome, SlopNetWizardStepServer,
            SlopNetWizardStepServerSetup, SlopNetWizardStepGuide,
            SlopNetWizardStepCodingApp, SlopNetWizardStepReady,
        };
        for (int s = 0; s < 6; s++) {
            [wizard showStep:steps[s]];
            for (int i = 0; i < 4; i++) {
                [window setFrame:NSMakeRect(0, 0, sizes[i][0], sizes[i][1]) display:YES];
                [window.contentView layoutSubtreeIfNeeded];
            }
            check(wizard.step == steps[s], "a step laid out at four sizes");
        }

        // The guide screen must not offer a download before the server has
        // been asked what it has room for. With no host there is nothing to
        // ask, so the button stays off.
        [wizard showStep:SlopNetWizardStepGuide];
        [window.contentView layoutSubtreeIfNeeded];
        NSButton *install = buttonTitled(window, @"Install the guide");
        check(install != nil, "the guide screen offers an install button");
        check(install != nil && !install.enabled,
              "install is refused until capacity has been checked");
        check(buttonTitled(window, @"Check again") != nil,
              "capacity can be re-checked");
        check(anyTextContains(window.contentView, @"ibm-granite/granite-4.1-3b-GGUF:Q4_K_M"),
              "the default model is the proved bounded Granite 3B");
        check(anyTextContains(window.contentView, @"5000") &&
              anyTextContains(window.contentView, @"6000"),
              "the storage and memory floors are stated before approving");
        check(!anyTextContains(window.contentView, @"8B"),
              "the unproved 8B model is not offered");

        // Pressing install with nothing checked must not reach the delegate.
        if (install) [install performClick:nil];
        check(!silent.askedToInstall, "a disabled install button starts no download");

        // Welcome cannot go back past itself.
        [wizard showStep:SlopNetWizardStepWelcome];
        [window.contentView layoutSubtreeIfNeeded];
        check(buttonTitled(window, @"Back") == nil, "the first screen has no Back");

        // The server screen keeps typed details when moving on.
        [wizard showStep:SlopNetWizardStepServer];
        [window.contentView layoutSubtreeIfNeeded];
        check(buttonTitled(window, @"Check it answers") != nil,
              "the server screen can test the connection in place");

        // A prepared server says so instead of offering to prepare it again.
        SlopNetWizard *prepared = [[SlopNetWizard alloc]
            initWithHost:@"198.51.100.10" port:@"22" user:@"root"
             serverReady:YES guideReady:NO];
        prepared.delegate = silent;
        [prepared showStep:SlopNetWizardStepServerSetup];
        [prepared.window.contentView layoutSubtreeIfNeeded];
        check(buttonTitled(prepared.window, @"Prepare my server") == nil,
              "an already-prepared server is not prepared twice");

        // A proved guide shows its model and moves on, rather than downloading.
        SlopNetWizard *done = [[SlopNetWizard alloc]
            initWithHost:@"198.51.100.10" port:@"22" user:@"root"
             serverReady:YES guideReady:YES];
        done.delegate = silent;
        [done showStep:SlopNetWizardStepGuide];
        [done.window.contentView layoutSubtreeIfNeeded];
        check(buttonTitled(done.window, @"Install the guide") == nil,
              "a proved guide is not offered for download again");

        // The last screen defines Chat and Build, and stays honest about the
        // approved-build gap.
        [done showStep:SlopNetWizardStepReady];
        [done.window.contentView layoutSubtreeIfNeeded];
        check(anyTextContains(done.window.contentView, @"Chat") &&
              anyTextContains(done.window.contentView, @"Build"),
              "the last screen explains Chat and Build");
        check(anyTextContains(done.window.contentView, @"refuses"),
              "the last screen is honest about the approved-build gap");
        check(buttonTitled(done.window, @"Start chatting") != nil,
              "Chat is the primary action once the guide is proved");

        fprintf(stderr, failures == 0 ? "\nWIZARD PROBE DONE — all ok\n"
                                      : "\nWIZARD PROBE DONE — %d failed\n", failures);
    }
    return failures == 0 ? 0 : 1;
}
