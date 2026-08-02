#import "SlopNetConsole.h"
#import "SlopNetBrand.h"
#import <util.h>
#import <termios.h>
#import <sys/ioctl.h>
#import <signal.h>
#import <unistd.h>

/// The colours and weights currently in force — one terminal "pen". A run of
/// text is stored with the pen that drew it, which is what lets a brand-filled
/// panel keep its own background while the rest of the line stays on the field.
@interface SlopNetInk : NSObject <NSCopying>
@property(nonatomic, strong) NSColor *foreground;   // nil == the default ink
@property(nonatomic, strong) NSColor *background;   // nil == the console field
@property(nonatomic, assign) BOOL bold;
@property(nonatomic, assign) BOOL dim;
@property(nonatomic, assign) BOOL reverse;
- (void)reset;
@end

@implementation SlopNetInk
- (void)reset {
    _foreground = nil;
    _background = nil;
    _bold = NO;
    _dim = NO;
    _reverse = NO;
}
- (id)copyWithZone:(NSZone *)zone {
    SlopNetInk *copy = [[SlopNetInk allocWithZone:zone] init];
    copy.foreground = _foreground;
    copy.background = _background;
    copy.bold = _bold;
    copy.dim = _dim;
    copy.reverse = _reverse;
    return copy;
}
@end

/// The attribute the console stores a cell's fill under.
///
/// Deliberately not NSBackgroundColorAttributeName: AppKit paints that using
/// each run's own font metrics, so a badge drawn at a different size leaves a
/// tab or a notch against the text beside it, and no amount of scaling closes
/// it — shrink the badge and the gap flips from coloured to black.
///
/// Painting it here instead means a fill covers the whole line box, the same
/// height for every run on the row, which is what a terminal cell does.
/// Where a cell's fill is stored.
///
/// Not NSBackgroundColorAttributeName: AppKit paints that from each run's own
/// font metrics, so the moment a badge is drawn at any other size its fill
/// becomes a different height and leaves a seam. Painting it here lets the
/// badge be sized to fit while the row keeps one uniform fill.
static NSString *const kCellFill = @"SlopNetCellFill";

/// Keeps every glyph inside its own row.
///
/// The badges are sbix bitmaps, and an sbix font carries several strikes at
/// different resolutions. On a Retina screen a different, larger strike is
/// chosen than on a 1x drawing context — which is why every render made here
/// looked correct while the operator's screen showed the logo poking out of
/// the top of the panel. Sizing the badge cannot fix that reliably, because
/// the size that fits depends on the strike the system picks.
///
/// Clipping does. Each line fragment draws inside its own rectangle, so a
/// bitmap can never paint above or below the row it belongs to, whatever
/// strike is chosen and whatever the backing scale.
@interface SlopNetClippingLayout : NSLayoutManager
@end

@implementation SlopNetClippingLayout

/// The fraction of a cell a block character fills, and from which side.
///
/// These characters exist to be tiled: a picture drawn with them relies on the
/// filled part of one cell meeting the filled part of the cell above with no
/// join. Drawn as glyphs they cannot, because a glyph is sized to the font's
/// box — 15.715pt here — while rows are a whole 16pt apart, leaving a seam of
/// a quarter point under every row. At two pixels to the point that seam is
/// visible, and it is what cut the Antigravity logo into floating squares.
///
/// So they are drawn as rectangles measured from the row itself, which is what
/// terminals do. Returns NO for anything that should stay a glyph.
static BOOL blockFillForCharacter(unichar c, CGFloat *fromLeft, CGFloat *fromTop,
                                  CGFloat *width, CGFloat *height, CGFloat *alpha) {
    *fromLeft = 0; *fromTop = 0; *width = 1; *height = 1; *alpha = 1;
    if (c == 0x2580) { *height = 0.5; return YES; }                    // upper half
    if (c >= 0x2581 && c <= 0x2588) {                                  // lower eighths
        CGFloat part = (CGFloat)(c - 0x2580) / 8.0;
        *fromTop = 1.0 - part; *height = part; return YES;
    }
    if (c >= 0x2589 && c <= 0x258F) {                                  // left eighths
        *width = (CGFloat)(0x2590 - c) / 8.0; return YES;
    }
    if (c == 0x2590) { *fromLeft = 0.5; *width = 0.5; return YES; }    // right half
    if (c >= 0x2591 && c <= 0x2593) {                                  // shades
        *alpha = 0.25 * (CGFloat)(c - 0x2590); return YES;
    }
    if (c == 0x2594) { *height = 0.125; return YES; }                  // upper eighth
    if (c == 0x2595) { *fromLeft = 0.875; *width = 0.125; return YES; } // right eighth
    return NO;
}

- (void)drawGlyphsForGlyphRange:(NSRange)range atPoint:(NSPoint)origin {
    NSUInteger index = range.location;
    while (index < NSMaxRange(range)) {
        NSRange lineGlyphs;
        NSRect fragment = [self lineFragmentRectForGlyphAtIndex:index
                                                 effectiveRange:&lineGlyphs];
        NSRange piece = NSIntersectionRange(range, lineGlyphs);
        if (piece.length == 0) break;
        NSRect clip = NSOffsetRect(fragment, origin.x, origin.y);
        [NSGraphicsContext saveGraphicsState];
        NSRectClip(clip);
        [super drawGlyphsForGlyphRange:piece atPoint:origin];
        [self fillBlocksInGlyphRange:piece atPoint:origin fragment:fragment];
        [NSGraphicsContext restoreGraphicsState];
        index = NSMaxRange(lineGlyphs);
    }
}

/// Paint over any block characters in this row with exact rectangles. Drawn
/// after the glyphs and covering them, so a row of them meets the row above.
- (void)fillBlocksInGlyphRange:(NSRange)glyphs atPoint:(NSPoint)origin
                      fragment:(NSRect)fragment {
    NSTextStorage *store = self.textStorage;
    if (store.length == 0) return;
    NSString *text = store.string;
    for (NSUInteger g = glyphs.location; g < NSMaxRange(glyphs); g++) {
        NSUInteger at = [self characterIndexForGlyphAtIndex:g];
        if (at >= text.length) continue;
        unichar c = [text characterAtIndex:at];
        // The arrow a status bar draws between its sections. No monospace
        // font carries it unless it has been patched for the purpose, so it
        // came out as an empty box — a hundred and forty of them across
        // Zellij's bars, which is most of what made it look broken. It is a
        // triangle filling the cell, so it is drawn as one.
        if (c == 0xE0B0 || c == 0xE0B2) {
            NSFont *sepFont = [store attribute:NSFontAttributeName
                                       atIndex:at effectiveRange:NULL];
            CGFloat sepCell = sepFont ? sepFont.maximumAdvancement.width : 0;
            if (sepCell <= 0) continue;
            NSPoint sepSpot = [self locationForGlyphAtIndex:g];
            NSRect cellRect = NSMakeRect(origin.x + fragment.origin.x + sepSpot.x,
                                         origin.y + fragment.origin.y,
                                         sepCell, fragment.size.height);
            NSColor *behind = [store attribute:NSBackgroundColorAttributeName
                                       atIndex:at effectiveRange:NULL];
            if (behind != nil) {
                [behind set];
                NSRectFillUsingOperation(cellRect, NSCompositingOperationSourceOver);
            }
            NSColor *edge = [store attribute:NSForegroundColorAttributeName
                                     atIndex:at effectiveRange:NULL];
            if (edge == nil) continue;
            NSBezierPath *arrow = [NSBezierPath bezierPath];
            if (c == 0xE0B0) {
                [arrow moveToPoint:NSMakePoint(NSMinX(cellRect), NSMinY(cellRect))];
                [arrow lineToPoint:NSMakePoint(NSMaxX(cellRect), NSMidY(cellRect))];
                [arrow lineToPoint:NSMakePoint(NSMinX(cellRect), NSMaxY(cellRect))];
            } else {
                [arrow moveToPoint:NSMakePoint(NSMaxX(cellRect), NSMinY(cellRect))];
                [arrow lineToPoint:NSMakePoint(NSMinX(cellRect), NSMidY(cellRect))];
                [arrow lineToPoint:NSMakePoint(NSMaxX(cellRect), NSMaxY(cellRect))];
            }
            [arrow closePath];
            [edge set];
            [arrow fill];
            continue;
        }

        CGFloat fromLeft, fromTop, width, height, alpha;
        if (!blockFillForCharacter(c, &fromLeft, &fromTop, &width, &height, &alpha)) continue;

        NSFont *font = [store attribute:NSFontAttributeName atIndex:at effectiveRange:NULL];
        CGFloat cell = font ? font.maximumAdvancement.width : 0;
        if (cell <= 0) continue;
        NSPoint spot = [self locationForGlyphAtIndex:g];
        NSRect cellRect = NSMakeRect(origin.x + fragment.origin.x + spot.x,
                                     origin.y + fragment.origin.y,
                                     cell, fragment.size.height);
        NSRect fill = NSMakeRect(cellRect.origin.x + cellRect.size.width * fromLeft,
                                 cellRect.origin.y + cellRect.size.height * fromTop,
                                 cellRect.size.width * width,
                                 cellRect.size.height * height);
        NSColor *ink = [store attribute:NSForegroundColorAttributeName
                                atIndex:at effectiveRange:NULL];
        if (ink == nil) continue;
        [[ink colorWithAlphaComponent:ink.alphaComponent * alpha] set];
        NSRectFillUsingOperation(fill, NSCompositingOperationSourceOver);
    }
}

@end

@interface SlopNetTextView : NSTextView
@end

@implementation SlopNetTextView

- (void)drawViewBackgroundInRect:(NSRect)rect {
    [super drawViewBackgroundInRect:rect];
    NSLayoutManager *layout = self.layoutManager;
    NSTextContainer *container = self.textContainer;
    if (layout == nil || container == nil) return;

    NSRange visibleGlyphs = [layout glyphRangeForBoundingRect:rect inTextContainer:container];
    NSRange visible = [layout characterRangeForGlyphRange:visibleGlyphs actualGlyphRange:NULL];
    NSPoint origin = self.textContainerOrigin;
    NSUInteger total = layout.numberOfGlyphs;

    [self.textStorage enumerateAttribute:kCellFill inRange:visible options:0
                              usingBlock:^(id value, NSRange range, BOOL *stop) {
        (void)stop;
        NSColor *fill = value;
        if (fill == nil) return;
        NSRange glyphs = [layout glyphRangeForCharacterRange:range actualCharacterRange:NULL];
        NSUInteger index = glyphs.location;
        while (index < NSMaxRange(glyphs)) {
            NSRange lineGlyphs;
            NSRect fragment = [layout lineFragmentRectForGlyphAtIndex:index
                                                       effectiveRange:&lineGlyphs];
            NSRange piece = NSIntersectionRange(glyphs, lineGlyphs);
            if (piece.length == 0) break;

            // x from where the glyphs sit, never from their bounding boxes: a
            // bitmap badge's box extends past its cell and would drag the fill
            // out with it.
            CGFloat startX = [layout locationForGlyphAtIndex:piece.location].x;
            CGFloat endX;
            NSUInteger after = NSMaxRange(piece);
            if (after < NSMaxRange(lineGlyphs) && after < total) {
                endX = [layout locationForGlyphAtIndex:after].x;
            } else {
                endX = NSMaxX([layout lineFragmentUsedRectForGlyphAtIndex:piece.location
                                                           effectiveRange:NULL]);
            }
            NSRect cell = NSMakeRect(fragment.origin.x + origin.x + startX,
                                     fragment.origin.y + origin.y,
                                     endX - startX,
                                     fragment.size.height);
            [fill set];
            NSRectFill(cell);
            index = NSMaxRange(lineGlyphs);
        }
    }];
}

@end

