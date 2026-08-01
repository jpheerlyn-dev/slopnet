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
static NSURL *replay(NSData *recording, NSUInteger chunk, NSInteger *offers) {
    SlopNetConsole *console =
        [[SlopNetConsole alloc] initWithFrame:NSMakeRect(0, 0, 900, 400)];
    [console layoutSubtreeIfNeeded];
    Catcher *catcher = [Catcher new];
    console.delegate = catcher;
    [console runExecutable:@"/bin/bash" arguments:@[@"-c", @"sleep 4"]];
    NSDate *ready = [NSDate dateWithTimeIntervalSinceNow:0.5];
    while ([ready timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    for (NSUInteger at = 0; at < recording.length; at += chunk) {
        NSUInteger take = MIN(chunk, recording.length - at);
        NSString *piece = [[NSString alloc]
            initWithData:[recording subdataWithRange:NSMakeRange(at, take)]
                encoding:NSUTF8StringEncoding];
        if (piece == nil) {
            piece = [[NSString alloc]
                initWithData:[recording subdataWithRange:NSMakeRange(at, take)]
                    encoding:NSISOLatin1StringEncoding];
        }
        [console consume:piece];
    }
    // Let the console notice that the program has stopped writing.
    NSDate *quiet = [NSDate dateWithTimeIntervalSinceNow:1.2];
    while ([quiet timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    if (offers) *offers = catcher.offers;
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
        NSString *expected = argc > 2 ? @(argv[2]) : nil;

        // Whole, and cut up the way a pseudo-terminal actually delivers it.
        NSArray<NSNumber *> *sizes = @[@(recording.length), @4096, @1024, @137];
        for (NSNumber *size in sizes) {
            NSInteger offers = 0;
            NSURL *page = replay(recording, size.unsignedIntegerValue, &offers);
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

        fprintf(stderr, failures == 0 ? "\nREPLAY PROBE DONE — all ok\n"
                                      : "\nREPLAY PROBE DONE — %d failed\n", failures);
    }
    return failures == 0 ? 0 : 1;
}
