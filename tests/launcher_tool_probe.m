// launcher_tool_probe.m — a full-screen tool never strands Granite behind it.
//
//   clang -DSLOPNET_NO_MAIN -fobjc-arc -Wall -Wextra \
//     -framework AppKit -framework CoreText -I packaging \
//     tests/launcher_tool_probe.m packaging/SlopNetLauncher.m \
//     packaging/SlopNetConsole.m packaging/SlopNetEntryView.m \
//     packaging/SlopNetSettings.m packaging/SlopNetTools.m \
//     packaging/SlopNetBrand.m packaging/SlopNetWizard.m \
//     -o /tmp/launcher_tool && /tmp/launcher_tool

#import <Cocoa/Cocoa.h>
#import "SlopNetConsole.h"
#import "SlopNetEntryView.h"
#import "SlopNetSettings.h"
#import "SlopNetTools.h"

static int failures = 0;
static void check(BOOL ok, const char *what) {
    fprintf(stderr, "%s %s\n", ok ? "ok  " : "FAIL", what);
    if (!ok) failures++;
}

static NSString *firstDecodedPayload(NSString *command) {
    NSRegularExpression *payload = [NSRegularExpression
        // Absolute paths, because the payload is now sent with them so that a
        // command on the far side cannot be steered by whatever is on the
        // path. The pattern predates that and matched nothing, which read as
        // a missing guard when the guard was there all along.
        regularExpressionWithPattern:@"(?:/usr/bin/)?printf %s '([^']+)' \\| "
                                     @"(?:/usr/bin/)?base64 -d"
                              options:0 error:nil];
    NSTextCheckingResult *match = [payload firstMatchInString:command ?: @""
                                                       options:0
                                                         range:NSMakeRange(0, command.length)];
    if (match == nil) return nil;
    NSString *encoded = [command substringWithRange:[match rangeAtIndex:1]];
    NSData *data = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

/// The launcher is deliberately private to the app. Redeclare only the
/// actions this probe drives; the production implementation is linked below.
@interface SlopNetAppDelegate : NSObject <SlopNetConsoleDelegate, SlopNetSettingsDelegate,
                                          SlopNetToolsDelegate>
- (NSView *)buildSidebar;
/// The terminal on top, and how a new tab's terminal is made.
@property(nonatomic, strong) SlopNetConsole *console;
@property(nonatomic, copy) SlopNetConsole *(^makeConsole)(void);
- (NSView *)buildMain;
- (void)showSkipControl:(NSString *)name;
- (void)skipThisSignIn:(id)sender;
- (void)returnToGranite:(id)sender;
- (void)setBusy:(BOOL)busy;
- (void)runServerCommand:(NSString *)command;
- (void)showTypingBar;
- (void)console:(SlopNetConsole *)console needsSignIn:(NSURL *)page code:(NSString *)code;
- (void)console:(SlopNetConsole *)console asksFor:(SlopNetPrompt)prompt
       question:(NSString *)question;
- (void)tools:(SlopNetTools *)tools runOnServer:(NSString *)command
        title:(NSString *)title;
- (BOOL)tools:(SlopNetTools *)tools openOnServer:(NSString *)command
        title:(NSString *)title;
- (void)tools:(SlopNetTools *)tools signInToProvider:(NSString *)provider;
- (void)signInToProvider:(NSString *)provider;
- (void)showTab:(NSUInteger)index;
- (NSString *)helper:(NSString *)name;
@end

@interface ProbeAppDelegate : SlopNetAppDelegate
@end
@implementation ProbeAppDelegate
- (NSString *)helper:(NSString *)name {
    (void)name;
    return @"/bin/true";
}
@end

@interface FakeConsole : SlopNetConsole
@property(nonatomic, assign) BOOL fakeRunning;
@property(nonatomic, assign) BOOL stopped;
@property(nonatomic, assign) BOOL refuseLaunch;
@property(nonatomic, copy) NSString *launchedPath;
@property(nonatomic, copy) NSArray<NSString *> *launchedArguments;
@property(nonatomic, strong) NSMutableArray<NSString *> *notes;
@end

@implementation FakeConsole
- (BOOL)running { return self.fakeRunning; }
- (BOOL)runExecutable:(NSString *)path arguments:(NSArray<NSString *> *)arguments {
    if (self.refuseLaunch) return NO;
    self.launchedPath = path;
    self.launchedArguments = arguments;
    self.fakeRunning = YES;
    return YES;
}
- (void)stop { self.stopped = YES; }
- (void)note:(NSString *)text {
    if (self.notes == nil) self.notes = [NSMutableArray array];
    [self.notes addObject:text ?: @""];
}
@end

@interface ToolsCatcher : NSObject
@property(nonatomic, copy) NSString *command;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, assign) BOOL accepted;
@end
@implementation ToolsCatcher
- (void)tools:(SlopNetTools *)tools runOnServer:(NSString *)command
        title:(NSString *)title {
    (void)tools; (void)command; (void)title;
}
- (BOOL)tools:(SlopNetTools *)tools openOnServer:(NSString *)command
        title:(NSString *)title {
    (void)tools;
    self.command = command;
    self.title = title;
    return self.accepted;
}
- (void)tools:(SlopNetTools *)tools signInToProvider:(NSString *)provider {
    (void)tools; (void)provider;
}
@end