@interface SlopNetConsole ()
@property(nonatomic, strong) NSTextView *output;
@property(nonatomic, strong) NSScrollView *scroller;
@property(nonatomic, strong) NSTextField *status;
@property(nonatomic, strong) NSButton *stopButton;
@property(nonatomic, assign) int master;          // our end of the PTY
@property(nonatomic, assign) pid_t child;
@property(nonatomic, strong) dispatch_source_t reader;
@property(nonatomic, strong) NSMutableArray<NSMutableAttributedString *> *lines;
@property(nonatomic, assign) NSUInteger row;      // cursor line
@property(nonatomic, assign) NSUInteger column;   // cursor column
@property(nonatomic, assign) BOOL needsRedraw;
@property(nonatomic, strong) SlopNetInk *ink;     // the live pen
@property(nonatomic, strong) NSFont *boldFont;
/// Lines already dropped off the top. Added to a row index this gives a token
/// that stays valid while the buffer scrolls, so an animation can redraw its
/// own line without counting on it staying put.
@property(nonatomic, assign) NSInteger droppedLines;
/// The last thing we told the delegate the program was waiting for.
@property(nonatomic, assign) SlopNetPrompt waitingFor;
/// The sign-in link already handed to the delegate, so one login does
/// not raise the same offer on every redraw.
@property(nonatomic, copy) NSString *announcedSignIn;
@property(nonatomic, copy) NSString *announcedCode;
@property(nonatomic, assign) BOOL signInLinkIsAuthorisation;
@property(nonatomic, strong) NSMutableString *collected;
/// How many lines each replaceable block currently occupies, by token. A block
/// that grows has to make room rather than refuse.
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *blockHeights;
/// One fixed line box for every row, so painted backgrounds tile vertically.
@property(nonatomic, strong) NSParagraphStyle *cellParagraph;
/// Whether the view should stay pinned to the newest output. Set false the
/// moment somebody scrolls up, true again when they come back to the bottom.
@property(nonatomic, assign) BOOL followTail;
/// A redraw is already queued, so a chatty program cannot queue a thousand.
@property(nonatomic, assign) BOOL redrawQueued;
/// A redraw is already scheduled for the next turn of the run loop.
@property(nonatomic, assign) BOOL redrawScheduled;
@property(nonatomic, assign) BOOL applicationCursorKeys;
/// What the program wrote, with the escape sequences taken out and nothing
/// moved. The drawn screen is the wrong place to read a link from: a program
/// redrawing a frame overwrites part of what is there, so rows end up holding
/// pieces of several frames at once. This does not.
@property(nonatomic, strong) NSMutableArray<NSString *> *streamLines;
@property(nonatomic, strong) NSMutableString *streamTail;
@property(nonatomic, assign) BOOL announcedAnAuthorisation;
/// Set once the program has stopped writing for a moment, at which point the
/// last row is finished with too.
@property(nonatomic, assign) BOOL outputSettled;
@property(nonatomic, assign) NSUInteger writeGeneration;
/// The start of an escape sequence that arrived without its end.
@property(nonatomic, copy) NSString *pendingEscape;
@property(nonatomic, strong) NSMutableData *readCarry;
@property(nonatomic, assign) BOOL flushingHeldBack;
/// A full-screen program asks for its own screen and gets a blank one, then
/// hands back what was underneath when it leaves.
@property(nonatomic, assign) BOOL onAlternateScreen;
@property(nonatomic, strong) NSMutableArray<NSMutableAttributedString *> *screenUnderneath;
@property(nonatomic, assign) NSUInteger rowUnderneath;
@property(nonatomic, assign) NSUInteger columnUnderneath;
/// Where the screen begins in the buffer, kept rather than guessed.
///
/// A program drawing a whole interface counts rows from the top of the screen,
/// so the console has to know where that is. It used to be worked out from how
/// many lines had accumulated, which is only right when nothing has scrolled
/// and is wrong the rest of the time — every absolute move landed somewhere
/// near enough to look plausible and wrong enough to shred the frame.
@property(nonatomic, assign) NSUInteger screenOrigin;
/// The rows a program has asked to confine scrolling to, counted from the top
/// of the screen. Full-screen programs keep a header or a status bar still by
/// scrolling only the region between them.
@property(nonatomic, assign) NSUInteger scrollFirst;
@property(nonatomic, assign) NSUInteger scrollLast;
@property(nonatomic, assign) BOOL scrollRegionSet;
@property(nonatomic, assign) NSUInteger savedRow;
@property(nonatomic, assign) NSUInteger savedColumn;
@property(nonatomic, assign) BOOL hasSavedCursor;
/// The cell geometry the screen model currently represents. The view's
/// measured geometry changes before resizeSubviewsWithOldSize: runs, so keep
/// the previous values explicitly for clipping the old screen into the new.
@property(nonatomic, assign) NSUInteger modeledColumns;
@property(nonatomic, assign) NSUInteger modeledRows;
/// Follow the newest line, the way a terminal does — until somebody scrolls
/// up to read something, and again once they come back to the bottom.
@property(nonatomic, assign) BOOL followingTail;
@end

/// Keep the console light even during a long build.
static const NSUInteger kMaxLines = 4000;

/// Row height, as a multiple of the font's own line height.
///
/// This must stay at 1. Raising it does NOT give a badge more room: AppKit
/// paints a run's background at the font's metric height, not at the line
/// box's, so a taller row just opens a black band between the rows and splits
/// the panel fill into stripes. Rendered at 1.2 and 1.4 to confirm before
/// writing this down, so nobody tries it again.
static const CGFloat kRowHeightForBadges = 1.00;

/// 12.53 / 17.0 — the text ascent over the badge ink's reach above the
/// baseline, both measured at 13.5pt. Anything larger pokes out the top.
static const CGFloat kBadgeInkFit = 0.73;

/// How far to drop a badge so its bitmap sits inside the line box
/// rather than above it. Found by rendering, not by arithmetic.

#pragma mark - ANSI colour

/// The xterm 256-colour palette: 16 named colours, a 6x6x6 cube, then greys.
static NSColor *SlopNetAnsiColor(NSInteger index) {
    static const uint8_t basic[16][3] = {
        {0x00, 0x00, 0x00}, {0xcd, 0x00, 0x00}, {0x00, 0xcd, 0x00}, {0xcd, 0xcd, 0x00},
        {0x00, 0x00, 0xee}, {0xcd, 0x00, 0xcd}, {0x00, 0xcd, 0xcd}, {0xe5, 0xe5, 0xe5},
        {0x7f, 0x7f, 0x7f}, {0xff, 0x00, 0x00}, {0x00, 0xff, 0x00}, {0xff, 0xff, 0x00},
        {0x5c, 0x5c, 0xff}, {0xff, 0x00, 0xff}, {0x00, 0xff, 0xff}, {0xff, 0xff, 0xff},
    };
    static const uint8_t level[6] = {0, 95, 135, 175, 215, 255};
    if (index < 0 || index > 255) return nil;
    if (index < 16) {
        return [NSColor colorWithSRGBRed:basic[index][0] / 255.0
                                   green:basic[index][1] / 255.0
                                    blue:basic[index][2] / 255.0 alpha:1.0];
    }
    if (index < 232) {
        NSInteger n = index - 16;
        return [NSColor colorWithSRGBRed:level[(n / 36) % 6] / 255.0
                                   green:level[(n / 6) % 6] / 255.0
                                    blue:level[n % 6] / 255.0 alpha:1.0];
    }
    CGFloat grey = (8 + (index - 232) * 10) / 255.0;
    return [NSColor colorWithSRGBRed:grey green:grey blue:grey alpha:1.0];
}

static NSColor *SlopNetTrueColor(NSInteger r, NSInteger g, NSInteger b) {
    return [NSColor colorWithSRGBRed:MAX(0, MIN(255, r)) / 255.0
                               green:MAX(0, MIN(255, g)) / 255.0
                                blue:MAX(0, MIN(255, b)) / 255.0 alpha:1.0];
}

/// Apply one SGR sequence's parameters to a pen. Everything StormCode output
/// actually emits is here: reset, bold, dim, reverse, the 8+8 named colours,
/// 256-colour (38;5;N) and 24-bit truecolor (38;2;r;g;b), for text and field.
static void SlopNetApplySGR(SlopNetInk *ink, NSString *parameters) {
    NSArray<NSString *> *parts = parameters.length
        ? [parameters componentsSeparatedByString:@";"] : @[@"0"];
    for (NSUInteger i = 0; i < parts.count; i++) {
        // A colon-separated sub-parameter list (ITU T.416 style) carries the
        // same numbers; take the leading one so 38:2:… behaves like 38;2;….
        NSInteger code = [[[parts[i] componentsSeparatedByString:@":"] firstObject] integerValue];
        switch (code) {
            case 0:  [ink reset]; break;
            case 1:  ink.bold = YES; break;
            case 2:  ink.dim = YES; break;
            case 7:  ink.reverse = YES; break;
            case 22: ink.bold = NO; ink.dim = NO; break;
            case 27: ink.reverse = NO; break;
            case 39: ink.foreground = nil; break;
            case 49: ink.background = nil; break;
            case 38:
            case 48: {
                NSColor *picked = nil;
                NSUInteger consumed = 0;
                if (i + 1 < parts.count) {
                    NSInteger mode = [parts[i + 1] integerValue];
                    if (mode == 5 && i + 2 < parts.count) {
                        picked = SlopNetAnsiColor([parts[i + 2] integerValue]);
                        consumed = 2;
                    } else if (mode == 2 && i + 4 < parts.count) {
                        picked = SlopNetTrueColor([parts[i + 2] integerValue],
                                                  [parts[i + 3] integerValue],
                                                  [parts[i + 4] integerValue]);
                        consumed = 4;
                    }
                }
                if (picked != nil) {
                    if (code == 38) ink.foreground = picked; else ink.background = picked;
                }
                i += consumed;
                break;
            }
            default:
                if (code >= 30 && code <= 37)        ink.foreground = SlopNetAnsiColor(code - 30);
                else if (code >= 90 && code <= 97)   ink.foreground = SlopNetAnsiColor(code - 90 + 8);
                else if (code >= 40 && code <= 47)   ink.background = SlopNetAnsiColor(code - 40);
                else if (code >= 100 && code <= 107) ink.background = SlopNetAnsiColor(code - 100 + 8);
                break;                               // italics, underline: not drawn
        }
    }
}

@implementation SlopNetConsole {
    struct termios _savedLineDiscipline;
    BOOL _haveSavedLineDiscipline;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _master = -1;
    _child = -1;
    _lines = [NSMutableArray arrayWithObject:[[NSMutableAttributedString alloc] init]];
    _row = 0;
    _column = 0;
    _ink = [[SlopNetInk alloc] init];
    _droppedLines = 0;
    _followTail = YES;
    _followingTail = YES;

    NSTextStorage *storage = [[NSTextStorage alloc] init];
    SlopNetClippingLayout *clipping = [[SlopNetClippingLayout alloc] init];
    NSTextContainer *box = [[NSTextContainer alloc]
        initWithContainerSize:NSMakeSize(FLT_MAX, FLT_MAX)];
    box.widthTracksTextView = YES;
    [clipping addTextContainer:box];
    [storage addLayoutManager:clipping];
    _output = [[SlopNetTextView alloc] initWithFrame:NSZeroRect textContainer:box];
    _output.editable = NO;
    _output.selectable = YES;
    // Rich text is what carries per-run colour. Without it every attribute
    // collapses to one font and one colour, which is what flattened the
    // StormCode panels in the first pass.
    _output.richText = YES;
    _output.drawsBackground = YES;
    // The jet-black field the whole StormCode palette is designed against.
    _output.backgroundColor = [SlopNetBrand voidColor];
    // The bundled colour face renders provider badges as real full-colour
    // logos; if it fails to register this is the system monospaced font and
    // callers print plain Unicode marks instead (see SlopNetBrand).
    _output.font = [SlopNetBrand consoleFontOfSize:13.5];
    _boldFont = [[NSFontManager sharedFontManager] convertFont:_output.font
                                                   toHaveTrait:NSBoldFontMask];
    _output.textColor = [SlopNetBrand inkColor];
    _output.automaticQuoteSubstitutionEnabled = NO;
    _output.textContainerInset = NSMakeSize(8, 8);

    _scroller = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _scroller.hasVerticalScroller = YES;
    _scroller.autohidesScrollers = NO;
    _scroller.borderType = NSNoBorder;
    _scroller.drawsBackground = YES;
    _scroller.backgroundColor = [SlopNetBrand voidColor];
    _scroller.documentView = _output;
    _scroller.translatesAutoresizingMaskIntoConstraints = NO;
    // Notice when somebody scrolls, so output arriving does not drag them back.
    _scroller.contentView.postsBoundsChangedNotifications = YES;
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(scrolled:)
                                               name:NSViewBoundsDidChangeNotification
                                             object:_scroller.contentView];
    _output.minSize = NSMakeSize(0, 0);
    _output.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    _output.verticallyResizable = YES;
    _output.horizontallyResizable = NO;
    _output.autoresizingMask = NSViewWidthSizable;
    _output.textContainer.widthTracksTextView = YES;
    [self addSubview:_scroller];

    // A crimson hairline around the field: the same frame the StormCode
    // panels draw, so the console reads as one bordered surface.
    _scroller.wantsLayer = YES;
    _scroller.layer.borderWidth = 1.0;
    _scroller.layer.borderColor = [SlopNetBrand crimsonColor].CGColor;

    _status = [NSTextField labelWithString:@"Nothing running."];
    _status.font = [NSFont systemFontOfSize:11];
    _status.textColor = [NSColor secondaryLabelColor];
    _status.translatesAutoresizingMaskIntoConstraints = NO;
    _status.hidden = YES;   // the window carries this now
    [self addSubview:_status];

    _stopButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    _stopButton.title = @"Stop";
    _stopButton.bezelStyle = NSBezelStyleRounded;
    _stopButton.target = self;
    _stopButton.action = @selector(stopPressed:);
    _stopButton.enabled = NO;
    _stopButton.translatesAutoresizingMaskIntoConstraints = NO;
    // Folded into the send button, the way a chat app does it.
    _stopButton.hidden = YES;
    [self addSubview:_stopButton];

    [NSLayoutConstraint activateConstraints:@[
        [_scroller.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_scroller.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scroller.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_status.topAnchor constraintEqualToAnchor:_scroller.bottomAnchor constant:0],
        [_status.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:2],
        [_status.heightAnchor constraintEqualToConstant:0],
        [_status.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_status.trailingAnchor constraintLessThanOrEqualToAnchor:_stopButton.leadingAnchor constant:-8],
        [_stopButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:_status.trailingAnchor constant:8],
        [_stopButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_stopButton.centerYAnchor constraintEqualToAnchor:_status.centerYAnchor],
        [_stopButton.widthAnchor constraintEqualToConstant:80],
    ]];
    return self;
}

- (BOOL)running { return self.child > 0; }

#pragma mark - measuring the field

- (CGFloat)characterWidth {
    NSFont *font = self.output.font ?: [NSFont monospacedSystemFontOfSize:11.5
                                                                   weight:NSFontWeightRegular];
    CGFloat advance = [@" " sizeWithAttributes:@{NSFontAttributeName: font}].width;
    return advance > 0.5 ? advance : 7.0;
}

