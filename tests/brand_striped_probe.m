// brand_striped_probe.m — the striped IBM face, and the conversation lines.
//
// The striped wordmark face was bundled in the colour font from the start and
// went unused: every heading drew in plain monospace. Two things have to hold
// for it to be safe to draw with.
//
// One, the glyphs must exist. A missing codepoint renders as a tofu box, which
// is worse than the word it replaced.
//
// Two, every striped glyph must carry the base monospace advance. Headings are
// padded to a width by counting characters, so a glyph even slightly wider
// would push the trailing rule off the end of every header in the app.
//
//   clang -fobjc-arc -framework AppKit -framework CoreText -I packaging \
//     tests/brand_striped_probe.m packaging/SlopNetBrand.m -o /tmp/striped \
//     && /tmp/striped
#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
#import "SlopNetBrand.h"

static int failures = 0;
static void check(BOOL ok, const char *what) {
    fprintf(stderr, "%s %s\n", ok ? "ok  " : "FAIL", what);
    if (!ok) failures++;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        // Without the bundled face, striped text must come back untouched.
        // This process has no app bundle, so that is the path under test here.
        check([[SlopNetBrand stripedText:@"SLOPNET"] isEqualToString:@"SLOPNET"],
              "no colour font means plain text, never tofu");

        // Now the font itself, loaded straight from the repository.
        NSURL *url = [NSURL fileURLWithPath:
            @"packaging/terminal-visuals/packaging-fonts/Menlo-StormCode-Color.ttf"];
        CFErrorRef error = NULL;
        CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url,
                                         kCTFontManagerScopeProcess, &error);
        if (error != NULL) CFRelease(error);
        CTFontRef font = CTFontCreateWithName(CFSTR("Menlo-RegularStormCodeColor"), 24, NULL);
        NSString *name = CFBridgingRelease(CTFontCopyPostScriptName(font));
        check([name containsString:@"Storm"], "the bundled face loads");

        UniChar base = 'M';
        CGGlyph baseGlyph;
        CGSize baseAdvance;
        CTFontGetGlyphsForCharacters(font, &base, &baseGlyph, 1);
        CTFontGetAdvancesForGlyphs(font, kCTFontOrientationHorizontal,
                                   &baseGlyph, &baseAdvance, 1);

        NSUInteger missing = 0, offGrid = 0;
        for (int i = 0; i < 62; i++) {              // A-Z, a-z, 0-9
            UniChar c = (UniChar)(0xE800 + i);
            CGGlyph glyph;
            CGSize advance;
            if (!CTFontGetGlyphsForCharacters(font, &c, &glyph, 1) || glyph == 0) {
                missing++;
                continue;
            }
            CTFontGetAdvancesForGlyphs(font, kCTFontOrientationHorizontal,
                                       &glyph, &advance, 1);
            if (fabs(advance.width - baseAdvance.width) > 0.01) offGrid++;
        }
        check(missing == 0, "all 62 striped letters and digits are in the font");
        check(offGrid == 0, "every striped glyph keeps the monospace advance");

        // The conversation lines: the person's words must not be dressed as
        // the guide's. This is what a Granite-branded panel around the typed
        // question used to do.
        NSString *mine = [SlopNetBrand youSaidANSI:@"hello?" width:60];
        check([mine containsString:@"You"], "the person's panel is labelled as theirs");
        check([mine containsString:@"hello?"], "and carries what they typed");
        check([[mine componentsSeparatedByString:@"█"] count] > 3,
              "the message sits in a banded panel, the way demo_agency draws a turn");
        check(![mine containsString:@"Granite"],
              "the guide's name is not printed above words it did not write");

        NSString *theirs = [SlopNetBrand guideRepliesANSIForProvider:@"ibm_granite"
                                                                name:@"Granite"];
        check([theirs containsString:@"Granite"], "the reply is attributed to the guide");


        // Granite is green on black, which the operator asked for twice. The
        // green was in the table from the start as a tint while the panel text
        // stayed white, so the guide read like every other vendor.
        NSString *reply = [SlopNetBrand guideSaidANSI:@"I am here."
                                             provider:@"ibm_granite"
                                                 name:@"Granite" width:60];
        check([reply containsString:@"38;2;0;171;35"],
              "the guide speaks in Granite green");
        check([reply containsString:@"48;2;0;0;0"],
              "on the black field, not a vendor fill");


        // The frame is a solid red band. A box-drawing hairline left a black
        // cell between the brand colour and the red, which is the gap the
        // operator kept pointing at; filling behind the hairline was worse,
        // because a coloured cell with a red thread through it puts the frame
        // inside the panel rather than around it.
        NSString *tile = [SlopNetBrand panelANSIForProvider:@"anthropic"
                                                      title:nil
                                                     detail:@[@"not signed in yet"]
                                                     action:nil frame:0 width:40];
        check([tile containsString:@"█"], "the frame is drawn with a full block");
        check(![tile containsString:@"┌"] && ![tile containsString:@"│"],
              "and no hairline is left to leave a gap beside the fill");
        // A full block paints its whole cell in the foreground, so the frame
        // must be crimson.
        check([tile containsString:@"38;2;255;0;60"], "in crimson");
        for (NSString *row in [tile componentsSeparatedByString:@"\n"]) {
            if (row.length == 0) continue;
            check([row containsString:@"█"], "every row of the panel is banded");
            break;
        }

        fprintf(stderr, failures == 0 ? "\nSTRIPED PROBE DONE — all ok\n"
                                      : "\nSTRIPED PROBE DONE — %d failed\n", failures);
    }
    return failures == 0 ? 0 : 1;
}
