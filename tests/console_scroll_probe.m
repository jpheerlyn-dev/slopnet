// console_scroll_probe.m — the console under a flood of output, which is what
// installing the local guide actually is.
//
// Two failures hide here and only show up under volume:
//
//   1. Every chunk read from the program rebuilt the whole buffer — up to four
//      thousand attributed lines — and handed it to NSTextView, which relaid
//      out the entire document. A build that prints thousands of lines turns
//      that into thousands of full rebuilds on the main thread, and the window
//      stops responding. Scrolling "not working" is the window not running.
//
//   2. Every redraw scrolled to the bottom unconditionally, so somebody who
//      scrolled up to read was yanked back down by the next line printed.
//
// Driven through a real program on the real PTY, so the chunking, the reader
// and the run loop are the ones the app uses.
//
//   clang -fobjc-arc -framework AppKit -framework CoreText -I packaging \
//     tests/console_scroll_probe.m packaging/SlopNetConsole.m \
//     packaging/SlopNetBrand.m -o /tmp/scroll_probe && /tmp/scroll_probe
#import <Cocoa/Cocoa.h>
#import "SlopNetConsole.h"

static int failures = 0;

static void check(BOOL ok, const char *what) {
    fprintf(stderr, "%s %s\n", ok ? "ok  " : "FAIL", what);
    if (!ok) failures++;
}

@interface Waiter : NSObject <SlopNetConsoleDelegate>
@property(nonatomic, assign) BOOL finished;
@end

@implementation Waiter
- (void)console:(SlopNetConsole *)c finishedWithStatus:(int)s { self.finished = YES; }
@end

/// Run a program and pump the run loop until it ends, exactly as the app does.
/// Returns how long the whole thing took.
static NSTimeInterval runToEnd(SlopNetConsole *console, Waiter *waiter,
                               NSString *script, NSTimeInterval limit) {
    waiter.finished = NO;
    NSDate *started = [NSDate date];
    [console runExecutable:@"/bin/bash" arguments:@[@"-c", script]];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:limit];
    while (!waiter.finished && [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return -[started timeIntervalSinceNow];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        SlopNetConsole *console =
            [[SlopNetConsole alloc] initWithFrame:NSMakeRect(0, 0, 900, 500)];
        Waiter *waiter = [Waiter new];
        console.delegate = waiter;
        NSWindow *window = [[NSWindow alloc]
            initWithContentRect:NSMakeRect(0, 0, 900, 500)
                      styleMask:NSWindowStyleMaskTitled
                        backing:NSBackingStoreBuffered
                          defer:NO];
        window.contentView = console;
        [console layoutSubtreeIfNeeded];

        // Three thousand lines of build chatter, printed as fast as the PTY
        // will carry it. Roughly the shape of compiling the guide's runtime.
        NSString *flood =
            @"for i in $(seq 1 3000); do "
            @"  if [ $((i % 7)) -eq 0 ]; then "
            @"    printf '\\033[32m[%3d%%]\\033[0m building object %d\\n' $((i % 100)) $i; "
            @"  else printf '  CC   src/module_%d.c -o build/module_%d.o\\n' $i $i; fi; "
            @"done";
        NSTimeInterval took = runToEnd(console, waiter, flood, 60);
        fprintf(stderr, "     3000 lines in %.2fs\n", took);

        // A window whose main thread is saturated cannot answer a scroll
        // wheel. The budget is loose on purpose: this exists to catch work
        // proportional to everything printed so far, repeated on every chunk.
        check(took < 6.0, "a flood of build output does not lock up the window");
        check([console.string containsString:@"module_3000.c"],
              "the last line printed is in the buffer");

        // Reading back through the output must survive new output arriving —
        // what every terminal does: follow the tail until somebody scrolls up,
        // then hold still until they come back.
        [console scrollToTopForTesting];
        CGFloat parked = [console scrollOffsetForTesting];
        runToEnd(console, waiter, @"printf 'a line while they are reading\\n'", 10);
        check(fabs([console scrollOffsetForTesting] - parked) < 4.0,
              "new output does not yank the view away from where they scrolled");
        check(![console isFollowingTailForTesting],
              "the console knows it is not at the tail");

        // Coming back to the bottom resumes following.
        [console scrollToBottomForTesting];
        runToEnd(console, waiter, @"printf 'following again\\n'", 10);
        check([console isFollowingTailForTesting],
              "returning to the bottom resumes following new output");
        check([console.string containsString:@"following again"],
              "and the newest line is there to be seen");

        [console stop];
        fprintf(stderr, failures == 0 ? "\nSCROLL PROBE DONE — all ok\n"
                                      : "\nSCROLL PROBE DONE — %d failed\n", failures);
    }
    return failures == 0 ? 0 : 1;
}