- (NSUInteger)columns {
    CGFloat usable = self.scroller.contentSize.width - self.output.textContainerInset.width * 2 - 4;
    if (usable < 40) usable = 40;
    NSUInteger columns = (NSUInteger)floor(usable / [self characterWidth]);
    // Keep panels inside sane bounds however the window is dragged.
    return MAX((NSUInteger)40, MIN(columns, (NSUInteger)220));
}

- (NSUInteger)visibleRows {
    NSFont *font = self.output.font;
    CGFloat lineHeight = [@"M" sizeWithAttributes:@{NSFontAttributeName: font}].height;
    if (lineHeight < 4) lineHeight = 14;
    NSUInteger rows = (NSUInteger)floor(self.scroller.contentSize.height / lineHeight);
    return MAX((NSUInteger)10, MIN(rows, (NSUInteger)200));
}

/// Tell a running program the window changed size, the way a terminal does.
/// Without this a program keeps wrapping to the size it was told at startup.
- (void)resizeChildTerminal {
    if (self.master < 0) return;
    struct winsize size = {0};
    size.ws_col = (unsigned short)self.columns;
    size.ws_row = (unsigned short)self.visibleRows;
    if (ioctl(self.master, TIOCSWINSZ, &size) == 0 && self.child > 0) {
        kill(self.child, SIGWINCH);
    }
}

/// Resize a running program's visible screen to the view's new cell geometry.
///
/// This deliberately stays on the current attributed-row model. Shrinking a
/// width clips the right edge, and shrinking a height drops rows from the top,
/// exactly as the pyte oracle does. Only the addressed screen is changed;
/// earlier scrollback and idle app-authored notes remain readable. A later
/// fixed-cell screen can replace this without changing that boundary.
- (void)resizeTerminalScreenFromColumns:(NSUInteger)oldColumns
                                   rows:(NSUInteger)oldRows
                              toColumns:(NSUInteger)newColumns
                                   rows:(NSUInteger)newRows {
    // App-authored notes are a document, not terminal cells, and resizing the
    // idle window must not truncate them. A running program owns a terminal
    // screen whether or not it selected the alternate buffer (`top` does not).
    if ((!self.running && !self.onAlternateScreen) || oldColumns == 0 || oldRows == 0 ||
        newColumns == 0 || newRows == 0) return;

    NSUInteger oldTop = self.screenOrigin;
    if (newColumns < oldColumns) {
        NSUInteger oldBottom = oldTop + oldRows;
        NSUInteger availableBottom = MIN(oldBottom, self.lines.count);
        for (NSUInteger r = oldTop; r < availableBottom; r++) {
            NSMutableAttributedString *line = self.lines[r];
            if (line.length > newColumns) {
                [line deleteCharactersInRange:NSMakeRange(newColumns,
                                                           line.length - newColumns)];
            }
        }
    }

    // Terminal height shrink keeps the bottom rows. Advancing the origin
    // leaves the clipped rows in the document as implementation history, but
    // removes them from the addressed screen and from screenTextForTesting.
    if (newRows < oldRows) self.screenOrigin += oldRows - newRows;

    NSUInteger top = self.screenOrigin;
    NSUInteger bottom = top + newRows - 1;
    self.row = MIN(MAX(self.row, top), bottom);
    self.column = MIN(self.column, newColumns - 1);
    if (self.hasSavedCursor) {
        self.savedRow = MIN(MAX(self.savedRow, top), bottom);
        self.savedColumn = MIN(self.savedColumn, newColumns - 1);
    }

    // Margins are screen geometry, so a resize resets them to the whole new
    // screen. Keeping a row number from the old height can make the next line
    // feed scroll a region that no longer exists.
    self.scrollRegionSet = NO;
    [self setNeedsRedrawSoon];
}

- (void)synchronizeTerminalGeometry {
    NSUInteger columns = self.columns;
    NSUInteger rows = self.visibleRows;
    BOOL changed = self.modeledColumns > 0 && self.modeledRows > 0 &&
        (columns != self.modeledColumns || rows != self.modeledRows);
    if (changed) {
        [self resizeTerminalScreenFromColumns:self.modeledColumns
                                         rows:self.modeledRows
                                    toColumns:columns
                                         rows:rows];
    }
    self.modeledColumns = columns;
    self.modeledRows = rows;
    if (changed) [self resizeChildTerminal];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self synchronizeTerminalGeometry];
}

// Auto Layout updates the scroll view's content size after the outer view's
// resize callback. Measuring there can still see the old cell count, so check
// once more after constraints have settled.
- (void)layout {
    [super layout];
    [self synchronizeTerminalGeometry];
}

#pragma mark - showing text

- (NSDictionary *)attributesForInk:(SlopNetInk *)ink {
    NSColor *foreground = ink.foreground ?: [SlopNetBrand inkColor];
    NSColor *background = ink.background;
    if (ink.reverse) {
        NSColor *field = background ?: [SlopNetBrand voidColor];
        background = foreground;
        foreground = field;
    }
    if (ink.dim) {
        foreground = [foreground blendedColorWithFraction:0.45
                                                  ofColor:background ?: [SlopNetBrand voidColor]]
            ?: foreground;
    }
    NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithCapacity:3];
    attributes[NSFontAttributeName] = (ink.bold && self.boldFont) ? self.boldFont : self.output.font;
    attributes[NSForegroundColorAttributeName] = foreground;
    attributes[NSParagraphStyleAttributeName] = [self cellParagraph];
    if (background != nil) attributes[kCellFill] = background;
    return attributes;
}

/// A terminal cell is a rectangle that tiles. A text view's line box is not:
/// it carries leading, so consecutive rows leave an unpainted sliver between
/// their backgrounds — which draws a seam straight through a panel — and a
/// bitmap badge taller than the box spills out of the top of its fill.
///
/// Pinning the line height to exactly the font's own line height, with no
/// spacing, makes the rows tile the way cells do.
- (NSParagraphStyle *)cellParagraph {
    if (_cellParagraph == nil) {
        NSFont *font = self.output.font ?: [NSFont userFixedPitchFontOfSize:13.5];
        // Tall enough for the badge bitmap, not just the letters.
        //
        // Every font on the row must stay the same size, because AppKit paints
        // a run's background from that run's metrics and any difference leaves
        // a seam. So the badge cannot be shrunk to fit the row — the row has to
        // be big enough for the badge. One size, one background height, and no
        // glyph drawing outside its own line.
        CGFloat height = ceil([self.output.layoutManager defaultLineHeightForFont:font]
                              * kRowHeightForBadges);
        NSMutableParagraphStyle *style =
            [[NSMutableParagraphStyle alloc] init];
        style.minimumLineHeight = height;
        style.maximumLineHeight = height;
        style.lineSpacing = 0;
        style.paragraphSpacing = 0;
        style.paragraphSpacingBefore = 0;
        style.lineHeightMultiple = 1;
        style.lineBreakMode = NSLineBreakByClipping;
        _cellParagraph = [style copy];
    }
    return _cellParagraph;
}

- (NSDictionary *)fieldAttributes {
    return @{ NSFontAttributeName: self.output.font,
              NSForegroundColorAttributeName: [SlopNetBrand inkColor],
              NSParagraphStyleAttributeName: [self cellParagraph] };
}

/// Push the line buffer into the view. Called after each chunk, not per
/// character, so a chatty program cannot make the window crawl.
/// Ask for a redraw. Cheap to call as often as output arrives.
///
/// It used to redraw inline, once per chunk read from the program. Rebuilding
/// the whole buffer thousands of times in a row is what made the window stop
/// responding while the local guide was installing — and an unresponsive
/// window is exactly what "scrolling is broken" looks like from the outside.
/// Now the work happens once per turn of the run loop no matter how much
/// arrives, which leaves the main thread free to handle the scroll wheel.
- (void)setNeedsRedrawSoon {
    self.needsRedraw = YES;
    if (self.redrawScheduled) return;
    self.redrawScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) return;
        strongSelf.redrawScheduled = NO;
        [strongSelf redraw];
    });
}

/// Somebody moved the view. Follow the newest line only while they are on it,
/// which is what makes reading back through a build survive the next line
/// being printed.
- (void)scrolled:(NSNotification *)note {
    self.followingTail = [self atTail];
}

/// Is the view sitting at the newest line?
- (BOOL)atTail {
    NSClipView *clip = self.scroller.contentView;
    CGFloat documentHeight = ((NSView *)self.scroller.documentView).frame.size.height;
    CGFloat visibleBottom = NSMaxY(clip.bounds);
    // A couple of points of slack: the tail is never pixel-exact after a
    // relayout, and being one point short must not count as scrolled away.
    return visibleBottom >= documentHeight - 4.0;
}

- (void)redraw {
    if (!self.needsRedraw) return;
    self.needsRedraw = NO;
    // Decided before the text changes, because replacing the storage moves
    // the document out from under the scroll position.
    BOOL follow = self.followingTail || [self atTail];
    NSPoint parked = self.scroller.contentView.bounds.origin;
    NSMutableAttributedString *joined = [[NSMutableAttributedString alloc] init];
    NSAttributedString *newline =
        [[NSAttributedString alloc] initWithString:@"\n" attributes:[self fieldAttributes]];
    [joined beginEditing];
    for (NSUInteger index = 0; index < self.lines.count; index++) {
        if (index > 0) [joined appendAttributedString:newline];
        [joined appendAttributedString:self.lines[index]];
    }
    [joined endEditing];
    [self.output.textStorage setAttributedString:joined];
    self.followingTail = follow;
    if (follow) {
        [self.output scrollRangeToVisible:NSMakeRange(self.output.textStorage.length, 0)];
    } else {
        // Someone is reading. Put them back exactly where they were, rather
        // than dragging them to the bottom on every line the program prints.
        [self.output.layoutManager ensureLayoutForTextContainer:self.output.textContainer];
        [self.scroller.contentView scrollToPoint:parked];
        [self.scroller reflectScrolledClipView:self.scroller.contentView];
    }
}

/// Where the visible screen starts inside the scrollback.
///
/// Rows in an absolute move are counted from the top of the screen, not the
/// top of everything the person has scrolled past. Without this, a program
/// asking for row 1 would land on the first line of the session.
- (NSUInteger)screenTop { return self.screenOrigin; }

/// How many rows the screen has.
- (NSUInteger)screenRows {
    return self.visibleRows > 0 ? self.visibleRows : 24;
}

/// Keep a cursor-changing control sequence inside the addressed screen.
///
/// Text output may briefly leave `column == columns` to represent pending
/// wrap. A cursor command cancels that state and lands on a real cell. Rows
/// are absolute indexes into `lines`, so their lower bound is screenOrigin,
/// not zero once scrollback exists or a height shrink has clipped the top.
- (void)clampCursorToScreen {
    NSUInteger top = [self screenTop];
    NSUInteger rows = MAX((NSUInteger)1, [self screenRows]);
    NSUInteger bottom = top + rows - 1;
    NSUInteger right = MAX((NSUInteger)1, self.columns) - 1;
    self.row = MIN(MAX(self.row, top), bottom);
    self.column = MIN(self.column, right);
}

/// The last row scrolling may touch, counted from the top of the screen.
- (NSUInteger)lastScrollingRow {
    NSUInteger rows = [self screenRows];
    if (self.scrollRegionSet && self.scrollLast < rows) return self.scrollLast;
    return rows - 1;
}

/// Move the contents of the scrolling region up by one, losing the top row of
/// the region and opening a blank one at the bottom.
///
/// When the region is the whole screen this is ordinary scrolling and the top
/// row simply becomes scrollback, which is why it is kept rather than deleted.
- (void)scrollRegionUp {
    NSUInteger first = self.screenOrigin + (self.scrollRegionSet ? self.scrollFirst : 0);
    NSUInteger last = self.screenOrigin + [self lastScrollingRow];
    if (!self.scrollRegionSet || (self.scrollFirst == 0 && last + 1 >= self.screenOrigin + [self screenRows])) {
        self.screenOrigin++;                       // the row above becomes history
        while (self.lines.count <= last + 1) {
            [self.lines addObject:[[NSMutableAttributedString alloc] init]];
        }
        return;
    }
    while (self.lines.count <= last) {
        [self.lines addObject:[[NSMutableAttributedString alloc] init]];
    }
    [self.lines removeObjectAtIndex:first];
    [self.lines insertObject:[[NSMutableAttributedString alloc] init] atIndex:last];
}

- (NSMutableAttributedString *)currentLine {
    while (self.lines.count <= self.row) {
        [self.lines addObject:[[NSMutableAttributedString alloc] init]];
    }
    return self.lines[self.row];
}

/// Write text at the cursor, overwriting what is already there — this is
/// what makes a progress line update in place instead of repeating. The
/// replaced span takes the current pen; untouched spans keep theirs.
/// Draw a badge small enough that its bitmap stays inside the row.
///
/// Measured rather than guessed: at 13.5pt the badge's ink reaches 17.0pt
/// above the baseline while the text ascent is 12.53pt, so it overflows by
/// 4.47pt and pokes out of the top of the fill. CoreText reports zero bounds
/// for these glyphs — the numbers came from drawing one and finding the ink.
///
/// The advance lost by shrinking is added back as kerning, so no column moves,
/// and the row's fill is painted separately so the size change cannot alter it.
- (void)settleBadgesIn:(NSMutableAttributedString *)piece {
    NSFont *font = self.output.font;
    if (font == nil) return;
    NSFont *smaller = [NSFont fontWithName:font.fontName
                                      size:font.pointSize * kBadgeInkFit];
    if (smaller == nil) return;
    NSString *text = piece.string;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        BOOL badge = (c >= 0xE000 && c <= 0xE7FF) || (c >= 0xE900 && c <= 0xEC45);
        if (!badge) continue;
        NSRange one = NSMakeRange(i, 1);
        NSString *single = [text substringWithRange:one];
        CGFloat wanted = [single sizeWithAttributes:@{NSFontAttributeName: font}].width;
        CGFloat drawn  = [single sizeWithAttributes:@{NSFontAttributeName: smaller}].width;
        [piece addAttribute:NSFontAttributeName value:smaller range:one];
        if (wanted > drawn) [piece addAttribute:NSKernAttributeName value:@(wanted - drawn) range:one];
    }
}