@interface SlopNetTools (Probe)
- (void)openPressed:(NSButton *)sender;
- (void)rebuildLibrary;
- (void)rebuildInstalled;
@end

int main(void) {
    @autoreleasepool {
        setenv("SLOPNET_PINNED_RELEASE", "v0.9.45", 1);
        [NSApplication sharedApplication];

        SlopNetAppDelegate *app = [ProbeAppDelegate new];
        [app buildSidebar];
        NSView *main = [app buildMain];
        NSWindow *appWindow = [[NSWindow alloc]
            initWithContentRect:NSMakeRect(0, 0, 1000, 700)
                      styleMask:NSWindowStyleMaskTitled
                        backing:NSBackingStoreBuffered defer:NO];
        appWindow.contentView = main;
        [app setValue:appWindow forKey:@"window"];
        FakeConsole *console = [[FakeConsole alloc] initWithFrame:NSMakeRect(0,0,900,400)];
        [app setValue:console forKey:@"console"];
        SlopNetEntryView *entry = [app valueForKey:@"entry"];
        entry.console = console;
        [app setValue:@"server.example.invalid" forKey:@"host"];
        [app setValue:@"root" forKey:@"username"];
        [app setValue:@"22" forKey:@"port"];

        NSButton *granite = [app valueForKey:@"graniteButton"];
        check([granite.title isEqualToString:@"Granite"] &&
              granite.action == @selector(returnToGranite:),
              "Granite is a permanent sidebar action");

        [app showSkipControl:@"Antigravity"];
        NSStackView *promptBar = [app valueForKey:@"promptBar"];
        NSTextField *promptLabel = [app valueForKey:@"promptLabel"];
        check(!promptBar.hidden && [promptLabel.stringValue containsString:@"Antigravity"],
              "the probe begins with the stale sign-in bar visible");
        check(![promptLabel.stringValue containsString:@"Setting up"],
              "the sign-in bar makes no stale setup claim");

        // A browser offer is informational; it must not steal the keyboard
        // from the still-running terminal program underneath it.
        console.fakeRunning = YES;
        NSURL *signInPage = [NSURL URLWithString:@"https://example.invalid/device"];
        [app console:console needsSignIn:signInPage code:@"ABCD-EFGH"];
        check(appWindow.firstResponder == entry &&
              ![[app valueForKey:@"openPageButton"] isHidden] &&
              ![[app valueForKey:@"codeButton"] isHidden],
              "a browser sign-in keeps terminal keyboard focus while its buttons stay available");
        [app showSkipControl:@"Next provider"];
        check([app valueForKey:@"signInPage"] == nil &&
              [app valueForKey:@"signInCode"] == nil &&
              [[app valueForKey:@"openPageButton"] isHidden] &&
              [[app valueForKey:@"codeButton"] isHidden],
              "the next queued provider cannot inherit the previous browser offer");
        [app console:console needsSignIn:signInPage code:@"IJKL-MNOP"];
        [app showTypingBar];
        [app console:console asksFor:SlopNetPromptNone question:nil];
        check([app valueForKey:@"signInPage"] == nil &&
              [app valueForKey:@"signInCode"] == nil && promptBar.hidden &&
              [[app valueForKey:@"openPageButton"] isHidden] &&
              [[app valueForKey:@"codeButton"] isHidden],
              "returning to the composer cannot resurrect a stale browser offer");
        console.fakeRunning = NO;

        // A direct sign-in can lose a race for the console. The failure must
        // put back the ordinary composer instead of leaving a spinner and a
        // terminal-only Back button on screen.
        console.refuseLaunch = YES;
        [app signInToProvider:@"claude"];
        check([app valueForKey:@"signingIn"] == nil &&
              [app valueForKey:@"actionTimer"] == nil &&
              ![[app valueForKey:@"busy"] boolValue] &&
              promptBar.hidden && [[app valueForKey:@"skipButton"] isHidden] &&
              ![[app valueForKey:@"entryScroller"] isHidden] &&
              ![[app valueForKey:@"sendButton"] isHidden] &&
              appWindow.firstResponder == entry,
              "a refused sign-in restores the ordinary composer");
        console.refuseLaunch = NO;

        // Granite stays visible during protected work without becoming a
        // second, misleading way to abort an install or build.
        console.fakeRunning = YES;
        [app setBusy:YES];
        [app returnToGranite:nil];
        check(!granite.enabled && !console.stopped,
              "Granite cannot accidentally interrupt protected work");
        console.fakeRunning = NO;
        [app setBusy:NO];

        // A tool now opens a terminal of its own, so the checks below follow
        // that one rather than the console Granite is using. The app is told
        // how to make it, which is the only way to watch a tool open without
        // a real connection being made.
        __block FakeConsole *toolConsole = nil;
        app.makeConsole = ^SlopNetConsole *{
            toolConsole = [[FakeConsole alloc] initWithFrame:NSZeroRect];
            toolConsole.fakeRunning = YES;
            return toolConsole;
        };
        NSUInteger tabsBefore = [[app valueForKey:@"tabTitles"] count];
        [app tools:nil openOnServer:
            @"zellij attach --create slopnet options --on-force-close detach"
                              title:@"Zellij"];
        check([[app valueForKey:@"tabTitles"] count] == tabsBefore + 1,
              "opening a tool adds a tab of its own");
        check(toolConsole != nil && app.console == toolConsole,
              "and that tab's terminal is the one now on top");
        check([[[app valueForKey:@"tabTitles"] firstObject] isEqualToString:@"Granite"],
              "Granite is still the first tab");
        // Two terminals from here on: the tool's, and Granite's underneath it.
        // Checks about the tool follow the first; anything typed goes to the
        // second, which is where a person would look for it.
        FakeConsole *graniteConsole = console;
        console = toolConsole ?: console;
        NSButton *send = [app valueForKey:@"sendButton"];
        NSButton *skip = [app valueForKey:@"skipButton"];
        check(promptBar.hidden && skip.hidden,
              "opening a tool clears the old sign-in prompt and Skip button");
        check([send.title isEqualToString:@"Back to Granite"] &&
              send.action == @selector(returnToGranite:),
              "a running tool has a plainly labelled way back to Granite");
        check([console.launchedPath isEqualToString:@"/usr/bin/ssh"] && console.fakeRunning,
              "the tool still launches through the normal SSH console path");
        // The keyboard has to be on the box that forwards keys to the program.
        // It is started from a sheet, so without this every key goes to the
        // sheet and a full-screen tool answers nothing.
        check(appWindow.firstResponder == entry,
              "starting a tool puts the keyboard on the box that forwards keys");
        NSString *remote = console.launchedArguments.lastObject;
        NSString *guard = firstDecodedPayload(remote);
        NSString *releasePayload = [[@"v0.9.45" dataUsingEncoding:NSUTF8StringEncoding]
            base64EncodedStringWithOptions:0];
        check([guard containsString:@"/var/lib/slopnet/release-v1"] &&
              [guard containsString:releasePayload] &&
              [guard containsString:@"runtime-account-v2"] &&
              [guard containsString:@"install-v2"] &&
              [guard containsString:@"home_dev="] &&
              [guard containsString:@"getent passwd slopnet"] &&
              [remote containsString:@"TERM=xterm-256color"] &&
              [remote containsString:@"COLORTERM=truecolor"],
              "Tools validate the managed account and exact release before running");

        // A second tool must open while the first is still running. The old
        // busy latch refused it, which made Superfile look broken after
        // anything else was open.
        __block FakeConsole *secondTool = nil;
        app.makeConsole = ^SlopNetConsole *{
            secondTool = [[FakeConsole alloc] initWithFrame:NSZeroRect];
            secondTool.fakeRunning = YES;
            return secondTool;
        };
        NSUInteger afterFirst = [[app valueForKey:@"tabTitles"] count];
        BOOL secondOk = [app tools:nil openOnServer:@"spf" title:@"Superfile"];
        check(secondOk && secondTool != nil &&
              [[app valueForKey:@"tabTitles"] count] == afterFirst + 1 &&
              app.console == secondTool && console.fakeRunning,
              "a second tool opens in its own tab while the first still runs");

        [app returnToGranite:nil];
        check(secondTool.stopped, "Back to Granite stops the tool on top");
        secondTool.fakeRunning = NO;
        [app console:secondTool finishedWithStatus:-1];
        // First tool is still running in the background; Granite is free.
        check(console.fakeRunning &&
              [send.title isEqualToString:@"Send"] &&
              send.action == @selector(sendPressed:),
              "closing one tool leaves others running and returns Granite's composer");

        // Stop the first tool from its tab so nothing is left running.
        NSArray *titles = [app valueForKey:@"tabTitles"];
        NSUInteger firstToolIndex = [titles indexOfObject:@"Zellij"];
        check(firstToolIndex != NSNotFound, "the first tool tab is still listed");
        [app showTab:firstToolIndex];
        check(app.console == console, "switching tabs brings the first tool back");
        [app returnToGranite:nil];
        console.fakeRunning = NO;
        [app console:console finishedWithStatus:-1];
        check([send.title isEqualToString:@"Send"] &&
              send.action == @selector(sendPressed:),
              "after the last tool closes the ordinary Granite composer returns");
        BOOL falseFailure = NO;
        for (NSString *note in console.notes) {
            if ([note containsString:@"Nothing was left half-done"]) falseFailure = YES;
        }
        check(!falseFailure, "choosing Back to Granite is not reported as a failure");

        // A command typed with the launcher's $ prefix can itself be a
        // full-screen program. It needs the same escape hatch as Tools.
        console = graniteConsole;
        console.stopped = NO;
        console.fakeRunning = NO;
        console.launchedPath = nil;
        [app runServerCommand:@"zellij"];
        // A typed full-screen command opens a terminal of its own too, so the
        // program to look at is the one now on top. Granite is a tab away, and
        // the button says so.
        check([send.title isEqualToString:@"Back to Granite"] &&
              send.action == @selector(returnToGranite:) && ((FakeConsole *)app.console).fakeRunning,
              "a typed server command keeps Granite one action away");
        [app returnToGranite:nil];
        console.fakeRunning = NO;
        [app console:console finishedWithStatus:-1];

        // Repeat the leave transition with the production PTY rather than a
        // synchronous fake. The child takes the alternate screen, receives a
        // real signal, and reports its asynchronous end through the launcher.
        SlopNetConsole *real = [[SlopNetConsole alloc]
            initWithFrame:NSMakeRect(0, 0, 900, 400)];
        real.delegate = app;
        [app setValue:real forKey:@"console"];
        entry.console = real;
        [app setValue:@YES forKey:@"toolRunning"];
        [app setBusy:YES];
        BOOL realStarted = [real runExecutable:@"/bin/sh"
            arguments:@[@"-c", @"printf '\033[?1049h'; trap 'exit 0' TERM; while :; do sleep 1; done"]];
        NSDate *rawDeadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
        while (realStarted && !real.rawInputActive && rawDeadline.timeIntervalSinceNow > 0) {
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        [app returnToGranite:nil];
        NSDate *stopDeadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
        while (real.running && stopDeadline.timeIntervalSinceNow > 0) {
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        check(realStarted && !real.running &&
              [send.title isEqualToString:@"Send"] &&
              send.action == @selector(sendPressed:),
              "a real alternate-screen PTY returns asynchronously to Granite");

        // The remaining queue checks deliberately use the controllable fake.
        [app setValue:console forKey:@"console"];
        entry.console = console;

        // Skipping one provider must wait for its child to end. The old code
        // tried to start provider two while provider one's PTY was still live,
        // so runExecutable: refused it and the queue could collapse.
        console.stopped = NO;
        console.fakeRunning = YES;
        console.launchedPath = nil;
        [app setValue:@"first" forKey:@"signingIn"];
        [app setValue:[NSMutableArray arrayWithObject:@"second"] forKey:@"signInQueue"];
        [app setValue:[NSMutableArray array] forKey:@"skipped"];
        [app setValue:@YES forKey:@"signInQueueActive"];
        [app showSkipControl:@"First"];
        [app skipThisSignIn:nil];
        check(console.stopped && [[app valueForKey:@"signingIn"] isEqualToString:@"first"] &&
              [[app valueForKey:@"signInQueue"] count] == 1 && console.launchedPath == nil,
              "Skip waits for the current PTY before advancing the queue");

        // Granite means abandon the whole sign-in run, not skip into the next
        // provider. Clearing happens before the child-finished callback.
        console.stopped = NO;
        [app setValue:@NO forKey:@"skippingSignIn"];
        [app setValue:@"first" forKey:@"signingIn"];
        [app setValue:[NSMutableArray arrayWithObject:@"second"] forKey:@"signInQueue"];
        [app returnToGranite:nil];
        check(console.stopped && [app valueForKey:@"signingIn"] == nil &&
              [[app valueForKey:@"signInQueue"] count] == 0,
              "Granite abandons the remaining sign-in queue");
        console.fakeRunning = NO;
        [app console:console finishedWithStatus:-1];
        check(console.launchedPath == nil, "returning to Granite starts no next provider");

        // Tools must step aside when Open is pressed; otherwise the tool
        // starts behind the sheet and appears not to have opened.
        ToolsCatcher *catcher = [ToolsCatcher new];
        catcher.accepted = NO;
        SlopNetTools *tools = [[SlopNetTools alloc]
            initWithHost:@"server.example.invalid" port:@"22" user:@"root" connected:YES];
        tools.delegate = (id<SlopNetToolsDelegate>)catcher;
        [tools setValue:@[@{@"id": @"zellij", @"name": @"Zellij",
                            @"run": @"zellij attach --create slopnet options --on-force-close detach",
                            @"install": @"true",
                            @"check": @"zellij",
                            @"subscription": @"free"},
                          @{@"id": @"antigravity",
                            @"name": @"Antigravity CLI  (preinstalled, interactive only)",
                            @"run": @"agy",
                            @"install": @"",
                            @"check": @"agy",
                            @"subscription": @"not a SlopNet build worker yet"}]
                forKey:@"tools"];
        // Rebuild rows after injecting the list the probe drives.
        [tools setValue:[NSMutableDictionary dictionary] forKey:@"libraryStatus"];
        [tools setValue:[NSMutableDictionary dictionary] forKey:@"libraryAction"];
        [tools setValue:[NSMutableDictionary dictionary] forKey:@"installedStatus"];
        [tools setValue:[NSMutableDictionary dictionary] forKey:@"installedOpen"];
        [tools rebuildLibrary];
        [tools rebuildInstalled];

        // Installed is the first tab — open what you have before browsing more.
        NSTabView *tabs = nil;
        NSMutableArray<NSView *> *stack =
            [NSMutableArray arrayWithObject:tools.window.contentView];
        while (stack.count > 0) {
            NSView *view = stack.lastObject;
            [stack removeLastObject];
            if ([view isKindOfClass:NSTabView.class]) { tabs = (NSTabView *)view; break; }
            [stack addObjectsFromArray:view.subviews];
        }
        check(tabs != nil && tabs.numberOfTabViewItems >= 2 &&
              [[[tabs tabViewItemAtIndex:0] label] isEqualToString:@"Installed"] &&
              [[[tabs tabViewItemAtIndex:1] label] isEqualToString:@"Library"],
              "Installed appears before Library");

        // Antigravity is preinstalled: the Library must not read as unfinished.
        NSDictionary *actions = [tools valueForKey:@"libraryAction"];
        NSButton *agy = actions[@"antigravity"];
        check([agy.title isEqualToString:@"Already installed"] && !agy.enabled,
              "Antigravity says Already installed, not No command yet");

        NSWindow *parent = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,900,700)
                                                       styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered defer:NO];
        [tools presentFrom:parent];
        NSButton *open = [NSButton buttonWithTitle:@"Open" target:nil action:nil];
        open.identifier = @"zellij";
        [tools openPressed:open];
        check(tools.window.sheetParent == parent,
              "Tools stays open when the console cannot accept the tool");
        catcher.accepted = YES;
        [tools openPressed:open];
        check([catcher.command isEqualToString:
               @"zellij attach --create slopnet options --on-force-close detach"],
              "Tools Open sends the listed run command");
        check(tools.window.sheetParent == nil,
              "Tools closes after Open so the console is visible");

        // Settings is connection and model only — no way to launch a tool.
        SlopNetSettings *settings = [[SlopNetSettings alloc]
            initWithHost:@"server.example.invalid" port:@"22" user:@"root" connected:YES];
        NSMutableArray<NSView *> *settingsStack =
            [NSMutableArray arrayWithObject:settings.window.contentView];
        BOOL settingsHasOpen = NO;
        while (settingsStack.count > 0) {
            NSView *view = settingsStack.lastObject;
            [settingsStack removeLastObject];
            if ([view isKindOfClass:NSButton.class] &&
                [((NSButton *)view).title isEqualToString:@"Open"]) {
                settingsHasOpen = YES;
            }
            [settingsStack addObjectsFromArray:view.subviews];
        }
        check(!settingsHasOpen, "Settings has no Open button for tools");

        fprintf(stderr, failures == 0 ? "\nLAUNCHER TOOL PROBE DONE — all ok\n"
                                      : "\nLAUNCHER TOOL PROBE DONE — %d failed\n", failures);
    }
    return failures == 0 ? 0 : 1;
}
