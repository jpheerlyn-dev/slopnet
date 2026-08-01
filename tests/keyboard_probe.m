// keyboard_probe.m — does a key pressed in the window reach the program?
//
// Every check of this until now was written against my own idea of the path
// and passed while the app did nothing. This one builds the real typing box in
// a real window, runs a real program on a real pseudo-terminal, posts a real
// key event through the window the way AppKit does, and reads back the bytes
// the program actually received.
//
// It reports what arrived rather than only passing or failing, because the
// question that mattered for a whole day was "is anything arriving at all".
//
//   clang -fobjc-arc -framework AppKit -framework CoreText -I packaging \
//     tests/keyboard_probe.m packaging/SlopNetConsole.m packaging/SlopNetBrand.m \
//     packaging/SlopNetEntryView.m -o /tmp/kb && /tmp/kb
#import <Cocoa/Cocoa.h>
#import "SlopNetBrand.h"
#import "SlopNetConsole.h"
#import "SlopNetEntryView.h"

static int failures = 0;

static void check(BOOL ok, const char *what) {
    fprintf(stderr, "%s %s\n", ok ? "ok  " : "FAIL", what);
    if (!ok) failures++;
}

@interface Quiet : NSObject <SlopNetConsoleDelegate>
@property(nonatomic, assign) BOOL finished;
@end
@implementation Quiet
- (void)console:(SlopNetConsole *)c asksFor:(SlopNetPrompt)p question:(NSString *)q {
    (void)c; (void)p; (void)q;
}
- (void)consoleFinished:(SlopNetConsole *)c ok:(BOOL)ok {
    (void)c; (void)ok; self.finished = YES;
}
@end

static void settle(double seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([until timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
}

/// One key press, as AppKit delivers it: through the window, to whatever holds
/// the keyboard. Nothing here calls the console directly, because calling the
/// console directly is what kept passing while the app did nothing.
static NSEvent *press(NSString *characters, NSString *bare,
                      NSEventModifierFlags flags, unsigned short code) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown
                            location:NSZeroPoint
                       modifierFlags:flags
                           timestamp:[NSProcessInfo processInfo].systemUptime
                        windowNumber:0
                             context:nil
                          characters:characters
         charactersIgnoringModifiers:bare
                           isARepeat:NO
                             keyCode:code];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSWindow *window = [[NSWindow alloc]
            initWithContentRect:NSMakeRect(0, 0, 900, 700)
                      styleMask:NSWindowStyleMaskTitled
                        backing:NSBackingStoreBuffered
                          defer:NO];

        SlopNetConsole *console =
            [[SlopNetConsole alloc] initWithFrame:NSMakeRect(0, 100, 900, 560)];
        SlopNetEntryView *entry =
            [[SlopNetEntryView alloc] initWithFrame:NSMakeRect(0, 0, 900, 90)];
        [window.contentView addSubview:console];
        [window.contentView addSubview:entry];
        [console layoutSubtreeIfNeeded];
        entry.console = console;

        Quiet *quiet = [Quiet new];
        console.delegate = quiet;

        // A program that takes its own screen, then reports the exact bytes it
        // is given. The alternate screen is what turns raw input on, so this is
        // the state a tool like Zellij puts the terminal in.
        NSString *reader =
            // Deliberately no stty here. The program does what a real one
            // does — takes the alternate screen and reads bytes — and leaves
            // the line discipline to the terminal. With the terminal left
            // collecting whole lines, a single key never arrives at all, which
            // is exactly what happened in the app while every check passed.
            @"printf '\\033[?1049h'; "
            @"head -c 2 | od -An -c | tr -d ' \\n' | sed 's/^/got:/'; printf '\\n'";
        [console runExecutable:@"/bin/bash" arguments:@[@"-c", reader]];
        settle(1.0);

        check(console.running, "a program is running on a real pseudo-terminal");
        check(console.rawInputActive,
              "the program has taken the alternate screen, so keys go straight through");

        BOOL took = [window makeFirstResponder:entry];
        check(took && window.firstResponder == entry,
              "the typing box can hold the keyboard");

        // Control-G: what Zellij's own shortcut bar tells you to press.
        [window sendEvent:press(@"\a", @"g", NSEventModifierFlagControl, 5)];
        settle(0.2);
        NSString *afterControlG = entry.prompt ?: @"";
        [window sendEvent:press(@"p", @"p", 0, 35)];
        settle(1.5);

        NSString *shown = console.textForTesting;
        NSRange at = [shown rangeOfString:@"got:"];
        NSString *arrived = @"(nothing arrived)";
        if (at.location != NSNotFound) {
            NSString *rest = [shown substringFromIndex:NSMaxRange(at)];
            NSRange end = [rest rangeOfString:@"\n"];
            arrived = end.location == NSNotFound ? rest : [rest substringToIndex:end.location];
        }
        fprintf(stderr, "\n    the program received: %s\n\n", arrived.UTF8String);

        // od spells 0x07 as \a, which is what the program actually reports.
        check([arrived containsString:@"\\a"],
              "Control-G pressed in the window reaches the program as 0x07");
        check([arrived containsString:@"p"],
              "and the letter after it arrives too");

        // The readout is the point of this: the operator must be able to see
        // that a key was received, on a screen that otherwise looks the same
        // whether the tool is listening or dead.
        fprintf(stderr, "    the box now reads: %s\n\n", entry.prompt.UTF8String);
        check([afterControlG containsString:@"Ctrl+g"],
              "the box names the key it just passed to the tool");

        [console stop];
        fprintf(stderr, failures == 0 ? "\nKEYBOARD PROBE DONE — all ok\n"
                                      : "\nKEYBOARD PROBE DONE — %d failed\n", failures);
    }
    return failures == 0 ? 0 : 1;
}