/// Write text at the cursor, wrapping at the width the program was told.
///
/// A terminal moves to the next row when a line reaches its right edge, and
/// programs count on it: they print a long line, then move the cursor back up
/// by however many rows they expect it to have taken. This console kept
/// appending to the one row instead, so the program's arithmetic and the
/// console's disagreed from that point on and redrawn frames landed on top of
/// each other. That is what shredded Antigravity's sign-in box and left an
/// authorisation URL cut off at the end of its first row.
///
/// The move happens on the character *after* the edge is reached, not on
/// reaching it, so a panel exactly the width of the window does not gain a
/// blank row beneath every line.
- (void)putText:(NSString *)text {
    if (text.length == 0) return;
    NSUInteger width = self.columns;
    if (width == 0) { [self putRun:text]; return; }
    NSUInteger at = 0;
    while (at < text.length) {
        if (self.column >= width) [self newline];
        NSUInteger room = width - self.column;
        NSUInteger take = MIN(room, text.length - at);
        [self putRun:[text substringWithRange:NSMakeRange(at, take)]];
        at += take;
    }
}

- (void)putRun:(NSString *)text {
    if (text.length == 0) return;
    NSMutableAttributedString *line = [self currentLine];
    if (line.length < self.column) {
        NSString *gap = [@"" stringByPaddingToLength:(self.column - line.length)
                                          withString:@" " startingAtIndex:0];
        [line appendAttributedString:
            [[NSAttributedString alloc] initWithString:gap attributes:[self fieldAttributes]]];
    }
    NSMutableAttributedString *piece =
        [[NSMutableAttributedString alloc] initWithString:text
                                              attributes:[self attributesForInk:self.ink]];
    [self settleBadgesIn:piece];
    NSUInteger end = self.column + text.length;
    if (end <= line.length) {
        [line replaceCharactersInRange:NSMakeRange(self.column, text.length)
                  withAttributedString:piece];
    } else {
        [line deleteCharactersInRange:NSMakeRange(self.column, line.length - self.column)];
        [line appendAttributedString:piece];
    }
    self.column = end;
}

/// The other direction: open a blank row at the top of the region and lose the
/// bottom one. This is what a program does when something arrives above what
/// is already showing.
- (void)scrollRegionDown {
    NSUInteger first = self.screenOrigin + (self.scrollRegionSet ? self.scrollFirst : 0);
    NSUInteger last = self.screenOrigin + [self lastScrollingRow];
    while (self.lines.count <= last) {
        [self.lines addObject:[[NSMutableAttributedString alloc] init]];
    }
    [self.lines removeObjectAtIndex:last];
    [self.lines insertObject:[[NSMutableAttributedString alloc] init] atIndex:first];
}

/// Down one row, staying in the same column, which is what a line feed does.
///
/// Only a carriage return moves to the left edge. While a program is in the
/// ordinary mode the terminal turns its newlines into both, so the difference
/// never showed; a program driving its own screen turns that off and sends
/// bare line feeds, and then it decides everything. Antigravity draws its
/// header by ending a row and stepping back left from where that row finished
/// — with the column reset to zero first, the step back clamps there and the
/// row starts at the edge. Two rows of the logo lost their indentation that
/// way, which is what stopped it forming a pyramid.
- (void)lineFeed {
    NSUInteger keep = self.column;
    [self newline];
    self.column = keep;
    NSMutableAttributedString *line = [self currentLine];
    if (line.length < self.column) {
        NSString *gap = [@"" stringByPaddingToLength:(self.column - line.length)
                                          withString:@" " startingAtIndex:0];
        [line appendAttributedString:
            [[NSAttributedString alloc] initWithString:gap
                                            attributes:[self fieldAttributes]]];
    }
}

- (void)newline {
    NSUInteger last = self.screenOrigin + [self lastScrollingRow];
    if (self.row >= last) {
        [self scrollRegionUp];
        self.row = self.screenOrigin + [self lastScrollingRow];
    } else {
        self.row++;
    }
    self.column = 0;
    [self currentLine];
    if (self.lines.count > kMaxLines) {
        NSUInteger drop = self.lines.count - kMaxLines;
        [self.lines removeObjectsInRange:NSMakeRange(0, drop)];
        self.row = self.row > drop ? self.row - drop : 0;
        self.screenOrigin = self.screenOrigin > drop ? self.screenOrigin - drop : 0;
        self.droppedLines += (NSInteger)drop;
    }
}

