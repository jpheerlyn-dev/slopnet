// console_menu_probe.m — proves a menu that redraws itself stays one menu.
//
// The operator pressed down, then up, and the sign-in menu walked down the
// screen leaving a trail of "> " markers, having overwritten the first two
// characters of its own hint line. Keys were reaching the program by then —
// the selection did move — so this is the console failing to render what came
// back.
//
// A menu redrawing in place has to put the cursor back where the old frame
// started. There are three usual ways to do that and the console swallowed
// two of them, so the cursor never went back up and every frame landed lower
// than the last. This drives a real program through the real PTY for each way
// and checks the screen holds one menu with the marker in the right place.
//
//   clang -fobjc-arc -framework AppKit -framework CoreText -I packaging \
//     tests/console_menu_probe.m packaging/SlopNetConsole.m \
//     packaging/SlopNetBrand.m -o /tmp/menu_probe && /tmp/menu_probe
#import <Cocoa/Cocoa.h>
#import "SlopNetBrand.h"
#import "SlopNetConsole.h"

static int failures = 0;

static void check(BOOL ok, const char *what) {
    fprintf(stderr, "%s %s\n", ok ? "ok  " : "FAIL", what);
    if (!ok) failures++;
}

@interface Quiet : NSObject <SlopNetConsoleDelegate>
@end
@implementation Quiet
- (void)console:(SlopNetConsole *)c asksFor:(SlopNetPrompt)p question:(NSString *)q {
    (void)c; (void)p; (void)q;
}
@end

static NSUInteger occurrences(NSString *haystack, NSString *needle) {
    NSUInteger count = 0, at = 0;
    while (at < haystack.length) {
        NSRange found = [haystack rangeOfString:needle
                                        options:0
                                          range:NSMakeRange(at, haystack.length - at)];
        if (found.location == NSNotFound) break;
        count++;
        at = NSMaxRange(found);
    }
    return count;
}

static void settle(double seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([until timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
}

/// Runs the fixture in one redraw style, presses down then up, and returns
/// what the screen holds afterwards.
static NSString *screenAfterDownThenUp(NSString *style, NSString *fixture) {
    SlopNetConsole *console =
        [[SlopNetConsole alloc] initWithFrame:NSMakeRect(0, 0, 900, 400)];
    [console layoutSubtreeIfNeeded];
    Quiet *quiet = [Quiet new];
    console.delegate = quiet;
    [console runExecutable:@"/usr/bin/python3" arguments:@[fixture, style]];
    settle(1.2);
    if (!console.running) return @"the fixture never started";
    [console sendKey:SlopNetKeyDown];
    settle(0.6);
    [console sendKey:SlopNetKeyUp];
    settle(0.6);
    NSString *shown = console.textForTesting;
    [console sendKeys:@"q"];
    settle(0.2);
    [console stop];
    return shown;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *fixture = argc > 1 ? @(argv[1]) : @"tests/menu_fixture.py";

        NSArray<NSString *> *styles = @[@"up", @"save", @"screen"];
        NSDictionary<NSString *, NSString *> *how = @{
            @"up":     @"a menu that moves the cursor back up to redraw",
            @"save":   @"a menu that saves its starting point and returns to it",
            @"screen": @"a full-screen program redrawing from the top",
        };

        for (NSString *style in styles) {
            NSString *shown = screenAfterDownThenUp(style, fixture);
            NSString *why = how[style];

            check(occurrences(shown, @"Select login method:") == 1,
                  [NSString stringWithFormat:@"%@ is drawn once, not once per keypress",
                   why].UTF8String);

            // Down then up puts the marker back on the first item. A stale
            // frame left behind would show it on both.
            check(occurrences(shown, @"> 1. Google OAuth") == 1 &&
                  occurrences(shown, @"> 2. Use a Google Cloud project") == 0,
                  [NSString stringWithFormat:@"%@ ends with one marker, on the first item",
                   why].UTF8String);

            // The trail the operator photographed: a marker on a line of its
            // own, left by a frame that landed lower than the one before it.
            check(occurrences(shown, @"\n> \n") == 0,
                  [NSString stringWithFormat:@"%@ leaves no stray markers behind",
                   why].UTF8String);
        }

        // The reason the frames diverged in the first place. A program is
        // told how wide the window is and prints a long line expecting the
        // terminal to move to the next row at the edge; if it does not, the
        // program's idea of where the cursor is drifts further off with every
        // line, and its next redraw lands somewhere else entirely.
        {
            SlopNetConsole *console =
                [[SlopNetConsole alloc] initWithFrame:NSMakeRect(0, 0, 900, 400)];
            [console layoutSubtreeIfNeeded];
            Quiet *quiet = [Quiet new];
            console.delegate = quiet;
            NSUInteger width = console.columns;
            NSUInteger length = width * 3 + 7;
            [console runExecutable:@"/bin/bash" arguments:@[@"-c",
                [NSString stringWithFormat:
                 @"printf 'x%%.0s' $(seq %lu); printf '\\n'; sleep 2",
                 (unsigned long)length]]];
            settle(1.2);
            NSString *shown = console.textForTesting;
            [console stop];

            NSUInteger longest = 0, rows = 0;
            for (NSString *row in [shown componentsSeparatedByString:@"\n"]) {
                if (row.length == 0) continue;
                rows++;
                if (row.length > longest) longest = row.length;
            }
            check(longest <= width,
                  "no row is drawn wider than the window the program was told about");
            check(rows >= 4,
                  "a line three windows long takes four rows, as the program expects");
        }

        fprintf(stderr, failures == 0 ? "\nMENU PROBE DONE — all ok\n"
                                      : "\nMENU PROBE DONE — %d failed\n", failures);
    }
    return failures == 0 ? 0 : 1;
}
