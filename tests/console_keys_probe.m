// console_keys_probe.m — a running program can be answered with key presses.
//
// A full-screen program reads arrow keys as escape sequences and Enter as a
// carriage return. Sending only finished lines meant a menu could be shown and
// never navigated, which is what made a coding-app sign-in look frozen.
#import <Cocoa/Cocoa.h>
#import "SlopNetConsole.h"
#import "SlopNetEntryView.h"

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

/// Runs a program that reports the exact bytes it read, optionally after
/// putting the terminal into a mode first, and returns what arrived.
static NSString *arrival(NSString *setup, SlopNetKey key) {
    SlopNetConsole *console =
        [[SlopNetConsole alloc] initWithFrame:NSMakeRect(0, 0, 900, 400)];
    [console layoutSubtreeIfNeeded];
    Silent *silent = [Silent new];
    console.delegate = silent;
    [console runExecutable:@"/bin/bash" arguments:@[@"-c",
        [NSString stringWithFormat:
         @"%@IFS= read -r -n 3 -s k; "
         @"printf 'got:%%s\\n' \"$(printf %%s \"$k\" | od -An -c | tr -d ' \\n')\"",
         setup]]];
    NSDate *settle = [NSDate dateWithTimeIntervalSinceNow:0.8];
    while ([settle timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    if (!console.running) return @"the program never started";
    [console sendKey:key];
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!silent.finished && [limit timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    NSString *shown = console.textForTesting;
    [console stop];
    NSRange at = [shown rangeOfString:@"got:"];
    if (at.location == NSNotFound) return @"nothing arrived";
    NSString *rest = [shown substringFromIndex:NSMaxRange(at)];
    NSRange end = [rest rangeOfString:@"\n"];
    return end.location == NSNotFound ? rest : [rest substringToIndex:end.location];
}

static NSEvent *keyEvent(NSString *characters, NSString *plain,
                         NSEventModifierFlags modifiers, unsigned short keyCode) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown
                            location:NSZeroPoint
                       modifierFlags:modifiers
                           timestamp:0
                        windowNumber:0
                             context:nil
                          characters:characters
         charactersIgnoringModifiers:plain
                           isARepeat:NO
                             keyCode:keyCode];
}

/// A real key-at-a-time reader takes the alternate screen, then reports the
/// exact bytes sent through the entry view's raw-input path.
static NSString *rawArrival(NSArray<NSEvent *> *events) {
    SlopNetConsole *console =
        [[SlopNetConsole alloc] initWithFrame:NSMakeRect(0, 0, 900, 400)];
    [console layoutSubtreeIfNeeded];
    Silent *silent = [Silent new];
    console.delegate = silent;
    SlopNetEntryView *entry = [[SlopNetEntryView alloc] initWithFrame:NSMakeRect(0, 0, 500, 60)];
    entry.console = console;
    NSString *reader =
        @"printf '\033[?1049h'; stty raw -echo; "
         "bytes=$(head -c 2 | od -An -tx1 | tr -d ' \n'); "
         "stty sane; printf '\033[?1049lgot:%s\n' \"$bytes\"";
    [console runExecutable:@"/bin/bash" arguments:@[@"-c", reader]];

    NSDate *ready = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!console.rawInputActive && console.running && [ready timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    if (!console.rawInputActive) {
        [console stop];
        return @"the alternate screen never became active";
    }
    for (NSEvent *event in events) {
        [entry keyDown:event];
    }
    if (entry.string.length != 0) {
        [console stop];
        return @"a raw key entered the line box";
    }

    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!silent.finished && [limit timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    NSString *shown = console.textForTesting;
    [console stop];
    NSRange at = [shown rangeOfString:@"got:"];
    if (at.location == NSNotFound) return @"nothing arrived";
    NSString *rest = [shown substringFromIndex:NSMaxRange(at)];
    NSRange end = [rest rangeOfString:@"\n"];
    return end.location == NSNotFound ? rest : [rest substringToIndex:end.location];
}

/// Reuse one console across two real PTYs. The first exits without undoing
/// DECCKM; the second must still begin in normal cursor-key mode.
static NSString *arrivalAfterUncleanModeExit(void) {
    SlopNetConsole *console =
        [[SlopNetConsole alloc] initWithFrame:NSMakeRect(0, 0, 900, 400)];
    [console layoutSubtreeIfNeeded];
    Silent *silent = [Silent new];
    console.delegate = silent;
    [console runExecutable:@"/bin/bash"
                 arguments:@[@"-c", @"printf '\033[?1h'"]];
    NSDate *firstLimit = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!silent.finished && firstLimit.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    silent.finished = NO;
    NSString *reader =
        @"stty raw -echo; bytes=$(head -c 3 | od -An -tx1 | tr -d ' \\n'); "
         "stty sane; printf 'got:%s\\n' \"$bytes\"";
    [console runExecutable:@"/bin/bash" arguments:@[@"-c", reader]];
    NSDate *ready = [NSDate dateWithTimeIntervalSinceNow:0.3];
    while (ready.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
    [console sendKey:SlopNetKeyUp];
    NSDate *secondLimit = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!silent.finished && secondLimit.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    NSString *shown = console.textForTesting;
    [console stop];
    NSRange at = [shown rangeOfString:@"got:" options:NSBackwardsSearch];
    if (at.location == NSNotFound) return @"nothing arrived";
    NSString *rest = [shown substringFromIndex:NSMaxRange(at)];
    NSRange end = [rest rangeOfString:@"\n"];
    return end.location == NSNotFound ? rest : [rest substringToIndex:end.location];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        check([arrival(@"", SlopNetKeyDown) isEqualToString:@"033[B"],
              "an ordinary program gets a down arrow as ESC [ B");

        // What a full-screen program does. Antigravity's sign-in menu turns
        // this mode on, and until now it was parsed and thrown away, so the
        // arrows it was sent were ones it does not listen for.
        check([arrival(@"printf '\\033[?1h'; ", SlopNetKeyUp) isEqualToString:@"033OA"],
              "in application cursor key mode an up arrow arrives as ESC O A");
        check([arrival(@"printf '\\033[?1h\\033[?1l'; ", SlopNetKeyUp)
               isEqualToString:@"033[A"],
              "and turning the mode back off restores ESC [ A");
        // A program that hides its cursor must not be read as changing it.
        check([arrival(@"printf '\\033[?25l'; ", SlopNetKeyDown) isEqualToString:@"033[B"],
              "an unrelated private mode leaves cursor keys alone");
        check([arrivalAfterUncleanModeExit() isEqualToString:@"1b5b41"],
              "a new PTY does not inherit application cursor mode from the previous child");

        NSEvent *controlG = keyEvent(@"\007", @"g", NSEventModifierFlagControl, 5);
        NSEvent *letterP = keyEvent(@"p", @"p", 0, 35);
        NSString *rawKeys = rawArrival(@[controlG, letterP]);
        if (![rawKeys isEqualToString:@"0770"]) {
            fprintf(stderr, "     received: %s\n", rawKeys.UTF8String);
        }
        check([rawKeys isEqualToString:@"0770"],
              "alternate-screen input sends Ctrl-G and p immediately as 07 70");

        // Sending a typed line, both ways a program can be reading.
        {
            // Reading whole lines, as a shell or a password prompt does. The
            // terminal turns the carriage return into a newline, so this is
            // unaffected.
            SlopNetConsole *c = [[SlopNetConsole alloc] initWithFrame:NSMakeRect(0,0,900,400)];
            [c layoutSubtreeIfNeeded];
            Silent *s = [Silent new];
            c.delegate = s;
            [c runExecutable:@"/bin/bash" arguments:@[@"-c",
                @"IFS= read -r line; printf 'line:%s\\n' \"$line\""]];
            NSDate *ready = [NSDate dateWithTimeIntervalSinceNow:0.6];
            while ([ready timeIntervalSinceNow] > 0) {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                         beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            }
            SlopNetEntryView *lineEntry =
                [[SlopNetEntryView alloc] initWithFrame:NSMakeRect(0,0,500,60)];
            lineEntry.console = c;
            NSWindow *lineWindow = [[NSWindow alloc]
                initWithContentRect:NSMakeRect(0,0,500,60)
                          styleMask:NSWindowStyleMaskBorderless
                            backing:NSBackingStoreBuffered
                              defer:NO];
            [lineWindow.contentView addSubview:lineEntry];
            [lineWindow makeFirstResponder:lineEntry];
            NSEvent *lineP = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                               location:NSZeroPoint
                                          modifierFlags:0
                                              timestamp:0
                                           windowNumber:lineWindow.windowNumber
                                                context:nil
                                             characters:@"p"
                            charactersIgnoringModifiers:@"p"
                                              isARepeat:NO
                                                keyCode:35];
            [lineEntry keyDown:lineP];
            check([lineEntry.string isEqualToString:@"p"],
                  "an ordinary screen keeps typed characters in the line box");
            [c sendLine:lineEntry.string];
            NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:3];
            while (!s.finished && [limit timeIntervalSinceNow] > 0) {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                         beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            }
            check([c.textForTesting containsString:@"line:p"],
                  "a program reading whole lines still receives the line");
            [c stop];
        }
        {
            // Reading keys as they arrive, as anything drawing its own
            // interface does. It is watching for a carriage return; a newline
            // is not it, and a message sent that way is never submitted.
            SlopNetConsole *c = [[SlopNetConsole alloc] initWithFrame:NSMakeRect(0,0,900,400)];
            [c layoutSubtreeIfNeeded];
            Silent *s = [Silent new];
            c.delegate = s;
            NSString *reader =
                @"stty raw -echo; head -c 3 | od -An -c | tr -d ' \\n' "
                @"| sed 's/^/got:/'; printf '\\n'";
            [c runExecutable:@"/bin/bash" arguments:@[@"-c", reader]];
            NSDate *ready = [NSDate dateWithTimeIntervalSinceNow:0.8];
            while ([ready timeIntervalSinceNow] > 0) {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                         beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            }
            [c sendLine:@"ab"];
            NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:3];
            while (!s.finished && [limit timeIntervalSinceNow] > 0) {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                         beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            }
            check([c.textForTesting containsString:@"got:ab\\r"],
                  "a program reading keys sees the carriage return it waits for");
            [c stop];
        }

        fprintf(stderr, failures == 0 ? "\nKEYS PROBE DONE — all ok\n"
                                      : "\nKEYS PROBE DONE — %d failed\n", failures);
    }
    return failures == 0 ? 0 : 1;
}
