// console_colour_probe.m — proves the console keeps colour, and still
// overwrites in place.
//
// The console used to throw ANSI colour away and paint the whole buffer in one
// font and one colour, which is what flattened the StormCode panels. Colour is
// now stored per run of text, so this checks the three things that can quietly
// regress: 24-bit foreground and background land on the right characters, a
// progress line overwritten by \r keeps the NEW colour, and a private-mode
// sequence like hiding the cursor leaves no digits in the output.
//
//   clang -fobjc-arc -framework AppKit -framework CoreText -I packaging \
//     tests/console_colour_probe.m packaging/SlopNetConsole.m \
//     packaging/SlopNetBrand.m -o /tmp/colour_probe && /tmp/colour_probe
#import <Cocoa/Cocoa.h>
#import "SlopNetBrand.h"
#import "SlopNetConsole.h"

static int failures = 0;

/// Waits for a real child to finish, so the probe also covers the PTY path.
@interface Waiter : NSObject <SlopNetConsoleDelegate>
@property(nonatomic, assign) BOOL finished;
@property(nonatomic, assign) int status;
@end

@implementation Waiter
- (void)console:(SlopNetConsole *)console finishedWithStatus:(int)status {
    self.status = status;
    self.finished = YES;
}
@end

static void check(BOOL ok, const char *what) {
    fprintf(stderr, "%s %s\n", ok ? "ok  " : "FAIL", what);
    if (!ok) failures++;
}

/// The console owns its text view privately; the probe reads what the view
/// actually holds, which is the thing a person sees.
static NSTextView *textViewOf(SlopNetConsole *console) {
    for (NSView *view in console.subviews) {
        if ([view isKindOfClass:NSScrollView.class]) {
            NSView *document = ((NSScrollView *)view).documentView;
            if ([document isKindOfClass:NSTextView.class]) return (NSTextView *)document;
        }
    }
    return nil;
}

