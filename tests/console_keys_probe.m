// console_keys_probe.m — a running program can be answered with key presses.
//
// A full-screen program reads arrow keys as escape sequences and Enter as a
// carriage return. Sending only finished lines meant a menu could be shown and
// never navigated, which is what made a coding-app sign-in look frozen.
#import <Cocoa/Cocoa.h>
#import "SlopNetConsole.h"

static int failures = 0;
static void check(BOOL ok, const char *what) {
    fprintf(stderr, "%s %s\n", ok ? "ok  " : "FAIL", what);
    if (!ok) failures++;
}

@interface Silent : NSObject <SlopNetConsoleDelegate>
@property(nonatomic, assign) BOOL finished;
@end
@implementation Silent
- (void)console:(SlopNetConsole *)c finishedWithStatus:(int)s { self.finished = YES; }
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        SlopNetConsole *console =
            [[SlopNetConsole alloc] initWithFrame:NSMakeRect(0, 0, 900, 400)];
        [console layoutSubtreeIfNeeded];
        Silent *silent = [Silent new];
        console.delegate = silent;

        // A program that reads raw bytes and reports what it saw, so the exact
        // escape sequence is checked rather than assumed.
        [console runExecutable:@"/bin/bash" arguments:@[@"-c",
            @"IFS= read -r -n 3 -s k; printf 'got:%s\\n' \"$(printf %s \"$k\" | od -An -c | tr -d ' \\n')\""]];

        NSDate *settle = [NSDate dateWithTimeIntervalSinceNow:0.6];
        while ([settle timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        check(console.running, "a program is running and can be typed at");

        [console sendKeys:@"\033[B"];             // down arrow
        NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:3];
        while (!silent.finished && [limit timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        NSString *shown = console.textForTesting;
        check([shown containsString:@"033"] && [shown containsString:@"["],
              "a down arrow arrives as its escape sequence, not as text");
        check(![shown containsString:@"\n\n\n"], "and nothing extra is sent with it");

        fprintf(stderr, failures == 0 ? "\nKEYS PROBE DONE — all ok\n"
                                      : "\nKEYS PROBE DONE — %d failed\n", failures);
    }
    return failures == 0 ? 0 : 1;
}
