// console_picture.m — replay a recording through the console and photograph it.
//
// The replay probe compares text, which cannot see anything about how the
// screen looks. The logo Antigravity prints is drawn from block characters
// that have to tile: the filled part of one cell must meet the filled part of
// the cell above with no join. Whether they do is a question about pixels, and
// the only way to answer it is to look.
//
// With PRINT_SCREEN set it also prints the rows the screen is showing, and its
// size. That is what makes a real terminal emulator usable as an oracle: size
// one to match, feed both the same recording, and any difference is a fault
// here. Comparing against the whole scrollback cannot do that, and two
// attempts to do it anyway produced confident nonsense before this existed.
//
//   python3 -m venv /tmp/refterm && /tmp/refterm/bin/pip install pyte==0.8.2
//   PRINT_SCREEN=1 /tmp/picture tests/agy_chat_recording.bin /tmp/shot.png
//
//   clang -fobjc-arc -framework AppKit -framework CoreText -I packaging \
//     tests/console_picture.m packaging/SlopNetConsole.m \
//     packaging/SlopNetBrand.m -o /tmp/picture && \
//     /tmp/picture tests/agy_chat_recording.bin /tmp/shot.png
//
// For an exact text-oracle comparison at a different terminal size, pass its
// columns and rows. An optional final byte count stops at a real recording
// boundary, and SCREEN_FILE writes only the visible rows for a direct diff.
// Pass "continue" after the resize geometry to resize at that byte boundary
// and then feed the rest of the same recording:
//
//   SCREEN_FILE=/tmp/slopnet-screen /tmp/picture recording.bin /tmp/shot.png 94 40 64344 40 40
//   SCREEN_FILE=/tmp/slopnet-screen /tmp/picture tests/agy_chat_recording.bin /tmp/shot.png 94 40 1014 40 40 continue
#import <Cocoa/Cocoa.h>
#import "SlopNetBrand.h"
#import "SlopNetConsole.h"

@interface Nobody : NSObject <SlopNetConsoleDelegate>
@end
@implementation Nobody
- (void)console:(SlopNetConsole *)c asksFor:(SlopNetPrompt)p question:(NSString *)q {
    (void)c; (void)p; (void)q;
}
@end

static BOOL sizeConsole(SlopNetConsole *console, NSUInteger wantedColumns,
                        NSUInteger wantedRows) {
    NSSize size = console.frame.size;
    for (NSUInteger tries = 0; console.columns != wantedColumns && tries < 2000; tries++) {
        size.width += console.columns < wantedColumns ? 1.0 : -1.0;
        if (size.width < 180 || size.width > 2000) break;
        [console setFrameSize:size];
        [console layoutSubtreeIfNeeded];
    }
    for (NSUInteger tries = 0; console.visibleRows != wantedRows && tries < 1600; tries++) {
        size.height += console.visibleRows < wantedRows ? 1.0 : -1.0;
        if (size.height < 140 || size.height > 1600) break;
        [console setFrameSize:size];
        [console layoutSubtreeIfNeeded];
    }
    if (console.columns == wantedColumns && console.visibleRows == wantedRows) return YES;
    fprintf(stderr, "could not size console to %lux%lu (got %lux%lu)\n",
            (unsigned long)wantedColumns, (unsigned long)wantedRows,
            (unsigned long)console.columns, (unsigned long)console.visibleRows);
    return NO;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc < 3) {
            fprintf(stderr, "usage: picture <recording.bin> <out.png> "
                            "[columns rows [bytes [resize-columns resize-rows [continue]]]]\n");
            return 2;
        }
        [NSApplication sharedApplication];
        NSData *recording = [NSData dataWithContentsOfFile:@(argv[1])];
        if (recording == nil) { fprintf(stderr, "cannot read %s\n", argv[1]); return 2; }

        SlopNetConsole *console =
            [[SlopNetConsole alloc] initWithFrame:NSMakeRect(0, 0, 900, 620)];
        [console layoutSubtreeIfNeeded];
        if (argc >= 5) {
            NSUInteger wantedColumns = (NSUInteger)strtoul(argv[3], NULL, 10);
            NSUInteger wantedRows = (NSUInteger)strtoul(argv[4], NULL, 10);
            if (!sizeConsole(console, wantedColumns, wantedRows)) return 2;
        }
        Nobody *nobody = [Nobody new];
        console.delegate = nobody;
        [console runExecutable:@"/bin/bash" arguments:@[@"-c", @"sleep 600"]];
        NSDate *ready = [NSDate dateWithTimeIntervalSinceNow:0.5];
        while ([ready timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        NSUInteger byteCount = recording.length;
        if (argc >= 6) {
            byteCount = MIN((NSUInteger)strtoul(argv[5], NULL, 10), recording.length);
        }
        [console consumeBytes:[recording subdataWithRange:NSMakeRange(0, byteCount)]];
        if (argc >= 8) {
            NSUInteger wantedColumns = (NSUInteger)strtoul(argv[6], NULL, 10);
            NSUInteger wantedRows = (NSUInteger)strtoul(argv[7], NULL, 10);
            if (!sizeConsole(console, wantedColumns, wantedRows)) return 2;
        }
        if (argc >= 9 && strcmp(argv[8], "continue") == 0 && byteCount < recording.length) {
            [console consumeBytes:[recording subdataWithRange:
                NSMakeRange(byteCount, recording.length - byteCount)]];
        }
        NSDate *quiet = [NSDate dateWithTimeIntervalSinceNow:1.0];
        while ([quiet timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        [console layoutSubtreeIfNeeded];
        [console displayIfNeeded];

        if (getenv("PRINT_SCREEN")) {
            fprintf(stderr, "COLUMNS %lu ROWS %lu\n",
                    (unsigned long)console.columns, (unsigned long)console.visibleRows);
            fprintf(stderr, "%s\n", console.screenTextForTesting.UTF8String);
            fprintf(stderr, "--- scrollback has %lu characters ---\n",
                    (unsigned long)console.textForTesting.length);
        }
        const char *screenFile = getenv("SCREEN_FILE");
        if (screenFile != NULL && screenFile[0] != '\0') {
            [console.screenTextForTesting writeToFile:@(screenFile) atomically:YES
                                             encoding:NSUTF8StringEncoding error:nil];
        }
        NSBitmapImageRep *shot =
            [console bitmapImageRepForCachingDisplayInRect:console.bounds];
        [console cacheDisplayInRect:console.bounds toBitmapImageRep:shot];
        NSData *png = [shot representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        [console stop];
        if (![png writeToFile:@(argv[2]) atomically:YES]) {
            fprintf(stderr, "could not write %s\n", argv[2]);
            return 1;
        }
        fprintf(stderr, "wrote %s\n", argv[2]);
    }
    return 0;
}