static NSColor *colourAt(NSTextView *view, NSUInteger index, NSString *attribute) {
    if (index >= view.textStorage.length) return nil;
    NSColor *colour = [view.textStorage attribute:attribute atIndex:index effectiveRange:NULL];
    return [colour colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
}

static BOOL isRGB(NSColor *colour, int r, int g, int b) {
    if (colour == nil) return NO;
    return (lround(colour.redComponent * 255) == r &&
            lround(colour.greenComponent * 255) == g &&
            lround(colour.blueComponent * 255) == b);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        SlopNetConsole *console = [[SlopNetConsole alloc] initWithFrame:NSMakeRect(0, 0, 900, 500)];
        [console layoutSubtreeIfNeeded];
        NSTextView *view = textViewOf(console);
        check(view != nil, "console exposes its text view");
        if (view == nil) return 1;

        // 24-bit foreground, then a 24-bit background run, on one line.
        [console note:@"\033[38;2;255;0;60mRED\033[0m\033[48;2;34;199;217mFIELD\033[0m"];
        NSString *text = view.textStorage.string;
        NSUInteger red = [text rangeOfString:@"RED"].location;
        NSUInteger field = [text rangeOfString:@"FIELD"].location;
        check(red != NSNotFound && field != NSNotFound, "both runs reached the buffer");
        check(isRGB(colourAt(view, red, NSForegroundColorAttributeName), 255, 0, 60),
              "38;2;255;0;60 became the crimson foreground");
        check(isRGB(colourAt(view, field, NSBackgroundColorAttributeName), 34, 199, 217),
              "48;2;34;199;217 became the Poolside background");
        check(colourAt(view, red, NSBackgroundColorAttributeName) == nil,
              "a foreground-only run takes no background");

        // 256-colour and the named 8: both still have to work, because ssh,
        // apt and git all use them.
        [console note:@"\033[38;5;196mX\033[0m\033[32mY\033[0m"];
        text = view.textStorage.string;
        check(isRGB(colourAt(view, [text rangeOfString:@"X"].location,
                             NSForegroundColorAttributeName), 255, 0, 0),
              "38;5;196 resolved through the 256-colour cube");
        check(isRGB(colourAt(view, [text rangeOfString:@"Y"].location,
                             NSForegroundColorAttributeName), 0, 205, 0),
              "SGR 32 resolved to the named green");

        // A progress line rewritten in place: same row, new colour, and the
        // old text must be gone rather than left behind it.
        [console note:@"\033[31mworking 1/3\033[0m"
                      @"\r\033[38;2;0;171;35mdone       \033[0m"];
        text = view.textStorage.string;
        check([text rangeOfString:@"working"].location == NSNotFound,
              "\\r overwrote the progress line instead of repeating it");
        NSUInteger done = [text rangeOfString:@"done"].location;
        check(done != NSNotFound &&
              isRGB(colourAt(view, done, NSForegroundColorAttributeName), 0, 171, 35),
              "the overwriting run kept its own colour");

        // Hiding and showing the cursor must not leave "25l" in the text.
        [console note:@"\033[?25lhidden\033[?25h"];
        text = view.textStorage.string;
        check([text rangeOfString:@"25l"].location == NSNotFound &&
              [text rangeOfString:@"hidden"].location != NSNotFound,
              "a private-mode sequence left no digits behind");

        // A replaceable block is what an animation redraws. The token must
        // still address the same rows afterwards.
        NSInteger token = [console noteReplaceable:@"\033[38;2;255;0;60mframe A\033[0m"];
        check([view.textStorage.string rangeOfString:@"frame A"].location != NSNotFound,
              "a replaceable block printed");
        check([console replaceLinesFromToken:token
                                        with:@"\033[38;2;0;171;35mframe B\033[0m"],
              "the block accepted a redraw");
        text = view.textStorage.string;
        check([text rangeOfString:@"frame A"].location == NSNotFound &&
              [text rangeOfString:@"frame B"].location != NSNotFound,
              "the redraw replaced the frame in place");
        check(isRGB(colourAt(view, [text rangeOfString:@"frame B"].location,
                             NSForegroundColorAttributeName), 0, 171, 35),
              "the redrawn frame carries its new colour");

        // After clearing, an old animation token must be refused rather than
        // overwriting whatever now occupies those rows.
        [console clear];
        check(![console replaceLinesFromToken:token with:@"stale"],
              "a token from before clear is refused");

        check(console.columns >= 40, "the console reports a usable width");

        // The PTY path, end to end: a real child on a real pseudo-terminal,
        // printing 24-bit colour. This is the regression that matters most —
        // the parser rewrite must not have changed what a program sees or how
        // its output arrives.
        Waiter *waiter = [Waiter new];
        console.delegate = waiter;
        NSString *script =
            @"printf '\\033[38;2;123;115;255mchild truecolor\\033[0m\\n'; "
            @"printf 'TERM=%s\\n' \"$TERM\"";
        check([console runExecutable:@"/bin/bash" arguments:@[@"-c", script]],
              "a child started on the PTY");
        NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:10];
        while (!waiter.finished && [limit timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        check(waiter.finished && waiter.status == 0, "the child ran and exited cleanly");
        text = view.textStorage.string;
        NSUInteger childRun = [text rangeOfString:@"child truecolor"].location;
        check(childRun != NSNotFound, "the child's output reached the console");
        check(childRun != NSNotFound &&
              isRGB(colourAt(view, childRun, NSForegroundColorAttributeName), 123, 115, 255),
              "the child's 24-bit colour survived the PTY");
        check([text rangeOfString:@"TERM=xterm-256color"].location != NSNotFound,
              "the child still sees TERM=xterm-256color");

        fprintf(stderr, failures == 0 ? "\nCOLOUR PROBE DONE — all ok\n"
                                      : "\nCOLOUR PROBE DONE — %d failed\n", failures);
    }
    return failures == 0 ? 0 : 1;
}
