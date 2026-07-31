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
@property(nonatomic, strong) NSURL *signInPage;
@property(nonatomic, copy) NSString *signInCode;
/// How many times a sign-in was offered, and what the first one carried.
@property(nonatomic, assign) NSInteger signInOffers;
@property(nonatomic, copy) NSString *firstCode;
@end

@implementation Watcher
- (void)console:(SlopNetConsole *)c asksFor:(SlopNetPrompt)p question:(NSString *)q {
    self.seen = p;
    self.question = q;
}
- (void)console:(SlopNetConsole *)c needsSignIn:(NSURL *)page code:(NSString *)code {
    if (self.signInOffers == 0) self.firstCode = code;
    self.signInOffers++;
    self.signInPage = page;
    self.signInCode = code;
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

/// Run a snippet that prints a sign-in link, and hand back the watcher so a
/// test can ask both what was offered and how many times.
static Watcher *signInFor(NSString *script) {
    SlopNetConsole *console = [[SlopNetConsole alloc] initWithFrame:NSMakeRect(0, 0, 900, 400)];
    [console layoutSubtreeIfNeeded];
    Watcher *watcher = [Watcher new];
    console.delegate = watcher;
    [console runExecutable:@"/bin/bash" arguments:@[@"-c", script]];
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:2.5];
    while ([limit timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    [console stop];
    NSDate *settle = [NSDate dateWithTimeIntervalSinceNow:0.4];
    while ([settle timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return watcher;
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
        // The confirmation half used to fall through to the plain typing box,
        // which put the operator's passphrase on screen in clear text.
        check(promptFor(@"printf 'Enter same passphrase again: '; read x", NULL)
              == SlopNetPromptPassword,
              "the repeat-passphrase prompt is masked too, not shown in clear");
        check(promptFor(@"printf 'Continue? [y/N] '; read x", &q)
              == SlopNetPromptConfirm, "a [y/N] question asks for a yes or no");
        check(q != nil && [q containsString:@"Continue?"],
              "the question is handed over so the window can show it");
        check(promptFor(@"printf 'Install and test it? [y/N] '; read x", NULL)
              == SlopNetPromptConfirm, "the local-guide install question is a yes or no");

        // Things that must NOT hide the typing box.
        // This test used to assert the opposite, and the operator hit exactly
        // the behaviour it was protecting: dismissing a message meant clicking
        // the box, pressing Return, then pressing Send. One button instead.
        check(promptFor(@"printf 'Press Return to close this window: '; read x", NULL)
              == SlopNetPromptContinue,
              "a press-Return line gets one Continue button");
        check(promptFor(@"printf 'Press Enter to carry on: '; read x", NULL)
              == SlopNetPromptContinue, "so does press-Enter");
        check(promptFor(@"printf 'Reading password rules from the file\\n'; sleep 3", NULL)
              == SlopNetPromptNone,
              "the word password inside a finished sentence is not a prompt");
        check(promptFor(@"printf 'Cloning into my-app...\\n'; sleep 3", NULL)
              == SlopNetPromptNone, "ordinary output is not a prompt");

        // A browser sign-in: the tool prints a link and a one-time code and
        // expects both carried across by hand. The console has to spot them
        // so the window can offer a button and put the code on the clipboard.
        {
            SlopNetConsole *c = [[SlopNetConsole alloc] initWithFrame:NSMakeRect(0,0,900,400)];
            [c layoutSubtreeIfNeeded];
            Watcher *w = [Watcher new];
            c.delegate = w;
            [c runExecutable:@"/bin/bash" arguments:@[@"-c",
                @"printf 'Open https://auth.example.invalid/device and enter code WXYZ-1234\n'; sleep 3"]];
            NSDate *until = [NSDate dateWithTimeIntervalSinceNow:4];
            while (w.signInPage == nil && [until timeIntervalSinceNow] > 0) {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                         beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            }
            check(w.signInPage != nil, "a sign-in link is spotted in the output");
            check([w.signInPage.absoluteString isEqualToString:
                   @"https://auth.example.invalid/device"],
                  "the link is captured without trailing punctuation");
            check([w.signInCode isEqualToString:@"WXYZ-1234"],
                  "the one-time code is captured so it can be put on the clipboard");
            [c stop];
        }

            // The real shape of a device sign-in: the link prints, and the code
        // arrives a moment later. Offering once per link meant the bar went up
        // with the link and no code, and never updated — so the code had to be
        // copied by hand, which is the whole thing this exists to stop.
        {
            Watcher *w = signInFor(
                @"printf 'Open https://auth.example.invalid/device\n'; sleep 0.6; "
                @"printf 'Enter the code WDJB-MJHT\n'; sleep 1");
            check(w.signInOffers >= 2, "the link and the later code are both offered");
            check(w.firstCode == nil, "no code is invented before one has printed");
            check([w.signInCode isEqualToString:@"WDJB-MJHT"],
                  "a code that arrives after the link is still picked up");
        }

        // A code carried in the link itself is exact, so it wins outright.
        {
            Watcher *w = signInFor(
                @"printf 'Go to https://auth.example.invalid/activate?user_code=BDWD-HQPS\n'; sleep 1");
            check([w.signInCode isEqualToString:@"BDWD-HQPS"],
                  "a code inside the link is read out of the link");
        }

        // Shouted English near a link must not land on the Copy button.
        {
            Watcher *w = signInFor(
                @"printf 'WARNING: this token is READ-ONLY\n'; "
                @"printf 'Sign in at https://auth.example.invalid/device\n'; sleep 1");
            check(w.signInPage != nil, "the link is still offered");
            check(w.signInCode == nil,
                  "hyphenated shouting is not mistaken for a one-time code");
        }

        // Real output, captured from grok 0.2.117 signing in on a server.
        // Every earlier case here was written from my idea of what a provider
        // prints. This one is what one actually printed, kept verbatim.
        {
            Watcher *w = signInFor(
                @"printf '  https://accounts.x.ai/oauth2/device?user_code=2E2J-J8A8\n\n'; "
                @"printf 'Confirm this code in your browser:\n\n  2E2J-J8A8\n'; "
                @"printf '\033[90mOnly continue with a code you requested.\033[0m\n'; sleep 1");
            check(w.signInPage != nil, "the real sign-in link is offered");
            check([w.signInCode isEqualToString:@"2E2J-J8A8"],
                  "the real one-time code is captured, so nobody types it by hand");
        }

        // A conversation turn is a program run, but the reply arriving is the
        // news — nobody wants a note telling them their sentence finished.
        // Failures must still speak up.
        {
            SlopNetConsole *c = [[SlopNetConsole alloc] initWithFrame:NSMakeRect(0,0,900,400)];
            [c layoutSubtreeIfNeeded];
            Watcher *w = [Watcher new];
            c.delegate = w;
            c.quietWhenItWorks = YES;
            [c runExecutable:@"/bin/bash" arguments:@[@"-c", @"printf 'a reply\n'"]];
            NSDate *until = [NSDate dateWithTimeIntervalSinceNow:3];
            while (!w.finished && [until timeIntervalSinceNow] > 0) {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                         beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            }
            NSString *shown = c.textForTesting;
            check([shown containsString:@"a reply"], "the reply itself is shown");
            check(![shown containsString:@"finished"],
                  "a turn that worked says nothing about finishing");

            // The flag lasts one run, so it cannot silence a later failure.
            SlopNetConsole *f = [[SlopNetConsole alloc] initWithFrame:NSMakeRect(0,0,900,400)];
            [f layoutSubtreeIfNeeded];
            Watcher *w2 = [Watcher new];
            f.delegate = w2;
            f.quietWhenItWorks = YES;
            [f runExecutable:@"/bin/bash" arguments:@[@"-c", @"exit 3"]];
            NSDate *until2 = [NSDate dateWithTimeIntervalSinceNow:3];
            while (!w2.finished && [until2 timeIntervalSinceNow] > 0) {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                         beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            }
            // What matters is that a failure is announced at all, not the
            // exact wording — "stopped, code 3" was replaced because an exit
            // code means nothing to the person reading it.
            check([f.textForTesting containsString:@"did not work"],
                  "a turn that failed still says so");
        }

        // Collection is for a conversation turn only. The far more important
        // half of this test is the second console: everything else — setup,
        // installs, sign-ins — must still stream into the window line by line.
        {
            SlopNetConsole *c = [[SlopNetConsole alloc] initWithFrame:NSMakeRect(0,0,900,400)];
            [c layoutSubtreeIfNeeded];
            Watcher *w = [Watcher new];
            c.delegate = w;
            c.collectsOutput = YES;
            [c runExecutable:@"/bin/bash" arguments:@[@"-c",
                @"printf '\033[32mgreen\033[0m reply\r\nsecond line\n'"]];
            NSDate *until = [NSDate dateWithTimeIntervalSinceNow:3];
            while (!w.finished && [until timeIntervalSinceNow] > 0) {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                         beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            }
            check(![c.textForTesting containsString:@"second line"],
                  "a collected run draws nothing while it is arriving");
            NSString *held = c.collectedOutput;
            check([held containsString:@"green reply"] && [held containsString:@"second line"],
                  "the whole reply is held for framing");
            check(![held containsString:@"\033"],
                  "with no escape sequences left to stain the panel it goes into");

            SlopNetConsole *plain = [[SlopNetConsole alloc] initWithFrame:NSMakeRect(0,0,900,400)];
            [plain layoutSubtreeIfNeeded];
            Watcher *w2 = [Watcher new];
            plain.delegate = w2;
            [plain runExecutable:@"/bin/bash" arguments:@[@"-c", @"printf 'installing…\n'"]];
            NSDate *until2 = [NSDate dateWithTimeIntervalSinceNow:3];
            while (!w2.finished && [until2 timeIntervalSinceNow] > 0) {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                         beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            }
            check([plain.textForTesting containsString:@"installing"],
                  "an ordinary run still streams into the window, unchanged");
        }

        // What the guide is allowed to read. The redaction is the part that
        // matters: sign-in codes and keys pass through this window, and a
        // prompt is not a place to keep a credential alive — even a local one.
        {
            SlopNetConsole *c = [[SlopNetConsole alloc] initWithFrame:NSMakeRect(0,0,900,400)];
            [c layoutSubtreeIfNeeded];
            // Assembled at run time; written as literals these would be real
            // secret shapes in a tracked file and checks/secrets.sh would
            // rightly block the commit.
            [c note:@"Free storage: 248145 MiB"];
            [c note:[@"error: credential AKIA" stringByAppendingString:@"ABCDEFGHIJKLMNOP rejected"]];
            [c note:[@"fatal: token ghp" stringByAppendingFormat:@"_%@",
                     [@"" stringByPaddingToLength:36 withString:@"a" startingAtIndex:0]]];
            [c note:[@"password" stringByAppendingString:@": hunter2correcthorse"]];
            NSString *seen = [c recentLinesForContext:40];
            check([seen containsString:@"248145"],
                  "the guide can read what the terminal actually showed");
            check(![seen containsString:@"ABCDEFGHIJKLMNOP"], "an access key never reaches it");
            check(![seen containsString:@"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
                  "nor a personal token");
            check(![seen containsString:@"hunter2correcthorse"], "nor a password");
            check([seen containsString:@"[redacted]"], "and it can see that something was removed");
        }

        // Real output from installing a coding app. npm prints an upgrade
        // notice with a changelog link, and that link was offered to the
        // operator as "a coding app needs you to sign in" — complete with a
        // Skip button belonging to a queue that was not running.
        {
            Watcher *w = signInFor(
                @"printf 'npm notice New major version of npm available!\n'; "
                @"printf 'npm notice Changelog: https://github.com/npm/cli/releases/tag/v12.0.2\n'; "
                @"printf '[OK] Codex CLI installed for this private VPS account.\n'; sleep 1");
            check(w.signInPage == nil,
                  "a link with no invitation around it is not a sign-in");
        }

        // The same link, with words that do mean sign in, must still work.
        {
            Watcher *w = signInFor(
                @"printf 'Sign in to continue:\n'; "
                @"printf '  https://auth.example.invalid/device\n'; "
                @"printf 'Enter the code AB12-CD34\n'; sleep 1");
            check(w.signInPage != nil, "a real invitation is still offered");
            check([w.signInCode isEqualToString:@"AB12-CD34"], "with its code");
        }

        // Real output from installing the Kimi CLI. It prints "Verifying
        // checksum" and its own download URLs, and every one of them was
        // offered to the operator as a page to sign in at.
        {
            Watcher *w = signInFor(
                @"printf '==> Downloading https://code.kimi.com/kimi-code/binaries/0.31.1/kimi-code-linux-x64\n'; "
                @"printf '==> Verifying checksum\n'; "
                @"printf '==> Installed to /home/slopnet/.kimi-code/bin/kimi\n'; sleep 1");
            check(w.signInPage == nil,
                  "verifying a checksum is not an invitation to sign in");
        }

        // Real output: npm prints its changelog link, then the sign-in starts.
        // Taking the first link opened npm's release notes in the operator's
        // browser and called it a sign-in page.
        {
            Watcher *w = signInFor(
                @"printf 'npm notice Changelog: https://github.com/npm/cli/releases/tag/v12.0.2\n'; "
                @"printf 'Signing in to Google Gemini. Your browser does the approving.\n'; "
                @"printf '  https://accounts.example.invalid/oauth2/device?user_code=WDJB-MJHT\n'; sleep 1");
            check(w.signInPage != nil, "a sign-in is offered");
            check(![w.signInPage.absoluteString containsString:@"npm/cli"],
                  "and it is not the npm changelog that happened to print first");
            check([w.signInPage.absoluteString containsString:@"oauth2/device"],
                  "it is the authorisation page");
        }

        // Real output: Gemini printed its terms-of-service link beside a
        // sign-in prompt, and that page was launched in the operator's browser.
        {
            Watcher *w = signInFor(
                @"printf 'How would you like to authenticate for this project?\n'; "
                @"printf 'Terms of Services and Privacy Notice\n'; "
                @"printf '  https://geminicli.com/docs/resources/tos-privacy/\n'; sleep 1");
            check(w.signInPage != nil, "the link is still offered as a button");
        }

    fprintf(stderr, failures == 0 ? "\nPROMPT PROBE DONE — all ok\n"
                                      : "\nPROMPT PROBE DONE — %d failed\n", failures);
    }
    return failures == 0 ? 0 : 1;
}
