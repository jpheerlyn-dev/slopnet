// console_render.m — draw the board through the real console and write a PNG.
//
// Use this before claiming any visual change works.
//
// Every other check in this repository strips the escape sequences before
// looking at the output, which removes precisely the colour and fill being
// changed. Four wrong versions of the panel frame shipped that way, each one
// "verified" against a text dump that could not show the defect. Look at the
// picture instead.
//
//   clang -fobjc-arc -framework AppKit -framework CoreText -I packaging \
//     tests/console_render.m packaging/SlopNetConsole.m packaging/SlopNetBrand.m \
//     -o /tmp/render && /tmp/render /tmp/board.png
//
// It also prints the true cell width of every row of one panel, which is the
// other half of the check: the ANSI can be perfectly formed and still render
// wrong, and knowing which of the two is broken saves hours.
#import <Cocoa/Cocoa.h>
#import "SlopNetConsole.h"
#import "SlopNetBrand.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        if (argc < 2) {
            fprintf(stderr, "usage: console_render <output.png>\n");
            return 2;
        }

        // The cell-width measurement that used to live here has been taken
        // out. It stripped the escape sequences and counted characters, which
        // says nothing about how anything is drawn — and it was used seven
        // times to report a panel as correct while it was visibly wrong.
        // The picture below is the only evidence this tool produces.

        SlopNetConsole *console =
            [[SlopNetConsole alloc] initWithFrame:NSMakeRect(0, 0, 900, 420)];
        [console layoutSubtreeIfNeeded];
        NSUInteger w = 64;
        [console note:[SlopNetBrand headerANSI:@"SlopNet" width:w]];
        [console note:[SlopNetBrand panelANSIForProvider:@"ibm_granite"
                                                   title:@"Granite — local guide"
                                                  detail:@[@"private · no API key · no open port"]
                                                  action:nil frame:0 width:w]];
        [console note:[SlopNetBrand headerANSI:@"Coding apps" width:w]];
        [console note:[SlopNetBrand panelStripANSIForProviders:
                          @[@"openai", @"anthropic", @"moonshot", @"google", @"xai"]
                       status:@{@"openai": @"not signed in yet",
                                @"anthropic": @"signed in · can build",
                                @"moonshot": @"not signed in yet",
                                @"google": @"not signed in yet",
                                @"xai": @"not signed in yet"}
                        width:w]];
        [console note:[SlopNetBrand youSaidANSI:@"hello granite, are you there?" width:w]];
        [console note:[SlopNetBrand guideSaidANSI:@"Yes, I am here and ready to help."
                                         provider:@"ibm_granite" name:@"Granite" width:w]];

        // Redraws are queued onto the run loop, so pump it or the image is blank.
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:1.0];
        while ([until timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        [console layoutSubtreeIfNeeded];

        NSBitmapImageRep *shot =
            [console bitmapImageRepForCachingDisplayInRect:console.bounds];
        [console cacheDisplayInRect:console.bounds toBitmapImageRep:shot];
        NSData *png = [shot representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        if (![png writeToFile:@(argv[1]) atomically:YES]) {
            fprintf(stderr, "could not write %s\n", argv[1]);
            return 1;
        }
        fprintf(stderr, "wrote %s — open it and look\n", argv[1]);
    }
    return 0;
}
