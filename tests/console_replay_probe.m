// console_replay_probe.m — replays a real recording through the console.
//
// Every fixture written for the sign-in link was invented from a guess about
// what Antigravity prints, and one of them passed with the fix removed — it
// was not reproducing the failure at all. This takes a recording of the real
// thing instead: the exact bytes `agy login` wrote to a pseudo-terminal on a
// server, captured at the width the console actually uses.
//
// It replays them in pieces, because how a read happens to be cut up changes
// what the console has seen when it looks for a link, and prints the address
// that would be opened. Pass the expected address as the second argument to
// have it checked.
//
//   clang -fobjc-arc -framework AppKit -framework CoreText -I packaging \
//     tests/console_replay_probe.m packaging/SlopNetConsole.m \
//     packaging/SlopNetBrand.m -o /tmp/replay && /tmp/replay recording.bin
#import <Cocoa/Cocoa.h>
#import "SlopNetBrand.h"
#import "SlopNetConsole.h"

static int failures = 0;

static void check(BOOL ok, const char *what) {
    fprintf(stderr, "%s %s\n", ok ? "ok  " : "FAIL", what);
    if (!ok) failures++;
}

@interface Catcher : NSObject <SlopNetConsoleDelegate>
@property(nonatomic, strong) NSURL *page;
@property(nonatomic, assign) NSInteger offers;
@end
@implementation Catcher
- (void)console:(SlopNetConsole *)c asksFor:(SlopNetPrompt)p question:(NSString *)q {
    (void)c; (void)p; (void)q;
}
- (void)console:(SlopNetConsole *)c needsSignIn:(NSURL *)page code:(NSString *)code {
    (void)c; (void)code;
    if (self.page == nil) self.page = page;
    self.offers++;
}
@end

/// Replays the recording in chunks of a given size and returns what would be
/// opened. The size matters: it decides how much the console has seen each
/// time it looks, which is exactly what differed between the fixtures that
/// passed and the failure the operator hit.
static NSURL *replay(NSData *recording, NSUInteger chunk, NSInteger *offers,
                     NSString **rendered) {
    SlopNetConsole *console =
        [[SlopNetConsole alloc] initWithFrame:NSMakeRect(0, 0, 900, 400)];
    [console layoutSubtreeIfNeeded];
    Catcher *catcher = [Catcher new];
    console.delegate = catcher;
    // Long enough to outlive every replay. At four seconds it expired part way
    // through the set, and the console noted the program had finished on
    // whichever screen was unlucky — a difference in the recording's rendering
    // that had nothing to do with the recording.
    [console runExecutable:@"/bin/bash" arguments:@[@"-c", @"sleep 600"]];
    NSDate *ready = [NSDate dateWithTimeIntervalSinceNow:0.5];
    while ([ready timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    for (NSUInteger at = 0; at < recording.length; at += chunk) {
        NSUInteger take = MIN(chunk, recording.length - at);
        [console consumeBytes:[recording subdataWithRange:NSMakeRange(at, take)]];
    }
    // Let the console notice that the program has stopped writing.
    NSDate *quiet = [NSDate dateWithTimeIntervalSinceNow:1.2];
    while ([quiet timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    if (offers) *offers = catcher.offers;
    // Copied deliberately. This hands back the console's own text, which the
    // console goes on changing — a capture kept for comparison later picked up
    // notes written after it was taken, and read as a difference in the
    // recording's rendering.
    if (rendered) *rendered = [console.textForTesting copy];
    NSURL *page = catcher.page;
    [console stop];
    return page;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        if (argc < 2) {
            fprintf(stderr, "usage: replay <recording.bin> [expected-address]\n");
            return 2;
        }
        NSData *recording = [NSData dataWithContentsOfFile:@(argv[1])];
        if (recording == nil) {
            fprintf(stderr, "cannot read %s\n", argv[1]);
            return 2;
        }
        NSString *expected = (argc > 2 && strlen(argv[2]) > 0) ? @(argv[2]) : nil;
        // Something that must appear on the drawn screen. For a conversation
        // that is the reply: it was arriving in the bytes all along and being
        // erased before it could be seen.
        NSString *mustShow = (argc > 3 && strlen(argv[3]) > 0) ? @(argv[3]) : nil;

        // Whole, and cut up the way a pseudo-terminal actually delivers it.
        NSArray<NSNumber *> *sizes = @[@(recording.length), @4096, @1024, @137];
        NSMutableArray<NSString *> *screens = [NSMutableArray array];
        for (NSNumber *size in sizes) {
            NSInteger offers = 0;
            NSString *drawn = nil;
            NSURL *page = replay(recording, size.unsignedIntegerValue, &offers, &drawn);
            [screens addObject:drawn ?: @""];
            if (getenv("REPLAY_DUMP")) {
                [(drawn ?: @"") writeToFile:[NSString stringWithFormat:@"/tmp/screen_%@.txt", size]
                                 atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }
            fprintf(stderr, "\n--- delivered in %lu-byte pieces, offered %ld time(s)\n",
                    (unsigned long)size.unsignedIntegerValue, (long)offers);
            fprintf(stderr, "    %s\n", page ? page.absoluteString.UTF8String : "(nothing offered)");
            if (expected != nil) {
                check(page != nil && [page.absoluteString isEqualToString:expected],
                      [NSString stringWithFormat:
                       @"the address opened is the one the program printed (%lu-byte pieces)",
                       (unsigned long)size.unsignedIntegerValue].UTF8String);
            }
        }

        if (mustShow != nil) {
            for (NSUInteger i = 0; i < screens.count; i++) {
                check([screens[i] containsString:mustShow],
                      [NSString stringWithFormat:@"%@ is on the screen (%@-byte pieces)",
                       mustShow, sizes[i]].UTF8String);
            }
        }

        // How the bytes are cut up is an accident of timing and has nothing to
        // do with what the program drew, so it must not change what is drawn.
        // An escape sequence split across two reads used to lose its ESC — the
        // rest printed as text, and the cursor move it asked for never
        // happened, so every frame after it landed in the wrong place.
        for (NSUInteger i = 1; i < screens.count; i++) {
            if (![screens[i] isEqualToString:screens[0]]) {
                NSString *a = screens[0], *b = screens[i];
                NSUInteger at = 0;
                while (at < a.length && at < b.length &&
                       [a characterAtIndex:at] == [b characterAtIndex:at]) at++;
                if (at < a.length) {
                    NSString *extra = [a substringFromIndex:at];
                    if (extra.length > 60) extra = [extra substringToIndex:60];
                    NSMutableString *shown = [NSMutableString string];
                    for (NSUInteger k = 0; k < extra.length; k++) {
                        [shown appendFormat:@"%04x ", [extra characterAtIndex:k]];
                    }
                    fprintf(stderr, "  only in the first: %s\n", shown.UTF8String);
                }
                fprintf(stderr, "  differ at %lu of %lu/%lu: %04x vs %04x\n",
                        (unsigned long)at, (unsigned long)a.length, (unsigned long)b.length,
                        at < a.length ? [a characterAtIndex:at] : 0,
                        at < b.length ? [b characterAtIndex:at] : 0);
            }
            check([screens[i] isEqualToString:screens[0]],
                  [NSString stringWithFormat:
                   @"the screen is the same whether delivered whole or in %@-byte pieces",
                   sizes[i]].UTF8String);
        }

        fprintf(stderr, failures == 0 ? "\nREPLAY PROBE DONE — all ok\n"
                                      : "\nREPLAY PROBE DONE — %d failed\n", failures);
    }
    return failures == 0 ? 0 : 1;
}