/// A deliberately small terminal: enough to render progress lines, menus,
/// prompts and colour correctly. It is not a full terminal emulator — a
/// full-screen program (a file manager, an editor) needs more than this.
- (void)consume:(NSString *)raw {
    // Held back rather than drawn. Deliberately before any parsing: a reply is
    // plain text, and the window must not show half a panel while it arrives.
    if (self.collectsOutput) {
        if (self.collected == nil) self.collected = [NSMutableString string];
        [self.collected appendString:raw];
        return;
    }

    // Put back the start of any escape sequence the last read cut in half,
    // and hold back the one this read cuts, so every sequence is parsed whole.
    if (self.pendingEscape.length > 0) {
        raw = [self.pendingEscape stringByAppendingString:raw];
        self.pendingEscape = @"";
    }
    NSUInteger unfinished = self.flushingHeldBack ? NSNotFound
                                                  : [self unfinishedEscapeIn:raw];
    if (unfinished != NSNotFound) {
        self.pendingEscape = [raw substringFromIndex:unfinished];
        raw = [raw substringToIndex:unfinished];
        if (raw.length == 0) return;
    }

    // Keep what the program wrote, with the escapes removed and nothing moved,
    // so a link can be read from it later without the redrawing damage.
    [self recordInStream:raw];
    // A program may print a link and then simply wait, in which case nothing
    // ever arrives to close it off. When writing stops, look again.
    self.outputSettled = NO;
    NSUInteger generation = ++self.writeGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf.writeGeneration != generation) return;
        [strongSelf flushHeldBack];
        strongSelf.outputSettled = YES;
        [strongSelf noticeASignInPage];
    });
    NSUInteger i = 0, n = raw.length;
    while (i < n) {
        unichar c = [raw characterAtIndex:i];

        if (c == 0x1B) {                                  // escape
            i++;
            if (i < n && [raw characterAtIndex:i] == '[') {
                i++;
                // A private-mode prefix (?, >, <, =) marks a sequence that
                // changes terminal modes rather than drawing: cursor
                // visibility, mouse reporting, bracketed paste. Consume it
                // whole. Reading its digits as text is what put stray "25l"
                // in the output when a program hid its cursor.
                unichar prefix = 0;
                if (i < n) {
                    unichar p = [raw characterAtIndex:i];
                    if (p == '?' || p == '>' || p == '<' || p == '=') { prefix = p; i++; }
                }
                NSMutableString *parameters = [NSMutableString string];
                unichar final = 0;
                while (i < n) {
                    unichar f = [raw characterAtIndex:i];
                    i++;
                    if ((f >= '0' && f <= '9') || f == ';' || f == ':') {
                        [parameters appendFormat:@"%C", f];
                        continue;
                    }
                    // Some sequences carry an intermediate byte before the one
                    // that ends them — a cursor-shape request is ESC [ 0 space
                    // q. Taking the space as the end left the q to be printed
                    // as ordinary text.
                    if (f >= 0x20 && f <= 0x2F) continue;
                    final = f;
                    break;
                }
                if (prefix != 0) {
                    // Application cursor key mode. A full-screen program turns
                    // this on and from then on expects an arrow as ESC O A
                    // rather than ESC [ A. Both are "the up arrow"; a program
                    // in this mode simply ignores the other one.
                    //
                    // This console parsed the mode and threw it away, so it
                    // always sent ESC [ A — which is why Antigravity's menu sat
                    // there while the arrows were pressed, and why Enter worked
                    // anyway: carriage return is the same byte in both modes.
                    if (prefix == '?' && (final == 'h' || final == 'l')) {
                        for (NSString *one in [parameters componentsSeparatedByString:@";"]) {
                            if (one.integerValue == 1) {
                                self.applicationCursorKeys = (final == 'h');
                            }
                            // Its own screen. A program drawing a whole
                            // interface — a menu, an editor, this chat — asks
                            // for a blank one and then addresses rows by
                            // number within it. Ignoring the request left it
                            // drawing over whatever was already here, with
                            // every row number counted from the wrong place:
                            // the logo came out scrambled, pieces of old rows
                            // showed through, and a reply landed somewhere
                            // that was never displayed.
                            if (one.integerValue == 1049) {
                                if (final == 'h' && !self.onAlternateScreen) {
                                    self.screenUnderneath = self.lines;
                                    self.rowUnderneath = self.row;
                                    self.columnUnderneath = self.column;
                                    self.lines = [NSMutableArray array];
                                    [self.lines addObject:
                                        [[NSMutableAttributedString alloc] init]];
                                    self.row = 0;
                                    self.column = 0;
                                    self.screenOrigin = 0;
                                    self.scrollRegionSet = NO;
                                    // Start the private screen with the exact
                                    // geometry the program was told. Later
                                    // view resizes compare against this model,
                                    // not against an incidental layout pass.
                                    self.modeledColumns = self.columns;
                                    self.modeledRows = [self screenRows];
                                    self.onAlternateScreen = YES;
                                    [self setLineDisciplineRaw:YES];
                                } else if (final == 'l' && self.onAlternateScreen) {
                                    self.lines = self.screenUnderneath.count > 0
                                        ? self.screenUnderneath
                                        : [NSMutableArray arrayWithObject:
                                            [[NSMutableAttributedString alloc] init]];
                                    self.screenUnderneath = nil;
                                    self.row = MIN(self.rowUnderneath, self.lines.count - 1);
                                    self.column = self.columnUnderneath;
                                    self.scrollRegionSet = NO;
                                    self.screenOrigin = self.lines.count > [self screenRows]
                                        ? self.lines.count - [self screenRows] : 0;
                                    self.onAlternateScreen = NO;
                                    [self setLineDisciplineRaw:NO];
                                    [self clampCursorToScreen];
                                }
                            }
                        }
                    }
                    continue;
                }
                NSInteger value = parameters.length ? [parameters intValue] : 1;
                switch (final) {
                    case 'm':                              // colours and weight
                        SlopNetApplySGR(self.ink, parameters);
                        break;
                    case 'A':                              // cursor up
                        [self clampCursorToScreen];
                        {
                            NSUInteger many = value > 0 ? (NSUInteger)value : 1;
                            NSUInteger above = self.row - [self screenTop];
                            self.row -= MIN(many, above);
                        }
                        break;
                    case 'B':                              // cursor down
                        [self clampCursorToScreen];
                        {
                            NSUInteger many = value > 0 ? (NSUInteger)value : 1;
                            NSUInteger bottom = [self screenTop] + [self screenRows] - 1;
                            self.row += MIN(many, bottom - self.row);
                        }
                        [self currentLine];
                        break;
                    case 'C': {                            // right
                        [self clampCursorToScreen];
                        NSUInteger many = value > 0 ? (NSUInteger)value : 1;
                        NSUInteger right = MAX((NSUInteger)1, self.columns) - 1;
                        self.column += MIN(many, right - self.column);
                        break;
                    }
                    case 'D':                              // left
                        [self clampCursorToScreen];
                        {
                            NSUInteger many = value > 0 ? (NSUInteger)value : 1;
                            self.column -= MIN(many, self.column);
                        }
                        break;
                    case 'G':                              // column
                        self.column = value > 0 ? (NSUInteger)(value - 1) : 0;
                        [self clampCursorToScreen];
                        break;
                    case 'E':                              // next line, column 1
                        [self clampCursorToScreen];
                        {
                            NSUInteger many = value > 0 ? (NSUInteger)value : 1;
                            NSUInteger bottom = [self screenTop] + [self screenRows] - 1;
                            self.row += MIN(many, bottom - self.row);
                        }
                        self.column = 0;
                        [self currentLine];
                        break;
                    case 'F':                              // previous line, column 1
                        [self clampCursorToScreen];
                        {
                            NSUInteger many = value > 0 ? (NSUInteger)value : 1;
                            NSUInteger above = self.row - [self screenTop];
                            self.row -= MIN(many, above);
                        }
                        self.column = 0;
                        break;
                    case 'd': {                            // row, counted from the top
                        NSInteger want = value > 0 ? value : 1;
                        NSUInteger relative = MIN((NSUInteger)(want - 1),
                                                  [self screenRows] - 1);
                        self.row = [self screenTop] + relative;
                        [self clampCursorToScreen];
                        [self currentLine];
                        break;
                    }
                    case 's':                              // remember the cursor
                        self.savedRow = self.row;
                        self.savedColumn = self.column;
                        self.hasSavedCursor = YES;
                        break;
                    case 'u':                              // and go back to it
                        if (self.hasSavedCursor) {
                            self.row = self.savedRow;
                            self.column = self.savedColumn;
                            [self clampCursorToScreen];
                            [self currentLine];
                        }
                        break;
                    case 'H': case 'f': {                  // row and column
                        // Both parameters were being thrown away, so every
                        // absolute move went to the same corner.
                        NSArray<NSString *> *parts =
                            [parameters componentsSeparatedByString:@";"];
                        NSInteger wantRow = parts.count > 0 ? [parts[0] integerValue] : 1;
                        NSInteger wantColumn = parts.count > 1 ? [parts[1] integerValue] : 1;
                        if (wantRow < 1) wantRow = 1;
                        if (wantColumn < 1) wantColumn = 1;
                        // A program can have drawn for a larger PTY just
                        // before this view receives the bytes or resize.
                        // Real terminals clamp an absolute position to their
                        // last cell. Deliberately replaying the real recordings
                        // into smaller screens proves the same boundary against
                        // pyte; it is not evidence that their original 94x40
                        // sessions had an edge defect.
                        NSInteger lastRow = (NSInteger)[self screenRows];
                        NSInteger lastColumn = (NSInteger)MAX((NSUInteger)1, self.columns);
                        if (wantRow > lastRow) wantRow = lastRow;
                        if (wantColumn > lastColumn) wantColumn = lastColumn;
                        self.row = [self screenTop] + (NSUInteger)(wantRow - 1);
                        self.column = (NSUInteger)(wantColumn - 1);
                        [self clampCursorToScreen];
                        [self currentLine];
                        break;
                    }
                    case 'r': {                            // set the scrolling region
                        NSArray<NSString *> *parts =
                            [parameters componentsSeparatedByString:@";"];
                        NSUInteger rows = [self screenRows];
                        NSInteger first = parts.count > 0 ? [parts[0] integerValue] : 1;
                        NSInteger last = parts.count > 1 ? [parts[1] integerValue] : (NSInteger)rows;
                        if (first < 1) first = 1;
                        if (last < 1 || last > (NSInteger)rows) last = (NSInteger)rows;
                        if (first >= last) {                 // nonsense, so no region
                            self.scrollRegionSet = NO;
                        } else {
                            self.scrollFirst = (NSUInteger)(first - 1);
                            self.scrollLast = (NSUInteger)(last - 1);
                            self.scrollRegionSet = YES;
                        }
                        // Setting the region puts the cursor at the top left.
                        self.row = self.screenOrigin;
                        self.column = 0;
                        [self clampCursorToScreen];
                        [self currentLine];
                        break;
                    }
                    case 'L': {                            // insert blank rows here
                        [self clampCursorToScreen];
                        NSUInteger many = value > 0 ? (NSUInteger)value : 1;
                        NSUInteger last = self.screenOrigin + [self lastScrollingRow];
                        for (NSUInteger k = 0; k < many && self.row <= last; k++) {
                            while (self.lines.count <= last) {
                                [self.lines addObject:[[NSMutableAttributedString alloc] init]];
                            }
                            [self.lines removeObjectAtIndex:last];
                            [self.lines insertObject:[[NSMutableAttributedString alloc] init]
                                             atIndex:self.row];
                        }
                        self.column = 0;
                        break;
                    }
                    case 'M': {                            // delete rows here
                        [self clampCursorToScreen];
                        NSUInteger many = value > 0 ? (NSUInteger)value : 1;
                        NSUInteger last = self.screenOrigin + [self lastScrollingRow];
                        for (NSUInteger k = 0; k < many && self.row <= last; k++) {
                            if (self.row >= self.lines.count) break;
                            [self.lines removeObjectAtIndex:self.row];
                            NSUInteger at = MIN(last, self.lines.count);
                            [self.lines insertObject:[[NSMutableAttributedString alloc] init]
                                             atIndex:at];
                        }
                        self.column = 0;
                        break;
                    }
                    case '@': {                            // open blank cells here
                        NSMutableAttributedString *line = [self currentLine];
                        NSUInteger many = value > 0 ? (NSUInteger)value : 1;
                        if (self.column <= line.length) {
                            NSString *blank = [@"" stringByPaddingToLength:many
                                                                withString:@" "
                                                           startingAtIndex:0];
                            [line insertAttributedString:
                                [[NSAttributedString alloc] initWithString:blank
                                                                attributes:[self fieldAttributes]]
                                                 atIndex:self.column];
                        }
                        break;
                    }
                    case 'P': {                            // remove cells here
                        NSMutableAttributedString *line = [self currentLine];
                        NSUInteger many = value > 0 ? (NSUInteger)value : 1;
                        if (self.column < line.length) {
                            NSUInteger take = MIN(many, line.length - self.column);
                            [line deleteCharactersInRange:NSMakeRange(self.column, take)];
                        }
                        break;
                    }
                    case 'X': {                            // erase characters
                        // Blank out what is there without moving the cursor
                        // and without shortening the row. Skipping it left
                        // pieces of the previous frame showing through.
                        NSMutableAttributedString *line = [self currentLine];
                        NSUInteger many = value > 0 ? (NSUInteger)value : 1;
                        if (self.column < line.length) {
                            NSUInteger take = MIN(many, line.length - self.column);
                            NSString *blank = [@"" stringByPaddingToLength:take
                                                                withString:@" "
                                                           startingAtIndex:0];
                            [line replaceCharactersInRange:NSMakeRange(self.column, take)
                                      withAttributedString:
                                [[NSAttributedString alloc] initWithString:blank
                                                                attributes:[self fieldAttributes]]];
                        }
                        break;
                    }
                    case 'K': {                            // erase in line
                        NSMutableAttributedString *line = [self currentLine];
                        NSInteger part = parameters.length ? [parameters intValue] : 0;
                        if (part == 1 || part == 2) {
                            NSUInteger upto = MIN(self.column, line.length);
                            if (part == 2) upto = line.length;
                            NSString *blank = [@"" stringByPaddingToLength:upto
                                                                withString:@" "
                                                           startingAtIndex:0];
                            [line replaceCharactersInRange:NSMakeRange(0, upto)
                                      withAttributedString:
                                [[NSAttributedString alloc] initWithString:blank
                                                                attributes:[self fieldAttributes]]];
                        }
                        if (part == 0 || part == 2) {
                            if (self.column < line.length) {
                                [line deleteCharactersInRange:
                                    NSMakeRange(self.column, line.length - self.column)];
                            }
                        }
                        break;
                    }
                    case 'J': {                            // erase in screen
                        // No parameter means erase from the cursor to the end
                        // of the screen, not erase everything. Wiping the lot
                        // threw away the whole conversation each time the
                        // program tidied up below the cursor — the reply had
                        // arrived and was deleted a moment later.
                        NSInteger part = parameters.length ? [parameters intValue] : 0;
                        if (part == 2 || part == 3) {
                            [self.lines removeAllObjects];
                            [self.lines addObject:[[NSMutableAttributedString alloc] init]];
                            // This model discarded the whole addressed buffer,
                            // so its new screen starts with that new first row.
                            // Leaving the old origin behind put the cursor in
                            // clipped scrollback immediately after the clear.
                            self.screenOrigin = 0;
                            self.row = 0;
                            self.column = 0;
                            [self clampCursorToScreen];
                            break;
                        }
                        if (part == 0) {
                            NSMutableAttributedString *line = [self currentLine];
                            if (self.column < line.length) {
                                [line deleteCharactersInRange:
                                    NSMakeRange(self.column, line.length - self.column)];
                            }
                            if (self.row + 1 < self.lines.count) {
                                [self.lines removeObjectsInRange:
                                    NSMakeRange(self.row + 1,
                                                self.lines.count - self.row - 1)];
                            }
                        } else if (part == 1) {
                            for (NSUInteger r = [self screenTop]; r < self.row &&
                                                                  r < self.lines.count; r++) {
                                [self.lines[r] deleteCharactersInRange:
                                    NSMakeRange(0, self.lines[r].length)];
                            }
                            NSMutableAttributedString *line = [self currentLine];
                            NSUInteger upto = MIN(self.column, line.length);
                            NSString *blank = [@"" stringByPaddingToLength:upto
                                                                withString:@" "
                                                           startingAtIndex:0];
                            [line replaceCharactersInRange:NSMakeRange(0, upto)
                                      withAttributedString:
                                [[NSAttributedString alloc] initWithString:blank
                                                                attributes:[self fieldAttributes]]];
                        }
                        break;
                    }
                    default: break;
                }
            } else if (i < n && [raw characterAtIndex:i] == ']') {
                // A window title, or a hyperlink wrapped around some text.
                // Either may be ended by a bell or by ESC backslash, and this
                // looked only for the bell. Zellij marks up nearly everything
                // it draws with hyperlinks ended the other way, so the search
                // ran off the end and ate the entire screen: sixty-four
                // kilobytes of output arrived and one character was drawn.
                i++;
                while (i < n) {
                    unichar here = [raw characterAtIndex:i];
                    if (here == 0x07) { i++; break; }
                    if (here == 0x1B && i + 1 < n &&
                        [raw characterAtIndex:i + 1] == '\\') { i += 2; break; }
                    i++;
                }
            } else if (i < n) {
                // Escapes with no bracket. Two of these move the cursor, and
                // skipping them is what made a menu walk down the screen: the
                // program said "come back to where the menu started", the
                // console heard nothing, and the next frame landed below the
                // last one instead of on top of it.
                unichar next = [raw characterAtIndex:i];
                i++;
                // Escapes that name a character set take a second character:
                // ESC ( B says "ASCII from here on", and programs built on
                // ncurses emit it constantly. Consuming only the bracket left
                // the B to be printed, which is why top came out with stray Bs
                // scattered through every row.
                if (next == '(' || next == ')' || next == '*' || next == '+' ||
                    next == '#' || next == '%') {
                    if (i < n) i++;
                } else if (next == '7') {
                    self.savedRow = self.row;
                    self.savedColumn = self.column;
                    self.hasSavedCursor = YES;
                } else if (next == '8') {
                    if (self.hasSavedCursor) {
                        self.row = self.savedRow;
                        self.column = self.savedColumn;
                        [self clampCursorToScreen];
                        [self currentLine];
                    }
                } else if (next == 'M') {               // up one row, scrolling
                    NSUInteger first = self.screenOrigin +
                        (self.scrollRegionSet ? self.scrollFirst : 0);
                    if (self.row <= first) {
                        [self scrollRegionDown];
                    } else {
                        self.row -= 1;
                    }
                } else if (next == 'D') {               // down one row, scrolling
                    [self newline];
                } else if (next == 'E') {               // down one row, column one
                    [self newline];
                    self.column = 0;
                }
            }
            continue;
        }

        if (c == '\n') { [self lineFeed]; i++; continue; }
        if (c == '\r') { self.column = 0; i++; continue; }
        if (c == 0x08) {                                   // backspace
            if (self.column > 0) self.column--;
            i++;
            continue;
        }
        if (c == '\t') {
            [self putText:@"    "];
            i++;
            continue;
        }
        if (c < 0x20) { i++; continue; }                   // other control bytes

        NSUInteger start = i;
        while (i < n) {
            unichar t = [raw characterAtIndex:i];
            if (t < 0x20 || t == 0x1B) break;
            i++;
        }
        [self putText:[raw substringWithRange:NSMakeRange(start, i - start)]];
    }
    [self setNeedsRedrawSoon];
    [self noticeWhatItIsWaitingFor];
    [self noticeASignInPage];
}

