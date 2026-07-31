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
static NSString *const kCellFill = @"SlopNetCellFill";

/// How big a badge is drawn next to the text. Chosen by rendering it.
static const CGFloat kBadgeScale = 0.85;

@interface SlopNetTextView : NSTextView
@end

@implementation SlopNetTextView

- (void)drawViewBackgroundInRect:(NSRect)rect {
    [super drawViewBackgroundInRect:rect];
    NSLayoutManager *layout = self.layoutManager;
    NSTextContainer *container = self.textContainer;
    if (layout == nil || container == nil) return;

    NSRange visible = [layout glyphRangeForBoundingRect:rect inTextContainer:container];
    NSRange characters = [layout characterRangeForGlyphRange:visible actualGlyphRange:NULL];
    NSPoint origin = self.textContainerOrigin;

    [self.textStorage enumerateAttribute:kCellFill inRange:characters
                                 options:0
                              usingBlock:^(id value, NSRange range, BOOL *stop) {
        (void)stop;
        NSColor *fill = value;
        if (fill == nil) return;
        NSRange glyphs = [layout glyphRangeForCharacterRange:range
                                       actualCharacterRange:NULL];
        // Per line fragment, so a run that wraps is filled on every line it
        // occupies, and each piece takes that line box's full height.
        NSUInteger index = glyphs.location;
        while (index < NSMaxRange(glyphs)) {
            NSRange lineRange;
            NSRect fragment = [layout lineFragmentRectForGlyphAtIndex:index
                                                       effectiveRange:&lineRange];
            NSRange piece = NSIntersectionRange(glyphs, lineRange);
            if (piece.length == 0) break;
            NSRect span = [layout boundingRectForGlyphRange:piece inTextContainer:container];
            NSRect cell = NSMakeRect(span.origin.x + origin.x,
                                     fragment.origin.y + origin.y,
                                     span.size.width,
                                     fragment.size.height);
            [fill set];
            NSRectFill(cell);
            index = NSMaxRange(lineRange);
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
@property(nonatomic, strong) NSMutableString *collected;
/// One fixed line box for every row, so painted backgrounds tile vertically.
@property(nonatomic, strong) NSParagraphStyle *cellParagraph;
/// Whether the view should stay pinned to the newest output. Set false the
/// moment somebody scrolls up, true again when they come back to the bottom.
@property(nonatomic, assign) BOOL followTail;
/// A redraw is already queued, so a chatty program cannot queue a thousand.
@property(nonatomic, assign) BOOL redrawQueued;
/// A redraw is already scheduled for the next turn of the run loop.
@property(nonatomic, assign) BOOL redrawScheduled;
/// Follow the newest line, the way a terminal does — until somebody scrolls
/// up to read something, and again once they come back to the bottom.
@property(nonatomic, assign) BOOL followingTail;
@end

/// Keep the console light even during a long build.
static const NSUInteger kMaxLines = 4000;

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

@implementation SlopNetConsole

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

    _output = [[SlopNetTextView alloc] initWithFrame:NSZeroRect];
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
    [self addSubview:_status];

    _stopButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    _stopButton.title = @"Stop";
    _stopButton.bezelStyle = NSBezelStyleRounded;
    _stopButton.target = self;
    _stopButton.action = @selector(stopPressed:);
    _stopButton.enabled = NO;
    _stopButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_stopButton];

    [NSLayoutConstraint activateConstraints:@[
        [_scroller.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_scroller.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scroller.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_status.topAnchor constraintEqualToAnchor:_scroller.bottomAnchor constant:6],
        [_status.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:2],
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

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self resizeChildTerminal];
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
        CGFloat height = ceil([self.output.layoutManager defaultLineHeightForFont:font]);
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

- (NSMutableAttributedString *)currentLine {
    while (self.lines.count <= self.row) {
        [self.lines addObject:[[NSMutableAttributedString alloc] init]];
    }
    return self.lines[self.row];
}

/// Write text at the cursor, overwriting what is already there — this is
/// what makes a progress line update in place instead of repeating. The
/// replaced span takes the current pen; untouched spans keep theirs.
/// Sit a colour badge inside the same box as the text beside it.
///
/// The badges are sbix bitmaps whose drawn box is taller than the letters they
/// sit next to. A run's background is painted to that box, so a badge pushed a
/// tab of colour up above the panel fill and the logo was not level with its
/// own background. A baseline offset cannot help: it moves the glyph and its
/// box together, so the tab travels with it.
///
/// The badge is therefore drawn small enough that its box fits the line. The
/// amount is measured from the glyph itself rather than guessed, so it holds
/// at any type size and on any screen; a fixed fudge factor looked right in
/// one render and wrong on the operator's machine. Shrinking costs advance,
/// which would pull every column left, so the exact difference is added back
/// as kerning and the grid does not move.
- (void)settleBadgesIn:(NSMutableAttributedString *)piece {
    NSFont *font = self.output.font;
    if (font == nil) return;
    NSFont *smaller = [NSFont fontWithName:font.fontName
                                      size:font.pointSize * kBadgeScale];
    if (smaller == nil) return;
    NSString *text = piece.string;

    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        BOOL badge = (c >= 0xE000 && c <= 0xE7FF) ||     // provider logos + twins
                     (c >= 0xE900 && c <= 0xEC45);       // action frames + twins
        if (!badge) continue;

        // Applied without asking the glyph how tall it is. sbix bitmaps report
        // their vector bounds, which are empty, so a measured version of this
        // scaled nothing at all and looked identical at every setting.
        NSRange one = NSMakeRange(i, 1);
        NSString *single = [text substringWithRange:one];
        CGFloat wanted = [single sizeWithAttributes:@{NSFontAttributeName: font}].width;
        CGFloat drawn  = [single sizeWithAttributes:@{NSFontAttributeName: smaller}].width;
        [piece addAttribute:NSFontAttributeName value:smaller range:one];
        if (wanted > drawn) {
            [piece addAttribute:NSKernAttributeName value:@(wanted - drawn) range:one];
        }
    }
}

- (void)putText:(NSString *)text {
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

- (void)newline {
    self.row++;
    self.column = 0;
    [self currentLine];
    if (self.lines.count > kMaxLines) {
        NSUInteger drop = self.lines.count - kMaxLines;
        [self.lines removeObjectsInRange:NSMakeRange(0, drop)];
        self.row = self.row > drop ? self.row - drop : 0;
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
                    final = f;
                    break;
                }
                if (prefix != 0) continue;
                NSInteger value = parameters.length ? [parameters intValue] : 1;
                switch (final) {
                    case 'm':                              // colours and weight
                        SlopNetApplySGR(self.ink, parameters);
                        break;
                    case 'A':                              // cursor up
                        self.row = (self.row >= (NSUInteger)value) ? self.row - value : 0;
                        break;
                    case 'B':                              // cursor down
                        self.row += value;
                        [self currentLine];
                        break;
                    case 'C': self.column += value; break; // right
                    case 'D':                              // left
                        self.column = (self.column >= (NSUInteger)value)
                            ? self.column - value : 0;
                        break;
                    case 'G':                              // column
                        self.column = value > 0 ? (NSUInteger)(value - 1) : 0;
                        break;
                    case 'H': case 'f':                    // home
                        self.row = 0; self.column = 0;
                        break;
                    case 'K': {                            // erase in line
                        NSMutableAttributedString *line = [self currentLine];
                        if (self.column < line.length) {
                            [line deleteCharactersInRange:
                                NSMakeRange(self.column, line.length - self.column)];
                        }
                        break;
                    }
                    case 'J':                              // erase screen
                        if (value == 2 || parameters.length == 0) {
                            [self.lines removeAllObjects];
                            [self.lines addObject:[[NSMutableAttributedString alloc] init]];
                            self.row = 0; self.column = 0;
                        }
                        break;
                    default: break;
                }
            } else if (i < n && [raw characterAtIndex:i] == ']') {
                while (i < n && [raw characterAtIndex:i] != 0x07) i++;   // title
                if (i < n) i++;
            } else if (i < n) {
                i++;
            }
            continue;
        }

        if (c == '\n') { [self newline]; i++; continue; }
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

- (void)noticeASignInPage {
    if (!self.running) return;
    NSString *recent = @"";
    NSUInteger from = self.lines.count > 12 ? self.lines.count - 12 : 0;
    for (NSUInteger i = from; i < self.lines.count; i++) {
        recent = [recent stringByAppendingFormat:@"%@\n", self.lines[i].string];
    }
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
    NSTextCheckingResult *found =
        [link firstMatchInString:recent options:0 range:NSMakeRange(0, recent.length)];
    if (found == nil) return;
    NSString *address = [recent substringWithRange:found.range];
    // Trim trailing punctuation a sentence may have left on the end.
    while (address.length > 0 &&
           [@".,);:" rangeOfString:[address substringFromIndex:address.length - 1]].location != NSNotFound) {
        address = [address substringToIndex:address.length - 1];
    }
    NSURL *page = [NSURL URLWithString:address];
    if (page == nil) return;

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
                || [lower containsString:@"verification"] || [lower containsString:@"verify"]
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
    BOOL sameAddress = [address isEqualToString:self.announcedSignIn];
    if (sameAddress) {
        if (code == nil) return;                                  // nothing new
        if ([code isEqualToString:self.announcedCode]) return;    // already said
    }
    self.announcedSignIn = address;
    self.announcedCode = code;

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

- (NSString *)textForTesting {
    [self redraw];
    return self.output.textStorage.string;
}

- (void)note:(NSString *)text {
    [self consume:[NSString stringWithFormat:@"%@\n", text]];
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
    [self setNeedsRedrawSoon];
    return token;
}

- (BOOL)replaceLinesFromToken:(NSInteger)token with:(NSString *)text {
    NSInteger start = token - self.droppedLines;
    if (start < 0) return NO;                       // scrolled out of the buffer
    NSArray<NSMutableAttributedString *> *block = [self renderBlock:text];
    if ((NSUInteger)start + block.count > self.lines.count) return NO;
    for (NSUInteger index = 0; index < block.count; index++) {
        self.lines[(NSUInteger)start + index] = block[index];
    }
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

    // Tell the child the real width of the field, so its own panels and
    // progress lines wrap where the window actually ends.
    struct winsize size = {0};
    size.ws_col = (unsigned short)self.columns;
    size.ws_row = (unsigned short)self.visibleRows;

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
        NSString *chunk = [[NSString alloc] initWithBytes:buffer
                                                   length:(NSUInteger)got
                                                 encoding:NSUTF8StringEncoding];
        if (chunk == nil) {
            chunk = [[NSString alloc] initWithBytes:buffer
                                             length:(NSUInteger)got
                                           encoding:NSISOLatin1StringEncoding];
        }
        if (chunk.length == 0) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (strongSelf == nil) return;
            [strongSelf consume:chunk];
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
            @"Stopped with a problem (code %d). The last lines above say why.", status]
                      glyph:nil
                       tint:nil];
        [self note:[NSString stringWithFormat:@"\n— stopped, code %d —", status]];
    }
    // Draw the last of it now rather than on a queued tick, so the final
    // lines — which are the ones saying what to do next — are on screen the
    // instant the program stops.
    [self redraw];
    if ([self.delegate respondsToSelector:@selector(console:finishedWithStatus:)]) {
        [self.delegate console:self finishedWithStatus:status];
    }
}

- (void)sendLine:(NSString *)line {
    if (!self.running || self.master < 0) return;
    NSString *withReturn = [line stringByAppendingString:@"\n"];
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
