// console_picture.m — replay a recording through the console and photograph it.
//
// The replay probe compares text, which cannot see anything about how the
// screen looks. The logo Antigravity prints is drawn from block characters
// that have to tile: the filled part of one cell must meet the filled part of
// the cell above with no join. Whether they do is a question about pixels, and
// the only way to answer it is to look.
//
//   clang -fobjc-arc -framework AppKit -framework CoreText -I packaging \
//     tests/console_picture.m packaging/SlopNetConsole.m \
//     packaging/SlopNetBrand.m -o /tmp/picture && \
//     /tmp/picture tests/agy_chat_recording.bin /tmp/shot.png
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

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc < 3) {
            fprintf(stderr, "usage: picture <recording.bin> <out.png>\n");
            return 2;
        }
        [NSApplication sharedApplication];
        NSData *recording = [NSData dataWithContentsOfFile:@(argv[1])];
        if (recording == nil) { fprintf(stderr, "cannot read %s\n", argv[1]); return 2; }

        SlopNetConsole *console =
            [[SlopNetConsole alloc] initWithFrame:NSMakeRect(0, 0, 900, 620)];
        [console layoutSubtreeIfNeeded];
        Nobody *nobody = [Nobody new];
        console.delegate = nobody;
        [console runExecutable:@"/bin/bash" arguments:@[@"-c", @"sleep 600"]];
        NSDate *ready = [NSDate dateWithTimeIntervalSinceNow:0.5];
        while ([ready timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        [console consumeBytes:recording];
        NSDate *quiet = [NSDate dateWithTimeIntervalSinceNow:1.0];
        while ([quiet timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        [console layoutSubtreeIfNeeded];
        [console displayIfNeeded];

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