/// Read the line the program stopped on and work out what it wants.
///
/// A program waiting at a prompt has printed the question and no newline, so
/// the tail of the current line is the question. This is a small, deliberate
/// set of shapes — the ones SlopNet's own scripts and ssh/sudo actually use.
/// Anything unrecognised stays ordinary typing, which is the safe direction:
/// the worst case is the console behaves exactly as it did before.
- (void)noticeWhatItIsWaitingFor {
    SlopNetPrompt found = SlopNetPromptNone;
    NSString *line = @"";
    if (self.running) {
        line = [[self currentLine].string
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *lower = line.lowercaseString;
        // Any line still waiting that mentions a password or passphrase is
        // treated as a secret. The confirmation half — "Enter same passphrase
        // again:" — used to fall through to the ordinary typing box, which
        // put the operator's passphrase on screen in clear text. A prompt
        // that ends mid-line and says passphrase is a secret, whichever half
        // of the pair it is.
        BOOL waiting = [lower hasSuffix:@":"] || [lower hasSuffix:@": "];
        if (waiting && ([lower containsString:@"password"] ||
                        [lower containsString:@"passphrase"])) {
            found = SlopNetPromptPassword;
        } else if ([lower hasSuffix:@"[y/n]"] || [lower hasSuffix:@"[y/n]?"] ||
                   [lower hasSuffix:@"(y/n)"] || [lower hasSuffix:@"(yes/no)"] ||
                   [lower hasSuffix:@"[yes/no]"]) {
            found = SlopNetPromptConfirm;
        } else if (waiting && ([lower containsString:@"press return"] ||
                               [lower containsString:@"press enter"] ||
                               [lower containsString:@"hit return"] ||
                               [lower containsString:@"hit enter"])) {
            // "Press Return to continue" through a typing box means clicking
            // the box, pressing Return, then pressing Send. One button.
            found = SlopNetPromptContinue;
        }
    }
    if (found == self.waitingFor) return;
    self.waitingFor = found;
    if ([self.delegate respondsToSelector:@selector(console:asksFor:question:)]) {
        [self.delegate console:self asksFor:found question:line];
    }
}

/// Spot a sign-in link, and the short code that goes with it.
///
/// Deliberately does NOT open anything by itself. The link is put in front of
/// the person with its address visible and a button to open it, because the
/// console shows output from programs, and output is not an instruction.
static NSString *codeInsideAddress(NSURL *page);
static BOOL codeLooksReal(NSString *candidate, NSString *text, NSRange where);

/// Strip the escape sequences and keep the text, split into rows the way the
/// program wrote them. Nothing here moves a cursor or overwrites anything.
/// Where an escape sequence begins that this text does not finish.
///
/// A read stops wherever it stops, which can be in the middle of an escape
/// sequence. Parsing each read on its own loses that sequence twice over: the
/// ESC is consumed with nothing after it, so the rest is printed as ordinary
/// text — "[19;34H" turned up in the middle of a menu — and the cursor move it
/// asked for never happens, so every frame after it lands in the wrong place.
/// A full-screen program writes thousands of these, so at four kilobytes a
/// read it is not a question of whether one gets cut.
/// Take bytes as they come off the program, however they are cut up.
///
/// A read stops wherever it stops, which can be halfway through a character.
/// Decoding each read on its own fails there, and falling back to Latin-1 for
/// the whole read turned every box rule into a row of "â" — the rest of the
/// read was fine and was mangled with it. Whatever is left over waits here for
/// the bytes that finish it.
///
/// This is the one place bytes become text, so that a recording replayed in
/// pieces goes through exactly what the running program goes through.
/// How many of these bytes end on a character boundary.
///
/// Asking Foundation to decode a run that stops halfway through a character
/// does not reliably fail — it drops the partial character and hands back the
/// rest. The dropped bytes are then missing from the next read, which begins
/// midway through a character, and every read after that is wrong too: one cut
/// in the wrong place turned every box rule from there on into rows of "â".
/// So the boundary is found here rather than inferred from a decode failing.
static NSUInteger wholeCharacterBytes(const unsigned char *bytes, NSUInteger count) {
    if (count == 0) return 0;
    NSUInteger at = count, back = 0;
    while (at > 0 && back < 4) {
        at--; back++;
        unsigned char c = bytes[at];
        if ((c & 0xC0) == 0x80) continue;              // inside a character
        NSUInteger needs = 1;
        if ((c & 0x80) == 0x00)      needs = 1;
        else if ((c & 0xE0) == 0xC0) needs = 2;
        else if ((c & 0xF0) == 0xE0) needs = 3;
        else if ((c & 0xF8) == 0xF0) needs = 4;
        return (at + needs <= count) ? count : at;
    }
    return count;
}

/// Let go of anything being held back for an end that is not coming.
///
/// Bytes wait here for the ones that finish them, and the start of an escape
/// sequence waits for its end. That is right while a program is writing and
/// wrong once it has stopped: whatever is held is then simply missing from the
/// screen. A terminal shows it rather than swallowing it.
- (void)flushHeldBack {
    if (self.readCarry.length > 0) {
        NSString *rest = [[NSString alloc] initWithData:self.readCarry
                                               encoding:NSISOLatin1StringEncoding];
        [self.readCarry setLength:0];
        if (rest.length > 0) [self consume:rest];
    }
    if (self.pendingEscape.length > 0) {
        NSString *stuck = self.pendingEscape;
        self.pendingEscape = @"";
        self.flushingHeldBack = YES;
        [self consume:stuck];
        self.flushingHeldBack = NO;
    }
}

- (void)consumeBytes:(NSData *)data {
    if (self.readCarry == nil) self.readCarry = [NSMutableData data];
    [self.readCarry appendData:data];
    const unsigned char *bytes = self.readCarry.bytes;
    NSUInteger usable = wholeCharacterBytes(bytes, self.readCarry.length);
    if (usable == 0) return;                            // wait for the rest
    NSString *chunk = [[NSString alloc] initWithBytes:bytes
                                               length:usable
                                             encoding:NSUTF8StringEncoding];
    if (chunk == nil) {
        // Genuinely not UTF-8 rather than merely cut short.
        chunk = [[NSString alloc] initWithBytes:bytes
                                         length:usable
                                       encoding:NSISOLatin1StringEncoding];
    }
    [self.readCarry replaceBytesInRange:NSMakeRange(0, usable) withBytes:NULL length:0];
    if (chunk.length > 0) [self consume:chunk];
}

- (NSUInteger)unfinishedEscapeIn:(NSString *)text {
    NSRange last = [text rangeOfString:@"\033" options:NSBackwardsSearch];
    if (last.location == NSNotFound) return NSNotFound;
    NSUInteger n = text.length;
    // Long enough that it is not an escape sequence at all; keeping it would
    // swallow real output waiting for an end that never comes. A window title
    // can be long, so this is well above anything a cursor move needs — at 128
    // it fired on ordinary sequences whenever the reads were small, which is
    // the same fault it was meant to prevent.
    if (n - last.location > 4096) return NSNotFound;
    NSUInteger i = last.location + 1;
    if (i >= n) return last.location;
    unichar kind = [text characterAtIndex:i];
    if (kind == '[') {
        // Parameters are all below '@', so they cannot be mistaken for the
        // byte that ends the sequence.
        for (i++; i < n; i++) {
            unichar f = [text characterAtIndex:i];
            if (f >= '@' && f <= '~') return NSNotFound;
        }
        return last.location;
    }
    if (kind == '(' || kind == ')' || kind == '*' || kind == '+' ||
        kind == '#' || kind == '%') {
        return (i + 1 < n) ? NSNotFound : last.location;
    }
    if (kind == ']') {
        for (i++; i < n; i++) {
            unichar here = [text characterAtIndex:i];
            if (here == 0x07) return NSNotFound;
            if (here == 0x1B && i + 1 < n && [text characterAtIndex:i + 1] == '\\') {
                return NSNotFound;
            }
        }
        return last.location;
    }
    return NSNotFound;                       // one character, and it is here
}

- (void)recordInStream:(NSString *)raw {
    static NSRegularExpression *escapes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        escapes = [NSRegularExpression regularExpressionWithPattern:
            @"\033\\][^\007\033]*(\007|\033\\\\)"   // window title
            @"|\033\\[[0-9;?<>=]*[@-~]"                       // the usual sort
            @"|\033[78MDEHc=>]"                               // the bracketless sort
                                                           options:0 error:nil];
    });
    NSString *plain = [escapes stringByReplacingMatchesInString:raw options:0
                                                          range:NSMakeRange(0, raw.length)
                                                   withTemplate:@""];
    if (self.streamLines == nil) self.streamLines = [NSMutableArray array];
    if (self.streamTail == nil) self.streamTail = [NSMutableString string];
    for (NSUInteger i = 0; i < plain.length; i++) {
        unichar c = [plain characterAtIndex:i];
        if (c == '\n' || c == '\r') {
            if (self.streamTail.length > 0) {
                [self.streamLines addObject:[self.streamTail copy]];
                [self.streamTail setString:@""];
            }
            continue;
        }
        [self.streamTail appendFormat:@"%C", c];
    }
    if (self.streamLines.count > 400) {
        [self.streamLines removeObjectsInRange:NSMakeRange(0, self.streamLines.count - 400)];
    }
}

/// Whether a sign-in address is intact enough to be worth opening.
///
/// A link rebuilt from pieces can come out with a parameter repeated, and
/// Google says so in as many words: "OAuth 2 parameters can only have a single
/// value: scope". Three such links were opened in three windows, each broken a
/// different way. A repeated parameter means the rebuilding went wrong, so the
/// link is not offered at all rather than opened and refused.
static BOOL addressSurvivedRebuilding(NSURL *page) {
    // Two schemes in one address means two links were run together. The
    // parameter names can still all be different when that happens, so the
    // test below would pass it — this is what actually caught it.
    NSString *whole = page.absoluteString;
    NSUInteger schemes = 0, at = 0;
    while (at < whole.length) {
        NSRange found = [whole rangeOfString:@"://"
                                     options:0
                                       range:NSMakeRange(at, whole.length - at)];
        if (found.location == NSNotFound) break;
        schemes++;
        at = NSMaxRange(found);
    }
    if (schemes != 1) return NO;

    NSURLComponents *parts = [NSURLComponents componentsWithURL:page
                                        resolvingAgainstBaseURL:NO];
    NSArray<NSURLQueryItem *> *items = parts.queryItems;
    if (items.count == 0) return YES;
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSURLQueryItem *item in items) {
        if ([seen containsObject:item.name]) return NO;
        [seen addObject:item.name];
    }
    return YES;
}

- (void)noticeASignInPage {
    if (!self.running) return;
    // Read the link from what the program wrote, not from the drawn screen.
    //
    // A program redrawing a boxed frame writes over part of what is already
    // there, so a drawn row can hold pieces of two or three frames at once.
    // Three attempts at reassembling that produced three different malformed
    // links, and all three were opened. What the program wrote is not damaged
    // in that way, so the link is taken from there.
    //
    // It can still arrive in pieces, because a program may split it itself to
    // fit a box. A row of nothing but link characters continues the row above
    // it; a space, a box rule or a blank row ends it, which is what stops
    // ordinary words being pulled into a link.
    NSCharacterSet *notLink = [[NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
        @"0123456789-._~:/?#[]@!$&'()*+,;=%"] invertedSet];
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    NSUInteger begin = self.streamLines.count > 40 ? self.streamLines.count - 40 : 0;
    for (NSUInteger i = begin; i < self.streamLines.count; i++) {
        [rows addObject:self.streamLines[i]];
    }
    NSUInteger finished = rows.count;
    if (self.streamTail.length > 0) [rows addObject:self.streamTail];

    NSMutableString *joined = [NSMutableString string];
    NSUInteger closed = 0;
    NSUInteger row = 0;
    for (NSString *line in rows) {
        if (row++ == finished) closed = joined.length;
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];
        BOOL continues = NO;
        // A program showing a link usually redraws the frame holding it — an
        // animated "Signing in..." does it several times a second — so the
        // same link arrives over and over. The row starting the next copy is
        // made of link characters like any other, and joining it to the tail
        // of the copy above produced one long spliced address that Google
        // refused. A row carrying its own scheme starts a link, never
        // continues one.
        if (trimmed.length > 0 &&
            [trimmed rangeOfString:@"://"].location == NSNotFound &&
            [trimmed rangeOfCharacterFromSet:notLink].location == NSNotFound) {
            NSRange lastBreak = [joined rangeOfString:@"\n" options:NSBackwardsSearch];
            NSString *tail = (lastBreak.location == NSNotFound)
                ? joined : [joined substringFromIndex:NSMaxRange(lastBreak)];
            continues = ([tail rangeOfString:@"://"].location != NSNotFound);
        }
        // The break goes in before the next row, not after this one: the test
        // above reads what has accumulated on the current row, and a trailing
        // break would leave it looking at nothing every time.
        if (continues) {
            [joined appendString:trimmed];
        } else {
            if (joined.length > 0) [joined appendString:@"\n"];
            [joined appendString:line];
        }
    }
    if (rows.count == finished) closed = joined.length;
    // Everything before the final row is finished with. A link on the final
    // row is not: the next row to arrive may continue it, and a chunk can end
    // on a row boundary in the middle of one. Waiting costs a moment; not
    // waiting opened a half-written address.
    NSRange lastRow = [joined rangeOfString:@"\n" options:NSBackwardsSearch];
    NSUInteger beforeLastRow = (lastRow.location == NSNotFound) ? 0 : NSMaxRange(lastRow);
    if (closed > beforeLastRow) closed = beforeLastRow;
    if (self.outputSettled) closed = joined.length;
    // How much of this is finished with. A link still arriving sits at the end
    // of the last row, and taking it then gives whatever has turned up so far
    // — which is how a half-written address came to be opened, and then held
    // on to by the one-per-run guard while the whole of it arrived a moment
    // later. A link only counts once something after it has closed it off.
    NSUInteger closedLength = closed;
    NSString *recent = joined;
    static NSRegularExpression *link;
    static NSRegularExpression *shortCode;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        link = [NSRegularExpression regularExpressionWithPattern:
                @"https://[A-Za-z0-9._~:/?#@!$&'()*+,;=%-]+" options:0 error:nil];
        // The shape these one-time codes take: short, upper-case, split by a
        // hyphen — but the group lengths differ by provider, so 4-4, 3-4 and
        // 4-6 all have to match. Anchored on word boundaries so it cannot
        // match a slice of a longer token. Deliberately broad; codeLooksReal
        // below throws out the hyphenated English this would otherwise catch.
        shortCode = [NSRegularExpression regularExpressionWithPattern:
                     @"\\b[A-Z0-9]{3,6}-[A-Z0-9]{3,6}\\b" options:0 error:nil];
    });
    // Every link in the recent output, not just the first.
    //
    // An install prints npm's upgrade notice — "Changelog: https://github.com/
    // npm/cli/releases/tag/v12.0.2" — and then the sign-in starts. Taking the
    // first link opened that changelog in the operator's browser and called it
    // a sign-in page. The last link that looks like an authorisation endpoint
    // wins; a plain link is only used when nothing better is on screen.
    NSArray<NSTextCheckingResult *> *all =
        [link matchesInString:recent options:0 range:NSMakeRange(0, recent.length)];
    if (all.count == 0) return;

    NSString *address = nil;
    BOOL authorisation = NO;
    for (NSTextCheckingResult *candidate in all) {
        if (NSMaxRange(candidate.range) > closedLength) continue;   // still arriving
        NSString *found = [recent substringWithRange:candidate.range];
        while (found.length > 0 &&
               [@".,);:" rangeOfString:[found substringFromIndex:found.length - 1]].location
               != NSNotFound) {
            found = [found substringToIndex:found.length - 1];
        }
        NSString *lowered = found.lowercaseString;
        BOOL authish = [lowered containsString:@"/device"] || [lowered containsString:@"/oauth"]
                    || [lowered containsString:@"/auth"]   || [lowered containsString:@"/login"]
                    || [lowered containsString:@"/activate"]
                    || [lowered containsString:@"user_code"];
        // The newest copy of a link can be half-written, because the frame
        // holding it is still arriving. Every complete copy is identical, so
        // the longest one is the whole of it.
        if (authish) {
            if (!authorisation || found.length >= address.length) address = found;
            authorisation = YES;
        }
        else if (address == nil) address = found;     // a fallback, until a better one
    }
    if (address == nil) return;

    NSURL *page = [NSURL URLWithString:address];
    if (page == nil) return;
    // A half-written address can end inside a percent escape, and building a
    // URL from that quietly re-encodes every escape in it — "%3A" becomes
    // "%253A" and the whole thing means something else. If anything had to be
    // rewritten to make it a URL, it was not a URL.
    if (![page.absoluteString isEqualToString:address]) return;

    // A link on its own is not a sign-in. Installing a coding app prints an
    // npm upgrade notice carrying a changelog link, and that link was offered
    // to the operator as "a coding app needs you to sign in" — with a Skip
    // button belonging to a queue that was not running, so nothing happened
    // when it was pressed.
    //
    // The words around the link have to say what it is for.
    NSString *lower = recent.lowercaseString;
    BOOL saysSo = [lower containsString:@"sign in"] || [lower containsString:@"signin"]
                || [lower containsString:@"log in"]  || [lower containsString:@"login"]
                || [lower containsString:@"authorize"] || [lower containsString:@"authorise"]
                || [lower containsString:@"authenticate"]
                // Not a bare "verify": an installer printing "Verifying
                // checksum" offered its own download URL as a page to sign in
                // at, three times in one install. Same shape as a bare "code"
                // matching Codex.
                || [lower containsString:@"verification code"]
                || [lower containsString:@"verify your"]
                || [lower containsString:@"to verify"]
                // Not a bare "code": the Codex CLI has it in its name, and
                // installing it was enough to raise a false sign-in.
                || [lower containsString:@"one-time code"]
                || [lower containsString:@"enter the code"]
                || [lower containsString:@"enter code"]
                || [lower containsString:@"confirm this code"];
    // Or the address itself is plainly an authorisation endpoint. Providers
    // word the surrounding sentence differently; the path rarely lies.
    NSString *where = address.lowercaseString;
    BOOL looksLikeAuth = [where containsString:@"/device"] || [where containsString:@"/oauth"]
                      || [where containsString:@"/auth"]   || [where containsString:@"/login"]
                      || [where containsString:@"/activate"]
                      || [where containsString:@"user_code"];
    if (!saysSo && !looksLikeAuth) return;
    if (!addressSurvivedRebuilding(page)) return;
    // Wait for the program to stop writing before opening anything. A link
    // arrives in pieces and a program redrawing its frame prints more after
    // each piece, so at any moment mid-write the longest thing that looks like
    // a link may be half of one. Everything that went wrong here came from
    // acting on what had turned up so far.
    if (authorisation && !self.outputSettled) return;

    // The code first, because whether this is worth announcing depends on it.
    // Some sign-in pages carry it in the address, which is exact; otherwise
    // read it out of the surrounding text.
    NSString *code = codeInsideAddress(page);
    if (code == nil) {
        NSTextCheckingResult *codeMatch =
            [shortCode firstMatchInString:recent options:0 range:NSMakeRange(0, recent.length)];
        if (codeMatch != nil) {
            NSString *candidate = [recent substringWithRange:codeMatch.range];
            if (codeLooksReal(candidate, recent, codeMatch.range)) code = candidate;
        }
    }

    // A program prints the link, then the code a line or two later. Announcing
    // once per address meant the bar went up with the link and no code, and
    // never updated — so the code had to be copied by hand, which is the whole
    // thing this was meant to stop. Announce again when the code arrives.
    // One sign-in page per run. Three were offered last time, each rebuilt
    // wrongly in a different way, and all three were opened at once.
    BOOL sameAddress = [address isEqualToString:self.announcedSignIn];
    if (authorisation && self.announcedAnAuthorisation && !sameAddress) return;
    if (sameAddress) {
        if (code == nil) return;                                  // nothing new
        if ([code isEqualToString:self.announcedCode]) return;    // already said
    }
    self.announcedSignIn = address;
    self.announcedCode = code;
    self.signInLinkIsAuthorisation = authorisation;
    if (authorisation) self.announcedAnAuthorisation = YES;

    if ([self.delegate respondsToSelector:@selector(console:needsSignIn:code:)]) {
        [self.delegate console:self needsSignIn:page code:code];
    }
}

