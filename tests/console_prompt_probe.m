// console_prompt_probe.m — proves the console spots what a program is waiting for.
//
// Typing a password blind into a terminal is the moment a non-expert decides
// the app has frozen, so the console watches for a prompt and the window puts
// a real control in front of them. Getting that detection wrong is worse than
// not having it: a missed password prompt leaves someone stuck, and a false
// positive hides the typing box for no reason.
//
// This drives a real child process through the real PTY, so the prompts are
// the ones a program actually prints.
//
//   clang -fobjc-arc -framework AppKit -framework CoreText -I packaging \
//     tests/console_prompt_probe.m packaging/SlopNetConsole.m \
//     packaging/SlopNetBrand.m -o /tmp/prompt_probe && /tmp/prompt_probe
#import <Cocoa/Cocoa.h>
#import "SlopNetBrand.h"
#import "SlopNetConsole.h"

static int failures = 0;

static void check(BOOL ok, const char *what) {
    fprintf(stderr, "%s %s\n", ok ? "ok  " : "FAIL", what);
    if (!ok) failures++;
}

@interface Watcher : NSObject <SlopNetConsoleDelegate>
@property(nonatomic, assign) SlopNetPrompt seen;
@property(nonatomic, copy) NSString *question;
@property(nonatomic, assign) BOOL finished;
@end

@implementation Watcher
- (void)console:(SlopNetConsole *)c asksFor:(SlopNetPrompt)p question:(NSString *)q {
    self.seen = p;
    self.question = q;
}
- (void)console:(SlopNetConsole *)c finishedWithStatus:(int)s { self.finished = YES; }
@end

/// Run a shell snippet that prints a prompt and waits, then report what the
/// console decided it was asking for.
static SlopNetPrompt promptFor(NSString *script, NSString **question) {
    SlopNetConsole *console = [[SlopNetConsole alloc] initWithFrame:NSMakeRect(0, 0, 900, 400)];
    [console layoutSubtreeIfNeeded];
    Watcher *watcher = [Watcher new];
    console.delegate = watcher;
    [console runExecutable:@"/bin/bash" arguments:@[@"-c", script]];
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:4];
    while (watcher.seen == SlopNetPromptNone && [limit timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    SlopNetPrompt seen = watcher.seen;
    if (question) *question = watcher.question;
    [console stop];
    // Let the kill land so the next case starts clean.
    NSDate *settle = [NSDate dateWithTimeIntervalSinceNow:0.4];
    while ([settle timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return seen;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        // The shapes SlopNet's own scripts and ssh/sudo actually print.
        NSString *q = nil;
        check(promptFor(@"printf 'root@example.invalid\\047s password: '; read x", NULL)
              == SlopNetPromptPassword, "an ssh password prompt asks for a password");
        check(promptFor(@"printf '[sudo] password for someone: '; read x", NULL)
              == SlopNetPromptPassword, "a sudo prompt asks for a password");
        check(promptFor(@"printf 'Enter passphrase for key: '; read x", NULL)
              == SlopNetPromptPassword, "an ssh key passphrase asks for a password");
        check(promptFor(@"printf 'Continue? [y/N] '; read x", &q)
              == SlopNetPromptConfirm, "a [y/N] question asks for a yes or no");
        check(q != nil && [q containsString:@"Continue?"],
              "the question is handed over so the window can show it");
        check(promptFor(@"printf 'Install and test it? [y/N] '; read x", NULL)
              == SlopNetPromptConfirm, "the local-guide install question is a yes or no");

        // Things that must NOT hide the typing box.
        check(promptFor(@"printf 'Press Return to close this window: '; read x", NULL)
              == SlopNetPromptNone,
              "a press-Return line is left as ordinary typing");
        check(promptFor(@"printf 'Reading password rules from the file\\n'; sleep 3", NULL)
              == SlopNetPromptNone,
              "the word password inside a finished sentence is not a prompt");
        check(promptFor(@"printf 'Cloning into my-app...\\n'; sleep 3", NULL)
              == SlopNetPromptNone, "ordinary output is not a prompt");

        fprintf(stderr, failures == 0 ? "\nPROMPT PROBE DONE — all ok\n"
                                      : "\nPROMPT PROBE DONE — %d failed\n", failures);
    }
    return failures == 0 ? 0 : 1;
}