/// A one-time code carried in the address itself, which several sign-in pages
/// do (`?user_code=WDJB-MJHT`). Exact when it is there, so it wins.
static NSString *codeInsideAddress(NSURL *page) {
    NSURLComponents *parts = [NSURLComponents componentsWithURL:page resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in parts.queryItems) {
        NSString *name = item.name.lowercaseString;
        if (([name isEqualToString:@"user_code"] || [name isEqualToString:@"code"] ||
             [name isEqualToString:@"otc"]) && item.value.length > 0) {
            return item.value;
        }
    }
    return nil;
}

/// Throw out the hyphenated English the code pattern also matches, so SHOUTED
/// words like READ-ONLY never end up on the Copy button.
///
/// Shape alone cannot do it: READ-ONLY and WDJB-MJHT are both nine letters
/// with a hyphen in the middle, and the letters-only form is a real code —
/// GitHub's device codes have no digits at all. So a candidate carrying a
/// digit is taken on its shape, and a letters-only one is taken only when the
/// text around it says what it is. Its own line or the line above, because
/// printing "Your code:" and then the code on a line of its own is common.
static BOOL codeLooksReal(NSString *candidate, NSString *text, NSRange where) {
    if ([candidate rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet].location
        != NSNotFound) {
        return YES;
    }
    NSRange line = [text lineRangeForRange:where];
    if (line.location > 0) {
        NSRange above = [text lineRangeForRange:NSMakeRange(line.location - 1, 0)];
        line = NSUnionRange(above, line);
    }
    return [[text substringWithRange:line].lowercaseString containsString:@"code"];
}

#pragma mark - for probes only

- (NSString *)string {
    [self redraw];
    return self.output.textStorage.string;
}

- (void)scrollToTopForTesting {
    [self redraw];
    [self.output.layoutManager ensureLayoutForTextContainer:self.output.textContainer];
    [self.scroller.contentView scrollToPoint:NSZeroPoint];
    [self.scroller reflectScrolledClipView:self.scroller.contentView];
    self.followingTail = NO;
}

- (void)scrollToBottomForTesting {
    [self redraw];
    [self.output scrollRangeToVisible:NSMakeRange(self.output.textStorage.length, 0)];
    self.followingTail = YES;
}

- (CGFloat)scrollOffsetForTesting {
    return self.scroller.contentView.bounds.origin.y;
}

- (BOOL)isFollowingTailForTesting {
    return self.followingTail || [self atTail];
}

- (NSString *)collectedOutput {
    if (self.collected == nil) return @"";
    // Escape sequences are stripped here rather than parsed: this text is
    // going into a panel that draws its own colours, and a stray SGR from the
    // program would leak into the panel fill and stain the rest of the row.
    static NSRegularExpression *escapes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        escapes = [NSRegularExpression regularExpressionWithPattern:
                   @"\\x1B\\[[0-9;?]*[ -/]*[@-~]" options:0 error:nil];
    });
    NSString *clean = [escapes stringByReplacingMatchesInString:self.collected options:0
                                                          range:NSMakeRange(0, self.collected.length)
                                                   withTemplate:@""];
    clean = [clean stringByReplacingOccurrencesOfString:@"\r" withString:@""];
    return [clean stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

/// The shapes that must never be carried into a prompt. Matches
/// crew.py's _SECRET_SHAPES, which redacts the same things server-side.
static NSString *SlopNetWithoutSecrets(NSString *text) {
    static NSArray<NSString *> *patterns;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        patterns = @[
            @"AKIA[0-9A-Z]{16}",
            @"gh[pousr]_[A-Za-z0-9]{20,}",
            @"sk-[A-Za-z0-9_-]{20,}",
            @"[A-Za-z0-9+/]{40,}={0,2}",                 // long base64-ish blobs
            @"(?i)bearer\\s+[A-Za-z0-9._-]{16,}",
            @"(?i)(api[_-]?key|secret|token|password)\\s*[:=]\\s*\\S+",
            @"-----BEGIN[^-]*PRIVATE KEY-----",
            @"ssh-(rsa|ed25519)\\s+[A-Za-z0-9+/=]+",
        ];
    });
    NSMutableString *clean = [text mutableCopy];
    for (NSString *pattern in patterns) {
        NSRegularExpression *expression =
            [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        if (expression == nil) continue;
        [expression replaceMatchesInString:clean options:0
                                     range:NSMakeRange(0, clean.length)
                              withTemplate:@"[redacted]"];
    }
    return clean;
}

- (NSString *)recentLinesForContext:(NSUInteger)count {
    [self redraw];
    NSUInteger from = self.lines.count > count ? self.lines.count - count : 0;
    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    for (NSUInteger i = from; i < self.lines.count; i++) {
        NSString *line = [self.lines[i].string
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (line.length > 0) [kept addObject:line];
    }
    return SlopNetWithoutSecrets([kept componentsJoinedByString:@"\n"]);
}

- (NSString *)screenTextForTesting {
    [self redraw];
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    NSUInteger first = self.screenOrigin;
    NSUInteger many = [self screenRows];
    for (NSUInteger r = first; r < first + many; r++) {
        NSString *row = r < self.lines.count ? self.lines[r].string : @"";
        while (row.length > 0 && [row hasSuffix:@" "]) {
            row = [row substringToIndex:row.length - 1];
        }
        [rows addObject:row];
    }
    return [rows componentsJoinedByString:@"\n"];
}

- (NSString *)textForTesting {
    [self redraw];
    return self.output.textStorage.string;
}

- (void)note:(NSString *)text {
    // Written by this app rather than by a program, so it never passes through
    // a terminal and nothing turns its newlines into a return as well. Since a
    // line feed started meaning "down, same column" — which is what it means —
    // a panel written with bare newlines had every row start where the row
    // above finished, and the message panels came out as a staircase.
    NSString *body = [text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    body = [body stringByReplacingOccurrencesOfString:@"\n" withString:@"\r\n"];
    [self consume:[NSString stringWithFormat:@"%@\r\n", body]];
}

#pragma mark - lines that can be redrawn (how a glyph animates)

/// Render a block of ANSI text into finished lines, with its own pen. Used
/// for panels, which are colour and newlines only — cursor motion inside a
/// replaceable block is not supported, because the block has no cursor.
- (NSArray<NSMutableAttributedString *> *)renderBlock:(NSString *)text {
    NSMutableArray<NSMutableAttributedString *> *rendered = [NSMutableArray array];
    // Its own pen, so a panel cannot leak colour into the live stream (or
    // inherit half a state from whatever the last program was printing).
    SlopNetInk *pen = [[SlopNetInk alloc] init];
    for (NSString *raw in [text componentsSeparatedByString:@"\n"]) {
        NSMutableAttributedString *line = [[NSMutableAttributedString alloc] init];
        NSUInteger i = 0, n = raw.length;
        while (i < n) {
            unichar c = [raw characterAtIndex:i];
            if (c == 0x1B) {
                i++;
                if (i < n && [raw characterAtIndex:i] == '[') {
                    i++;
                    NSMutableString *parameters = [NSMutableString string];
                    unichar final = 0;
                    while (i < n) {
                        unichar f = [raw characterAtIndex:i];
                        i++;
                        if ((f >= '0' && f <= '9') || f == ';' || f == ':') {
                            [parameters appendFormat:@"%C", f];
                            continue;
                        }
                        final = f;
                        break;
                    }
                    if (final == 'm') SlopNetApplySGR(pen, parameters);
                }
                continue;
            }
            NSUInteger start = i;
            while (i < n && [raw characterAtIndex:i] != 0x1B) i++;
            if (i > start) {
                [line appendAttributedString:[[NSAttributedString alloc]
                    initWithString:[raw substringWithRange:NSMakeRange(start, i - start)]
                        attributes:[self attributesForInk:pen]]];
            }
        }
        [rendered addObject:line];
    }
    return rendered;
}

- (NSInteger)noteReplaceable:(NSString *)text {
    NSArray<NSMutableAttributedString *> *block = [self renderBlock:text];
    // Start on a fresh line so the block owns whole rows; the token names
    // the first of them.
    if ([self currentLine].length > 0) [self newline];
    NSInteger token = self.droppedLines + (NSInteger)self.row;
    for (NSUInteger index = 0; index < block.count; index++) {
        [self currentLine];
        self.lines[self.row] = block[index];
        [self newline];
    }
    if (self.blockHeights == nil) self.blockHeights = [NSMutableDictionary dictionary];
    self.blockHeights[@(token)] = @(block.count);
    [self setNeedsRedrawSoon];
    return token;
}

- (BOOL)replaceLinesFromToken:(NSInteger)token with:(NSString *)text {
    NSInteger start = token - self.droppedLines;
    if (start < 0) return NO;                       // scrolled out of the buffer
    if ((NSUInteger)start > self.lines.count) return NO;

    // A block can change height. A reply being typed into a panel starts as
    // three lines — two rules and a header — and grows as the words wrap, and
    // this used to refuse the moment the new block was taller than the old
    // one. The reply simply stopped mid-sentence, and the header kept its
    // thinking glyph because the finished frame never landed either.
    NSArray<NSMutableAttributedString *> *block = [self renderBlock:text];
    if (self.blockHeights == nil) self.blockHeights = [NSMutableDictionary dictionary];
    NSNumber *known = self.blockHeights[@(token)];
    NSUInteger was = known ? known.unsignedIntegerValue : block.count;
    NSUInteger end = MIN(self.lines.count, (NSUInteger)start + was);

    NSRange old = NSMakeRange((NSUInteger)start, end - (NSUInteger)start);
    [self.lines replaceObjectsInRange:old withObjectsFromArray:block];
    self.blockHeights[@(token)] = @(block.count);

    // The cursor sits after the block; keep it there as the block changes size.
    if (self.row >= (NSUInteger)start) {
        NSInteger moved = (NSInteger)block.count - (NSInteger)old.length;
        NSInteger row = (NSInteger)self.row + moved;
        self.row = (NSUInteger)MAX(0, row);
    }
    if (self.lines.count == 0) [self.lines addObject:[[NSMutableAttributedString alloc] init]];
    if (self.row >= self.lines.count) self.row = self.lines.count - 1;

    [self setNeedsRedrawSoon];
    return YES;
}

- (void)clear {
    [self.lines removeAllObjects];
    [self.lines addObject:[[NSMutableAttributedString alloc] init]];
    self.row = 0;
    self.column = 0;
    [self.ink reset];
    // Every outstanding animation token now points at nothing. Moving the
    // origin past them makes replaceLinesFromToken: answer NO, which is how
    // an animation learns to stop.
    self.droppedLines += (NSInteger)kMaxLines;
    [self setNeedsRedrawSoon];
}

#pragma mark - the status line

- (void)setStatusText:(NSString *)text glyph:(NSString *)glyph tint:(NSColor *)tint {
    NSString *safeText = text ?: @"";
    if (glyph.length == 0) {
        self.status.stringValue = safeText;
        self.status.textColor = tint ?: [NSColor secondaryLabelColor];
        return;
    }
    NSMutableAttributedString *line = [[NSMutableAttributedString alloc] init];
    // The badge needs the colour face; the words stay in the system font so
    // the status line still looks like part of the app.
    [line appendAttributedString:[[NSAttributedString alloc]
        initWithString:[glyph stringByAppendingString:@"  "]
            attributes:@{NSFontAttributeName: [SlopNetBrand consoleFontOfSize:13.5]}]];
    [line appendAttributedString:[[NSAttributedString alloc]
        initWithString:safeText
            attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:11],
                         NSForegroundColorAttributeName: tint ?: [NSColor secondaryLabelColor]}]];
    self.status.attributedStringValue = line;
}

#pragma mark - running

- (BOOL)runExecutable:(NSString *)path arguments:(NSArray<NSString *> *)arguments {
    self.collected = nil;      // this run's output, not the last one's
    if (self.running) {
        [self note:@"Something is already running here. Stop it first."];
        return NO;
    }
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
        [self note:[NSString stringWithFormat:
            @"Cannot run %@ — it is missing or not executable.", path]];
        return NO;
    }

    // A new PTY starts in the terminal's default input/addressing modes. A
    // child that was stopped before it emitted cleanup must not make the next
    // child receive application-mode arrows or inherit its margins/cursor.
    self.applicationCursorKeys = NO;
    self.scrollRegionSet = NO;
    self.hasSavedCursor = NO;

    // Tell the child the real width of the field, so its own panels and
    // progress lines wrap where the window actually ends.
    self.modeledColumns = self.columns;
    self.modeledRows = self.visibleRows;
    struct winsize size = {0};
    size.ws_col = (unsigned short)self.modeledColumns;
    size.ws_row = (unsigned short)self.modeledRows;

    int master = -1;
    pid_t pid = forkpty(&master, NULL, NULL, &size);
    if (pid < 0) {
        [self note:@"macOS would not give SlopNet a terminal for that program."];
        return NO;
    }

    if (pid == 0) {
        // Child: become the program. Nothing here may touch Cocoa.
        NSMutableArray *all = [NSMutableArray arrayWithObject:path];
        [all addObjectsFromArray:arguments ?: @[]];
        char **argv = calloc(all.count + 1, sizeof(char *));
        for (NSUInteger i = 0; i < all.count; i++) {
            argv[i] = strdup([all[i] UTF8String]);
        }
        argv[all.count] = NULL;
        setenv("TERM", "xterm-256color", 1);
        setenv("COLORTERM", "truecolor", 1);
        setenv("SLOPNET_IN_APP", "1", 1);
        execv(path.UTF8String, argv);
        _exit(127);                    // only reached if execv failed
    }

    self.master = master;
    self.child = pid;
    self.announcedSignIn = nil;
    self.announcedAnAuthorisation = NO;
    self.streamLines = [NSMutableArray array];
    self.streamTail = [NSMutableString string];
    self.pendingEscape = @"";
    self.readCarry = [NSMutableData data];
    self.onAlternateScreen = NO;
    self.screenUnderneath = nil;
    self.announcedCode = nil;
    self.stopButton.enabled = YES;
    [self setStatusText:[NSString stringWithFormat:@"Running %@ …", path.lastPathComponent]
                  glyph:nil
                   tint:nil];

    __weak typeof(self) weakSelf = self;
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    self.reader = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, master, 0, queue);
    dispatch_source_set_event_handler(self.reader, ^{
        char buffer[4096];
        ssize_t got = read(master, buffer, sizeof(buffer));
        if (got <= 0) {
            dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf childEnded]; });
            return;
        }
        NSData *piece = [NSData dataWithBytes:buffer length:(NSUInteger)got];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (strongSelf == nil) return;
            [strongSelf consumeBytes:piece];
        });
    });
    dispatch_resume(self.reader);
    return YES;
}

- (void)childEnded {
    if (self.child <= 0) return;
    if (self.reader) {
        dispatch_source_cancel(self.reader);
        self.reader = nil;
    }
    int raw = 0;
    pid_t finished = waitpid(self.child, &raw, WNOHANG);
    if (finished == 0) {
        // Not reaped yet: wait briefly rather than leaving a zombie.
        waitpid(self.child, &raw, 0);
    }
    int status = WIFEXITED(raw) ? WEXITSTATUS(raw) : -1;
    if (self.master >= 0) { close(self.master); self.master = -1; }
    self.child = -1;
    self.stopButton.enabled = NO;
    // A program that dies mid-colour must not tint everything printed after
    // it; the pen goes back to the field's own ink.
    [self.ink reset];
    [self noticeWhatItIsWaitingFor];

    BOOL quiet = self.quietWhenItWorks;
    self.quietWhenItWorks = NO;          // one run only
    self.collectsOutput = NO;            // the buffer stays for the delegate
    if (status == 0) {
        [self setStatusText:@"Finished successfully." glyph:nil tint:nil];
        if (!quiet) [self note:@"\n— finished —"];
    } else if (status < 0) {
        [self setStatusText:@"Stopped." glyph:nil tint:nil];
        [self note:@"\n— stopped —"];
    } else {
        [self setStatusText:[NSString stringWithFormat:
            @"That did not work. The lines above say what happened."]
                      glyph:nil
                       tint:nil];
        // "code 2" is a number for a developer. The lines above already say
        // what went wrong in the program's own words; this just has to say
        // that it did not work, and not pretend to know why.
        [self note:@"\n— that did not work —"];
    }
    // Draw the last of it now rather than on a queued tick, so the final
    // lines — which are the ones saying what to do next — are on screen the
    // instant the program stops.
    [self redraw];
    if ([self.delegate respondsToSelector:@selector(console:finishedWithStatus:)]) {
        [self.delegate console:self finishedWithStatus:status];
    }
}

- (void)sendKey:(SlopNetKey)key {
    NSString *letter = nil;
    switch (key) {
        case SlopNetKeyUp:    letter = @"A"; break;
        case SlopNetKeyDown:  letter = @"B"; break;
        case SlopNetKeyRight: letter = @"C"; break;
        case SlopNetKeyLeft:  letter = @"D"; break;
        case SlopNetKeyEscape:    [self sendKeys:@"\033"]; return;
        case SlopNetKeyTab:       [self sendKeys:@"\t"];   return;
        case SlopNetKeyEnter:     [self sendKeys:@"\r"];   return;
        case SlopNetKeyInterrupt: [self sendKeys:@"\003"]; return;
    }
    [self sendKeys:[NSString stringWithFormat:@"\033%@%@",
                    self.applicationCursorKeys ? @"O" : @"[", letter]];
}

/// Let single keys through, or go back to whole lines.
///
/// A terminal starts in the mode where the line discipline collects what is
/// typed and hands the program a whole line at a time. That is right for a
/// password or a yes-or-no answer. It is wrong for a program that reads keys
/// as they come: Control-G written to the terminal simply sat in the buffer,
/// waiting for a newline that a keystroke never sends. The keys were being
/// forwarded correctly the whole time and were never delivered.
- (void)setLineDisciplineRaw:(BOOL)raw {
    if (self.master < 0) return;
    struct termios settings;
    if (tcgetattr(self.master, &settings) != 0) return;
    if (raw) {
        if (!_haveSavedLineDiscipline) {
            _savedLineDiscipline = settings;
            _haveSavedLineDiscipline = YES;
        }
        cfmakeraw(&settings);
        tcsetattr(self.master, TCSANOW, &settings);
    } else if (_haveSavedLineDiscipline) {
        tcsetattr(self.master, TCSANOW, &_savedLineDiscipline);
        _haveSavedLineDiscipline = NO;
    }
}

- (BOOL)rawInputActive {
    return self.running && self.onAlternateScreen;
}

- (BOOL)sendKeyEvent:(NSEvent *)event {
    if (!self.rawInputActive || event.type != NSEventTypeKeyDown) return NO;

    // Command belongs to the Mac, even while a terminal program is running:
    // copy, paste and the app's menu shortcuts must not become server input.
    if ((event.modifierFlags & NSEventModifierFlagCommand) != 0) return NO;

    // These keys are terminal operations rather than text. In particular,
    // arrows depend on the mode selected by the running program, so keep that
    // choice in sendKey: instead of teaching the entry box terminal modes.
    switch (event.keyCode) {
        case 126: [self sendKey:SlopNetKeyUp];     return YES;
        case 125: [self sendKey:SlopNetKeyDown];   return YES;
        case 124: [self sendKey:SlopNetKeyRight];  return YES;
        case 123: [self sendKey:SlopNetKeyLeft];   return YES;
        case 53:  [self sendKey:SlopNetKeyEscape]; return YES;
        case 48:  [self sendKey:SlopNetKeyTab];    return YES;
        case 36:
        case 76:  [self sendKey:SlopNetKeyEnter];  return YES;
        default: break;
    }

    // Zellij's commands begin with Control letters. AppKit normally supplies
    // the control byte in characters, but derive it from the unmodified
    // letter deliberately: Ctrl+g is 0x07, Ctrl+a is 0x01, and so on. It does
    // not depend on the text editor deciding how or when to insert the key.
    if ((event.modifierFlags & NSEventModifierFlagControl) != 0) {
        NSString *plain = event.charactersIgnoringModifiers.lowercaseString;
        if (plain.length == 1) {
            unichar letter = [plain characterAtIndex:0];
            if (letter >= 'a' && letter <= 'z') {
                unichar control = (unichar)(letter - 'a' + 1);
                [self sendKeys:[NSString stringWithCharacters:&control length:1]];
                return YES;
            }
        }
    }

    // A full-screen program reads characters one at a time. Sending this via
    // the text view would buffer it until Return and turn a key-driven tool
    // into something visible but inert.
    NSString *characters = event.characters ?: @"";
    if (characters.length > 0) [self sendKeys:characters];
    return YES;
}

- (void)sendKeys:(NSString *)raw {
    if (!self.running || self.master < 0 || raw.length == 0) return;
    const char *bytes = raw.UTF8String;
    size_t remaining = strlen(bytes);
    while (remaining > 0) {
        ssize_t wrote = write(self.master, bytes, remaining);
        if (wrote <= 0) break;
        bytes += wrote;
        remaining -= (size_t)wrote;
    }
}

- (void)sendLine:(NSString *)line {
    if (!self.running || self.master < 0) return;
    // Carriage return, because that is what a terminal sends when somebody
    // presses Return. A program reading whole lines still receives a newline:
    // the terminal itself translates one to the other. A program reading keys
    // as they come — anything drawing its own interface — is watching for the
    // carriage return specifically, and a newline is not it. Sending a newline
    // meant a message typed to Antigravity appeared in its input box and was
    // never submitted, so it sat there and no reply ever came.
    NSString *withReturn = [line stringByAppendingString:@"\r"];
    const char *bytes = withReturn.UTF8String;
    size_t remaining = strlen(bytes);
    while (remaining > 0) {
        ssize_t wrote = write(self.master, bytes, remaining);
        if (wrote <= 0) break;
        bytes += wrote;
        remaining -= (size_t)wrote;
    }
}

- (void)sendSecret:(NSString *)secret {
    // Deliberately the same wire as sendLine:. The difference that matters is
    // at the other end — this came from a masked field, is not echoed by the
    // terminal, and no copy is kept here.
    [self sendLine:secret ?: @""];
}

- (void)stopPressed:(id)sender { [self stop]; }

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self
                                                  name:NSViewBoundsDidChangeNotification
                                                object:nil];
}

- (void)stop {
    if (!self.running) return;
    [self note:@"\n(asking it to stop…)"];
    kill(self.child, SIGTERM);
    pid_t stopping = self.child;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (self.child == stopping) kill(stopping, SIGKILL);
    });
}

@end
