#import "SlopNetBrand.h"
#import <CoreText/CoreText.h>
#import <QuartzCore/QuartzCore.h>

// The bundled colour face. Built by packaging/terminal-visuals/scripts
// (build_iconfont.py → patch_font.py → build_colorfont.py): Menlo plus a
// full-colour sbix bitmap per provider logo. Menlo derivatives may ship
// inside this local app but must never be published as a standalone
// download — see packaging/terminal-visuals/README.md.
static NSString *const kColorFontFile = @"Menlo-StormCode-Color";
static NSString *const kColorFontPSName = @"Menlo-RegularStormCodeColor";

// Each provider: id, recognised display name, base PUA codepoint in the
// colour font, a plain-Unicode fallback mark, and the brand's own colours.
// Codepoints are append-only and never renumbered (they are baked into built
// fonts). The colour font also carries a two-cell-wide twin of every badge at
// codepoint + 0x200; the app uses that one, because a single Menlo cell is
// far too narrow for a logo at text size.
//
// panel/text/mark/tint come from runtime-modules/app.py's BRAND table:
//   panel — the surface the brand presents itself on
//   text  — readable text inside that surface
//   mark  — the logo's own colour when it differs from the text (nil = text)
//   tint  — a label colour tuned to be readable on the BLACK chrome, which is
//           not the same problem as text-on-panel and so not the same value
//
// IMPORTANT: `panel` must stay in step with the bg each badge bitmap was
// rasterised against in scripts/build_colorfont.py, because that colour is
// baked into the PNG. Changing one without rebuilding the font puts a badge
// on a mismatched square.
typedef struct {
    __unsafe_unretained NSString *pid;
    __unsafe_unretained NSString *display;
    unichar codepoint;
    __unsafe_unretained NSString *mark;
    uint32_t panel;
    uint32_t text;
    uint32_t markInk;      // 0 == use text
    uint32_t tint;
} SlopNetBrandEntry;

static const SlopNetBrandEntry kBrands[] = {
    { @"anthropic",   @"Claude",       0xE000, @"✳", 0xB15C40, 0xFFFFFF, 0,        0xD97757 },
    // Antigravity keeps its single mark and a plain panel: no multicolour
    // per-letter Google wordmark (operator decision, 2026-07-30).
    { @"google",      @"Antigravity",  0xE001, @"✦", 0xFFFFFF, 0x202124, 0,        0x4285F4 },
    { @"openai",      @"ChatGPT",      0xE002, @"❋", 0x343541, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF },
    { @"xai",         @"Grok",         0xE003, @"⦸", 0x000000, 0xFFFFFF, 0,        0xBDBDBD },
    { @"moonshot",    @"Moonshot",     0xE004, @"☾", 0x1D1D1F, 0xFFFFFF, 0,        0xE2E3EA },
    { @"zai",         @"GLM",          0xE005, @"⧫", 0x141618, 0xFFFFFF, 0,        0x8DB3FF },
    { @"minimax",     @"MiniMax",      0xE006, @"⬢", 0x181E25, 0xFFFFFF, 0,        0xE34872 },
    { @"mistral",     @"Mistral",      0xE007, @"▤", 0xFFFFFF, 0xB53600, 0,        0xFFAF01 },
    { @"alibaba",     @"Qwen",         0xE008, @"◈", 0x082DFF, 0xFFFFFF, 0xFFFFFF, 0x8DB3FF },
    { @"aihorde",     @"AI Horde",     0xE009, @"⚔", 0xFFAA00, 0x000000, 0,        0x56B4F8 },
    { @"cerebras",    @"Cerebras",     0xE00A, @"⬣", 0xF7F5F2, 0x000000, 0,        0xF15A29 },
    { @"cohere",      @"Cohere",       0xE00B, @"◐", 0xF0EBE1, 0x1D4045, 0,        0x7FD1B9 },
    { @"deepseek",    @"DeepSeek",     0xE00C, @"▲", 0x212327, 0xFFFFFF, 0,        0x6E88FF },
    { @"huggingface", @"Hugging Face", 0xE00E, @"☻", 0x0B0F19, 0xFFFFFF, 0,        0xFFD21E },
    { @"ibm",         @"IBM",          0xE00F, @"☰", 0x1F70C1, 0xFFFFFF, 0,        0x75B9FF },
    { @"internlm",    @"InternLM",     0xE010, @"◧", 0x858599, 0x000000, 0x000000, 0x858599 },
    { @"meta",        @"Meta",         0xE011, @"∞", 0x111112, 0xFFFFFF, 0,        0x2997FF },
    { @"microsoft",   @"Microsoft",    0xE012, @"⊞", 0xFFFFFF, 0x242424, 0,        0xF25022 },
    { @"nous",        @"Nous",         0xE013, @"✧", 0x000000, 0xFFFFFF, 0,        0xD8D4CF },
    { @"nvidia",      @"NVIDIA",       0xE014, @"◤", 0x76B900, 0x000000, 0,        0x8FD400 },
    { @"ollama",      @"Ollama",       0xE015, @"◍", 0xFFFFFF, 0x000000, 0,        0xE0DDD4 },
    { @"openrouter",  @"OpenRouter",   0xE016, @"⋈", 0xC8FF00, 0x000000, 0,        0xC8FF00 },
    { @"perplexity",  @"Perplexity",   0xE017, @"⌕", 0x010E17, 0xFFFFFF, 0,        0x22B8CD },
    { @"tencent",     @"Tencent",      0xE018, @"◑", 0xEAF3FA, 0x003A8C, 0,        0x4D8FFF },
    { @"together",    @"Together",     0xE019, @"⧉", 0x151532, 0xFFFFFF, 0,        0xFC6B3C },
    { @"venice",      @"Venice",       0xE01A, @"⚿", 0xF7F5ED, 0x0E2942, 0,        0x3C8FDD },
    { @"stormcode",   @"StormCode",    0xE01B, @"🌀", 0x000000, 0xFF003C, 0,        0xFF003C },
    { @"cognition",   @"Devin",        0xE01C, @"⬡", 0x001423, 0xFFFFFF, 0,        0x68D5DD },
    { @"xiaomi",      @"Xiaomi",       0xE01E, @"▣", 0xFF6900, 0x000000, 0,        0xFF6900 },
    { @"inclusionai", @"InclusionAI",  0xE01F, @"◉", 0x6D3BD1, 0xFFFFFF, 0,        0xB794F4 },
    { @"nova",        @"Nova",         0xE020, @"✶", 0x000000, 0xFFFFFF, 0,        0xE433FF },
    { @"poolside",    @"Poolside",     0xE021, @"≋", 0x22C7D9, 0x211B55, 0,        0x7B73FF },
    { @"scale",       @"Scale",        0xE022, @"▰", 0x000000, 0xFFFFFF, 0,        0xB39DDB },
    { @"stepfun",     @"StepFun",      0xE023, @"▦", 0xFFFFFF, 0x000000, 0,        0xE8E5DF },
    { @"jina",        @"Jina",         0xE024, @"⊙", 0xFFFFFF, 0x009191, 0,        0x00C2C2 },
    { @"rivescript",  @"RiveScript",   0xE025, @"❖", 0x960100, 0xFFFFFF, 0,        0xE0594A },
    { @"searxng",     @"SearXNG",      0xE026, @"⊚", 0xFFFFFF, 0x3050FF, 0,        0x7B8FFF },
    // SlopNet's local default model. The cubes carry their own green
    // gradient (#006116 → #00AB23) and are drawn on a black field, so the
    // panel is black with white text and the gradient's bright end as the
    // tint — the same shape as xai, nous and stormcode, which also present
    // on black. Panel black is what build_colorfont.py baked behind the
    // badge; the green is the artwork's own.
    // Green on black, as the operator specified. The green was already here as
    // the tint; the text itself was white, which is why the panel came out
    // reading like every other vendor.
    { @"ibm_granite", @"Granite",      0xE027, @"❐", 0x000000, 0x00AB23, 0,        0x00AB23 },
};
static const NSUInteger kBrandCount = sizeof(kBrands) / sizeof(kBrands[0]);

// Action glyph frames, from runtime-modules/action_frames.py (generated by
// scripts/build_action_frames.py). A concept maps to consecutive codepoints
// in frame order; the base codepoints carry no glyph, so a frame is only
// ever drawn through its N-cell twin at base + N*0x100.
typedef struct {
    __unsafe_unretained NSString *concept;
    unichar first;
    uint8_t frames;
} SlopNetActionEntry;

static const SlopNetActionEntry kActions[] = {
    { @"search",        0xE900, 12 },
    { @"db-research",   0xE90C, 6  },
    { @"net-research",  0xE912, 1  },
    { @"deep-research", 0xE913, 1  },
    { @"rag",           0xE914, 1  },
    { @"rerank",        0xE915, 1  },
    { @"read",          0xE916, 6  },
    { @"write",         0xE91C, 22 },
    { @"think",         0xE932, 5  },
    { @"message",       0xE937, 1  },
    { @"user-message",  0xE938, 1  },
    { @"user-press",    0xE939, 3  },
    { @"instruction",   0xE93C, 1  },
    { @"template",      0xE93D, 9  },
};
static const NSUInteger kActionCount = sizeof(kActions) / sizeof(kActions[0]);

/// Both modes cost the same columns, so a panel's edges line up whether or
/// not the colour font loaded: a badge glyph advances two cells on its own,
/// and a fallback mark is one character plus a space.
/// Three, matching show_panels.py's CELLS. Everything in the reference
/// is laid out against this width.
static const NSUInteger kMarkColumns = 3;

static NSColor *SlopNetColorFromHex(uint32_t hex) {
    return [NSColor colorWithSRGBRed:((hex >> 16) & 0xFF) / 255.0
                               green:((hex >> 8) & 0xFF) / 255.0
                                blue:(hex & 0xFF) / 255.0
                               alpha:1.0];
}

#pragma mark - ANSI helpers

static NSString *const kReset = @"\033[0m";

static NSString *SlopNetSGRForColor(NSColor *color, BOOL isBackground) {
    NSColor *srgb = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]] ?: color;
    return [NSString stringWithFormat:@"\033[%d;2;%d;%d;%dm", isBackground ? 48 : 38,
            (int)lround(srgb.redComponent * 255),
            (int)lround(srgb.greenComponent * 255),
            (int)lround(srgb.blueComponent * 255)];
}

static NSString *SlopNetInkSGR(NSColor *color) { return SlopNetSGRForColor(color, NO); }
static NSString *SlopNetFieldSGR(NSColor *color) { return SlopNetSGRForColor(color, YES); }

static NSString *SlopNetRepeat(NSString *unit, NSInteger times) {
    if (times <= 0) return @"";
    return [@"" stringByPaddingToLength:(NSUInteger)times * unit.length
                            withString:unit startingAtIndex:0];
}

#pragma mark - panel chrome parts
//
// Three small views and one button. They exist so Settings and Tools can look
// like the console without either of them hand-rolling a theme, and so there
// is exactly one place to change when the look moves again.

/// A plain filled rectangle. NSBox's separator cannot be coloured, which is
/// why the rules in these panels are their own view.
///
/// The fill is a layer colour rather than a `drawRect:`. Custom `drawRect:`
/// views in this hierarchy were not being asked to draw at all, and an
/// undrawn view shows its uninitialised backing store — a flat red sheet over
/// the whole panel. A layer fill always renders.
@interface SlopNetRuleView : NSView
@property(nonatomic, strong) NSColor *fill;
@end

@implementation SlopNetRuleView
- (void)setFill:(NSColor *)fill {
    _fill = fill;
    self.wantsLayer = YES;
    self.layer.backgroundColor = (fill ?: NSColor.grayColor).CGColor;
}
@end

/// The void field a panel sits on: black, a crimson bloom bleeding down from
/// the top edge, CRT scanlines, and a targeting bracket in each corner. All
/// of it is faint on purpose — it should read at a glance and disappear when
/// you are actually reading the words.
///
/// Built entirely from layers, deliberately. A custom `drawRect:` in this
/// hierarchy was never called, and a view that is never drawn shows its
/// uninitialised backing store — which is how a panel ends up as a flat red
/// sheet with the controls faintly visible underneath. Layers always render.
@interface SlopNetBackdropView : NSView
@property(nonatomic, strong) CAGradientLayer *bloom;
@property(nonatomic, strong) CAReplicatorLayer *scanlines;
@property(nonatomic, strong) CALayer *scanline;
@property(nonatomic, strong) CAShapeLayer *brackets;
@end

@implementation SlopNetBackdropView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self == nil) return nil;
    self.wantsLayer = YES;
    [self buildLayers];
    return self;
}

/// AppKit can hand a view a fresh backing layer when it joins a layer-backed
/// hierarchy, throwing away anything configured on the old one. Everything is
/// therefore (re)applied from `updateLayer`, which runs on every display pass.
- (BOOL)wantsUpdateLayer { return YES; }

- (void)updateLayer {
    [self buildLayers];
    self.layer.backgroundColor = [SlopNetBrand voidColor].CGColor;
    [self layout];
}

- (void)buildLayers {
    if (self.layer == nil || self.bloom.superlayer == self.layer) return;

    NSColor *crimson = [SlopNetBrand crimsonColor];

    // Crimson bloom bleeding down from the top, as if the panel is lit by the
    // console next to it.
    _bloom = [CAGradientLayer layer];
    _bloom.colors = @[(__bridge id)[crimson colorWithAlphaComponent:0.16].CGColor,
                      (__bridge id)[crimson colorWithAlphaComponent:0.0].CGColor];
    // Unit coordinates on a macOS layer put (0,0) at the bottom left, so the
    // bright end of the bloom is y=1.
    _bloom.startPoint = CGPointMake(0.5, 1.0);
    _bloom.endPoint = CGPointMake(0.5, 0.0);
    [self.layer addSublayer:_bloom];

    // Scanlines: one point lit, two dark. Enough to say CRT, not enough to
    // fight the type sitting on top of them.
    _scanline = [CALayer layer];
    _scanline.backgroundColor =
        [NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0.022].CGColor;
    _scanlines = [CAReplicatorLayer layer];
    _scanlines.instanceTransform = CATransform3DMakeTranslation(0, 3, 0);
    [_scanlines addSublayer:_scanline];
    [self.layer addSublayer:_scanlines];

    // HUD corner brackets.
    _brackets = [CAShapeLayer layer];
    _brackets.fillColor = NSColor.clearColor.CGColor;
    _brackets.strokeColor = [crimson colorWithAlphaComponent:0.30].CGColor;
    _brackets.lineWidth = 1.5;
    [self.layer addSublayer:_brackets];
}

/// Sublayers do not follow the view's size on their own, and the bracket path
/// has to be rebuilt at every size.
- (void)layout {
    [super layout];
    NSRect bounds = self.bounds;
    if (NSIsEmptyRect(bounds)) return;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    CGFloat bloomHeight = NSHeight(bounds) * 0.45;
    self.bloom.frame = CGRectMake(0, NSHeight(bounds) - bloomHeight,
                                  NSWidth(bounds), bloomHeight);
    self.scanlines.frame = bounds;
    self.scanline.frame = CGRectMake(0, 0, NSWidth(bounds), 1.0);
    self.scanlines.instanceCount = (NSInteger)ceil(NSHeight(bounds) / 3.0);

    const CGFloat arm = 16.0, inset = 10.0;
    CGRect frame = CGRectInset(bounds, inset, inset);
    CGMutablePathRef path = CGPathCreateMutable();
    const CGPoint corners[4] = {
        { CGRectGetMinX(frame), CGRectGetMinY(frame) },
        { CGRectGetMaxX(frame), CGRectGetMinY(frame) },
        { CGRectGetMinX(frame), CGRectGetMaxY(frame) },
        { CGRectGetMaxX(frame), CGRectGetMaxY(frame) },
    };
    const CGFloat dx[4] = { 1, -1, 1, -1 };
    const CGFloat dy[4] = { 1, 1, -1, -1 };
    for (int i = 0; i < 4; i++) {
        CGPathMoveToPoint(path, NULL, corners[i].x + dx[i] * arm, corners[i].y);
        CGPathAddLineToPoint(path, NULL, corners[i].x, corners[i].y);
        CGPathAddLineToPoint(path, NULL, corners[i].x, corners[i].y + dy[i] * arm);
    }
    self.brackets.frame = bounds;
    self.brackets.path = path;
    CGPathRelease(path);

    [CATransaction commit];
}

@end

/// A button that looks like a control on a terminal, not a control in a
/// preferences pane: void fill, crimson edge, monospaced title, crimson wash
/// under the pointer. Drawn on its own layer so there is no bezel to fight.
@interface SlopNetPanelButton : NSButton
@property(nonatomic, assign) SlopNetButtonRole role;
@property(nonatomic, assign) BOOL hovering;
@property(nonatomic, strong) NSTrackingArea *hoverArea;
/// Kept so the icon can be re-tinted whenever the role or state changes.
@property(nonatomic, copy) NSString *symbolName;
@end

@implementation SlopNetPanelButton

/// Remove only our own tracking area, never the whole set. Clearing every
/// area here also clears the ones AppKit installs for the button, and putting
/// one back re-triggers this method — a loop that starves the window of
/// drawing and leaves it showing an unpainted backing store.
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.hoverArea != nil) {
        [self removeTrackingArea:self.hoverArea];
    }
    self.hoverArea = [[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp |
                      NSTrackingInVisibleRect)
               owner:self
            userInfo:nil];
    [self addTrackingArea:self.hoverArea];
}

- (void)mouseEntered:(NSEvent *)event { (void)event; self.hovering = YES; [self refreshChrome]; }
- (void)mouseExited:(NSEvent *)event  { (void)event; self.hovering = NO;  [self refreshChrome]; }

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [self refreshChrome];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    [self refreshChrome];
}

/// The title is drawn from an attributed string, so setting the plain title
/// has to rebuild it — otherwise `button.title = @"Hide"` silently keeps the
/// old words on screen.
- (void)setTitle:(NSString *)title {
    [super setTitle:title];
    [self refreshChrome];
}

/// A disabled control must still be legible — somebody has to be able to read
/// what they are not allowed to press yet, and why.
- (void)refreshChrome {
    NSColor *crimson = [SlopNetBrand crimsonColor];
    NSColor *title, *border, *fill;
    CGFloat width = 1.0;

    if (!self.isEnabled) {
        title  = [[SlopNetBrand ghostColor] colorWithAlphaComponent:0.85];
        border = [crimson colorWithAlphaComponent:0.14];
        fill   = [NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0.02];
    } else {
        switch (self.role) {
            case SlopNetButtonRolePrimary:
                title  = [NSColor colorWithSRGBRed:1.0 green:0.42 blue:0.52 alpha:1.0];
                border = [crimson colorWithAlphaComponent:0.95];
                fill   = [crimson colorWithAlphaComponent:0.20];
                width  = 1.5;
                break;
            case SlopNetButtonRoleDanger:
                title  = crimson;
                border = [crimson colorWithAlphaComponent:0.55];
                fill   = [crimson colorWithAlphaComponent:0.06];
                break;
            case SlopNetButtonRoleNormal:
            default:
                title  = [SlopNetBrand inkColor];
                border = [crimson colorWithAlphaComponent:0.30];
                fill   = [NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0.035];
                break;
        }
        if (self.isHighlighted) {
            fill   = [crimson colorWithAlphaComponent:0.38];
            border = crimson;
        } else if (self.hovering) {
            fill   = [crimson colorWithAlphaComponent:0.16];
            border = [crimson colorWithAlphaComponent:0.75];
        }
    }

    self.layer.backgroundColor = fill.CGColor;
    self.layer.borderColor = border.CGColor;
    self.layer.borderWidth = width;

    // The symbol is a template image, so tinting it is how it takes the same
    // colour as the words next to it.
    if (self.symbolName.length > 0) self.contentTintColor = title;

    // Follow whatever alignment the caller set — the sidebar rows read as
    // navigation and want their words on the left, not centred.
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = self.alignment;
    self.attributedTitle = [[NSAttributedString alloc]
        initWithString:self.title
            attributes:@{ NSFontAttributeName: [NSFont monospacedSystemFontOfSize:11.5
                                                                           weight:NSFontWeightMedium],
                          NSForegroundColorAttributeName: title,
                          NSKernAttributeName: @(0.3),
                          NSParagraphStyleAttributeName: paragraph }];
}

@end

@implementation SlopNetBrand

+ (const SlopNetBrandEntry *)entryForProvider:(NSString *)providerId {
    for (NSUInteger i = 0; i < kBrandCount; i++) {
        if ([kBrands[i].pid isEqualToString:providerId]) return &kBrands[i];
    }
    return NULL;
}

+ (const SlopNetActionEntry *)entryForAction:(NSString *)concept {
    for (NSUInteger i = 0; i < kActionCount; i++) {
        if ([kActions[i].concept isEqualToString:concept]) return &kActions[i];
    }
    return NULL;
}

#pragma mark - the StormCode palette

+ (NSColor *)voidColor    { return SlopNetColorFromHex(0x000000); }
+ (NSColor *)crimsonColor { return SlopNetColorFromHex(0xFF003C); }
+ (NSColor *)inkColor     { return SlopNetColorFromHex(0xE8E8E8); }
+ (NSColor *)ghostColor   { return SlopNetColorFromHex(0x666666); }
// Host surface behind chrome glass — near-black with a red lift so crimson
// glass has something to refract. Never used as the console cell field.
+ (NSColor *)chromeFieldColor {
    return [NSColor colorWithSRGBRed:0.035 green:0.012 blue:0.018 alpha:1.0];
}
// Matrix-adjacent shell: StormCode crimson through the liquid material.
//
// Liquid Glass *lightens* whatever it is tinted with, so #FF003C at 0.42 came
// out as flat bubblegum pink — the opposite of the Terminator HUD it was
// meant to be. That red is a light emitting on black; as a surface fill it
// wants to be dark. A deep oxblood at low alpha keeps the hue and lets the
// black underneath stay black, so crimson text still reads as the bright
// thing on the panel rather than competing with its own background.
+ (NSColor *)chromeTintColor {
    return [NSColor colorWithSRGBRed:0.42 green:0.02 blue:0.09 alpha:0.16];
}
+ (NSColor *)phosphorColor { return SlopNetColorFromHex(0x00AB23); }

#pragma mark - window chrome

+ (BOOL)liquidGlassAvailable {
    if (@available(macOS 26.0, *)) {
        return NSClassFromString(@"NSGlassEffectView") != Nil;
    }
    return NO;
}

/// Dark shell for the window, and no system title bar across the top.
///
/// The content view runs the full height of the window and the title bar is
/// transparent with its title hidden, so the close/minimise/zoom buttons sit
/// on SlopNet's own surface instead of in a grey system strip. Nothing here
/// touches the console: this is the window, not its contents.
///
/// Callers must keep interactive controls out of the top ~28 points, which is
/// still the window's drag region even when it is transparent.
+ (void)applyTerminalChromeToWindow:(NSWindow *)window {
    if (window == nil) return;
    window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    window.backgroundColor = [self chromeFieldColor];
    window.styleMask |= NSWindowStyleMaskFullSizeContentView;
    window.titlebarAppearsTransparent = YES;
    window.titleVisibility = NSWindowTitleHidden;
}

/// How far down a window's content must start to clear the title bar's drag
/// region. Measured from the window rather than assumed, so it stays right if
/// the system ever changes the height.
+ (CGFloat)titleBarInsetForWindow:(NSWindow *)window {
    if (window == nil) return 28.0;
    CGFloat height = NSHeight([window contentRectForFrameRect:window.frame]) -
                     NSHeight(window.contentLayoutRect);
    return height > 0 ? height : 28.0;
}

/// Glass around chrome (sidebar, composer). Never wrap SlopNetConsole or its
/// holder — the PTY field must stay an opaque black rectangle.
+ (NSView *)glassPanelWrapping:(NSView *)content
                  cornerRadius:(CGFloat)radius
                     tintColor:(NSColor *)tint {
    if (content == nil) return [[NSView alloc] initWithFrame:NSZeroRect];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    const CGFloat inset = 12.0;

    // The padding lives in a plain view wrapped around the content, not in
    // constraints against the glass. NSGlassEffectView pins whatever is handed
    // to `contentView` to its own bounds, so constraints written against the
    // glass were quietly doing nothing and the sidebar's rows ended up hard
    // against the window edge.
    NSView *padded = [[NSView alloc] initWithFrame:NSZeroRect];
    padded.translatesAutoresizingMaskIntoConstraints = NO;
    [padded addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:padded.topAnchor constant:inset],
        [content.leadingAnchor constraintEqualToAnchor:padded.leadingAnchor constant:inset],
        [content.trailingAnchor constraintEqualToAnchor:padded.trailingAnchor constant:-inset],
        [content.bottomAnchor constraintEqualToAnchor:padded.bottomAnchor constant:-inset],
    ]];

    if (@available(macOS 26.0, *)) {
        if ([self liquidGlassAvailable]) {
            NSGlassEffectView *glass = [[NSGlassEffectView alloc] initWithFrame:NSZeroRect];
            glass.translatesAutoresizingMaskIntoConstraints = NO;
            glass.cornerRadius = radius;
            glass.tintColor = tint ?: [self chromeTintColor];
            glass.style = NSGlassEffectViewStyleRegular;
            glass.contentView = padded;
            // Let a split-view column stretch the panel; do not hug content
            // height so hard that the sidebar collapses.
            [glass setContentHuggingPriority:1
                              forOrientation:NSLayoutConstraintOrientationVertical];
            [glass setContentCompressionResistancePriority:1
                                            forOrientation:NSLayoutConstraintOrientationVertical];
            return glass;
        }
    }

    // Fallback when Liquid Glass is not available: dark frost + crimson edge.
    NSVisualEffectView *frost = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    frost.translatesAutoresizingMaskIntoConstraints = NO;
    frost.material = NSVisualEffectMaterialHUDWindow;
    frost.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    frost.state = NSVisualEffectStateActive;
    frost.wantsLayer = YES;
    frost.layer.cornerRadius = radius;
    frost.layer.masksToBounds = YES;
    frost.layer.borderWidth = 1.0;
    frost.layer.borderColor = [[self crimsonColor] colorWithAlphaComponent:0.45].CGColor;
    // `padded` already carries the inset, so this only has to fill the frost.
    [frost addSubview:padded];
    [NSLayoutConstraint activateConstraints:@[
        [padded.topAnchor constraintEqualToAnchor:frost.topAnchor],
        [padded.leadingAnchor constraintEqualToAnchor:frost.leadingAnchor],
        [padded.trailingAnchor constraintEqualToAnchor:frost.trailingAnchor],
        [padded.bottomAnchor constraintEqualToAnchor:frost.bottomAnchor],
    ]];
    [frost setContentHuggingPriority:1
                      forOrientation:NSLayoutConstraintOrientationVertical];
    [frost setContentCompressionResistancePriority:1
                                    forOrientation:NSLayoutConstraintOrientationVertical];
    return frost;
}

+ (void)styleChromeButton:(NSButton *)button {
    if (button == nil) return;
    if (@available(macOS 26.0, *)) {
        button.bezelStyle = NSBezelStyleGlass;
        button.bezelColor = [self chromeTintColor];
    } else {
        button.bezelStyle = NSBezelStyleRounded;
    }
    button.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightMedium];
    button.contentTintColor = [self inkColor];
}

+ (void)styleChromeCaption:(NSTextField *)label {
    if (label == nil) return;
    label.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightSemibold];
    label.textColor = [[self crimsonColor] colorWithAlphaComponent:0.85];
}

#pragma mark - panel chrome

+ (NSColor *)okColor    { return [self phosphorColor]; }
+ (NSColor *)warnColor  { return [self crimsonColor]; }
+ (NSColor *)quietColor { return [self ghostColor]; }

+ (void)applyPanelChromeToWindow:(NSWindow *)window {
    if (window == nil) return;
    window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
}

+ (NSView *)panelBackdrop {
    SlopNetBackdropView *backdrop = [[SlopNetBackdropView alloc] initWithFrame:NSZeroRect];
    backdrop.translatesAutoresizingMaskIntoConstraints = NO;
    return backdrop;
}

+ (NSView *)hairline {
    SlopNetRuleView *rule = [[SlopNetRuleView alloc] initWithFrame:NSZeroRect];
    rule.fill = [[self crimsonColor] colorWithAlphaComponent:0.28];
    rule.translatesAutoresizingMaskIntoConstraints = NO;
    [rule.heightAnchor constraintEqualToConstant:1].active = YES;
    return rule;
}

+ (NSView *)sectionHeaderWithTitle:(NSString *)title {
    // Reads as `▬ YOUR SERVER ──────────`: the same three beats headerANSI:
    // draws inside the console — a solid lead-in, the name, then a rule that
    // runs out to the edge.
    SlopNetRuleView *lead = [[SlopNetRuleView alloc] initWithFrame:NSZeroRect];
    lead.fill = [self crimsonColor];
    lead.translatesAutoresizingMaskIntoConstraints = NO;
    [lead.widthAnchor constraintEqualToConstant:18].active = YES;
    [lead.heightAnchor constraintEqualToConstant:3].active = YES;

    NSTextField *label = [NSTextField labelWithString:title.uppercaseString];
    label.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightBold];
    label.textColor = [self crimsonColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.attributedStringValue = [[NSAttributedString alloc]
        initWithString:title.uppercaseString
            attributes:@{ NSFontAttributeName: label.font,
                          NSForegroundColorAttributeName: [self crimsonColor],
                          NSKernAttributeName: @(1.6) }];

    SlopNetRuleView *trail = [[SlopNetRuleView alloc] initWithFrame:NSZeroRect];
    trail.fill = [[self crimsonColor] colorWithAlphaComponent:0.45];
    trail.translatesAutoresizingMaskIntoConstraints = NO;
    [trail.heightAnchor constraintEqualToConstant:1].active = YES;
    // The rule is the only part that may stretch; the words must not.
    [trail setContentHuggingPriority:NSLayoutPriorityDefaultLow - 1
                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    [label setContentHuggingPriority:NSLayoutPriorityRequired
                      forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *row = [NSStackView stackViewWithViews:@[lead, label, trail]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 9;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    return row;
}

+ (void)stylePanelLabel:(NSTextField *)label size:(CGFloat)size {
    if (label == nil) return;
    label.font = [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular];
    label.textColor = [self inkColor];
}

+ (void)stylePanelHelp:(NSTextField *)label {
    if (label == nil) return;
    label.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    // Brighter than SHELL_GHOST: this is the text that explains the app to a
    // beginner, and #666666 on black is too thin to read a paragraph of.
    label.textColor = [NSColor colorWithSRGBRed:0.62 green:0.63 blue:0.65 alpha:1.0];
}

+ (void)stylePanelColumnHeading:(NSTextField *)label {
    if (label == nil) return;
    label.attributedStringValue = [[NSAttributedString alloc]
        initWithString:label.stringValue.uppercaseString
            attributes:@{ NSFontAttributeName: [NSFont monospacedSystemFontOfSize:9.5
                                                                           weight:NSFontWeightSemibold],
                          NSForegroundColorAttributeName:
                              [[self crimsonColor] colorWithAlphaComponent:0.75],
                          NSKernAttributeName: @(1.4) }];
}

+ (NSView *)panelFieldBoxWrapping:(NSTextField *)field {
    if (field == nil) return [[NSView alloc] initWithFrame:NSZeroRect];

    field.bordered = NO;
    field.bezeled = NO;
    field.drawsBackground = NO;
    field.focusRingType = NSFocusRingTypeNone;
    field.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    field.textColor = [self inkColor];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    if (field.placeholderString.length > 0) {
        field.placeholderAttributedString = [[NSAttributedString alloc]
            initWithString:field.placeholderString
                attributes:@{ NSFontAttributeName: field.font,
                              NSForegroundColorAttributeName: [self ghostColor] }];
    }

    // The box is what gives the field its padding and its edge. Doing it this
    // way rather than with a custom NSTextFieldCell keeps the field an
    // ordinary NSTextField, so callers' pointers and bindings still work.
    NSView *box = [[NSView alloc] initWithFrame:NSZeroRect];
    box.translatesAutoresizingMaskIntoConstraints = NO;
    box.wantsLayer = YES;
    box.layer.backgroundColor = [self voidColor].CGColor;
    box.layer.borderColor = [[self crimsonColor] colorWithAlphaComponent:0.40].CGColor;
    box.layer.borderWidth = 1.0;
    box.layer.cornerRadius = 3.0;
    // Without a bezel of its own, a secure field draws its AutoFill affordance
    // outside its bounds and it lands on whatever is next to it. Clip it.
    box.clipsToBounds = YES;
    [box addSubview:field];
    [NSLayoutConstraint activateConstraints:@[
        [field.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:8],
        [field.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-8],
        [field.topAnchor constraintEqualToAnchor:box.topAnchor constant:5],
        [field.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-5],
    ]];
    return box;
}

+ (NSButton *)panelButtonWithTitle:(NSString *)title
                              role:(SlopNetButtonRole)role
                            target:(id)target
                            action:(SEL)action {
    SlopNetPanelButton *button = [[SlopNetPanelButton alloc] initWithFrame:NSZeroRect];
    button.title = title ?: @"";
    button.role = role;
    button.target = target;
    button.action = action;
    button.bordered = NO;
    button.buttonType = NSButtonTypeMomentaryChange;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.wantsLayer = YES;
    button.layer.cornerRadius = 3.0;
    button.alignment = NSTextAlignmentCenter;
    // A default height, not a fixed one: the sidebar rows are taller, and a
    // required constraint here would fight the one they add.
    NSLayoutConstraint *height = [button.heightAnchor constraintEqualToConstant:26];
    height.priority = NSLayoutPriorityDefaultHigh;
    height.active = YES;
    [button refreshChrome];
    return button;
}

+ (NSImage *)symbolImageNamed:(NSString *)symbolName
                       boxSize:(CGFloat)box
                     pointSize:(CGFloat)points {
    if (symbolName.length == 0) return nil;
    NSImage *symbol = [NSImage imageWithSystemSymbolName:symbolName
                                accessibilityDescription:nil];
    if (symbol == nil) return nil;
    symbol = [symbol imageWithSymbolConfiguration:
        [NSImageSymbolConfiguration configurationWithPointSize:points
                                                        weight:NSFontWeightRegular
                                                         scale:NSImageSymbolScaleMedium]];
    NSSize drawn = symbol.size;
    // Centred in a fixed square. Symbols are not the same width — a wrench is
    // far wider than a plus — so without a common box the words beside them
    // start at a different place on every row.
    NSImage *canvas = [NSImage imageWithSize:NSMakeSize(box, box)
                                     flipped:NO
                              drawingHandler:^BOOL(NSRect bounds) {
        (void)bounds;
        [symbol drawInRect:NSMakeRect(round((box - drawn.width) / 2),
                                      round((box - drawn.height) / 2),
                                      drawn.width, drawn.height)];
        return YES;
    }];
    canvas.template = YES;
    return canvas;
}

+ (NSButton *)panelButtonWithTitle:(NSString *)title
                            symbol:(NSString *)symbolName
                              role:(SlopNetButtonRole)role
                            target:(id)target
                            action:(SEL)action {
    NSButton *button = [self panelButtonWithTitle:title role:role
                                           target:target action:action];
    NSImage *icon = [self symbolImageNamed:symbolName boxSize:18 pointSize:14];
    if (icon == nil) return button;
    if ([button isKindOfClass:SlopNetPanelButton.class]) {
        ((SlopNetPanelButton *)button).symbolName = symbolName;
    }
    button.image = icon;
    button.imagePosition = NSImageLeft;
    button.imageHugsTitle = YES;
    [SlopNetBrand setPanelButton:button role:role];   // re-tint with the icon in place
    return button;
}

+ (void)setPanelButton:(NSButton *)button role:(SlopNetButtonRole)role {
    if (![button isKindOfClass:SlopNetPanelButton.class]) return;
    SlopNetPanelButton *panel = (SlopNetPanelButton *)button;
    panel.role = role;
    [panel refreshChrome];
}

+ (void)styleFieldEditor:(NSText *)editor {
    if ([editor isKindOfClass:NSTextView.class]) {
        NSTextView *view = (NSTextView *)editor;
        view.insertionPointColor = [self crimsonColor];
        view.selectedTextAttributes = @{
            NSBackgroundColorAttributeName: [[self crimsonColor] colorWithAlphaComponent:0.35],
            NSForegroundColorAttributeName: [self inkColor],
        };
    }
}

+ (NSAttributedString *)markAttributedForProvider:(NSString *)providerId
                                             size:(CGFloat)size {
    if (providerId.length == 0) return nil;
    if ([self entryForProvider:providerId] == NULL) return nil;
    NSString *mark = [self markForProvider:providerId];
    if (mark.length == 0) return nil;
    NSDictionary *attributes = @{
        NSFontAttributeName: [self consoleFontOfSize:size],
        NSForegroundColorAttributeName: [self markColorForProvider:providerId],
    };
    return [[NSAttributedString alloc] initWithString:mark attributes:attributes];
}

+ (NSColor *)backgroundColorForProvider:(NSString *)providerId {
    const SlopNetBrandEntry *entry = [self entryForProvider:providerId ?: @""];
    return entry ? SlopNetColorFromHex(entry->panel) : [self voidColor];
}

+ (NSColor *)foregroundColorForProvider:(NSString *)providerId {
    const SlopNetBrandEntry *entry = [self entryForProvider:providerId ?: @""];
    return entry ? SlopNetColorFromHex(entry->text) : [self crimsonColor];
}

+ (NSColor *)markColorForProvider:(NSString *)providerId {
    const SlopNetBrandEntry *entry = [self entryForProvider:providerId ?: @""];
    if (entry == NULL) return [self crimsonColor];
    return SlopNetColorFromHex(entry->markInk ?: entry->text);
}

+ (NSColor *)tintColorForProvider:(NSString *)providerId {
    const SlopNetBrandEntry *entry = [self entryForProvider:providerId ?: @""];
    return entry ? SlopNetColorFromHex(entry->tint) : [self ghostColor];
}

+ (BOOL)colorFontActive {
    static BOOL active = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *url = [[NSBundle mainBundle] URLForResource:kColorFontFile
                                             withExtension:@"ttf"];
        if (url == nil) {
            // Outside an .app there is no bundle to read from, so probes and
            // the renderer fell back to plain Unicode marks — and the fallback
            // is a DIFFERENT WIDTH from the real badge, which quietly changed
            // the column arithmetic in every picture used to check a layout.
            // A checkout-relative copy keeps those tools honest. The bundle
            // always wins when there is one, so the shipped app is unaffected.
            NSString *inTree = [NSString stringWithFormat:
                @"packaging/terminal-visuals/packaging-fonts/%@.ttf", kColorFontFile];
            if ([NSFileManager.defaultManager fileExistsAtPath:inTree]) {
                url = [NSURL fileURLWithPath:inTree];
            }
        }
        if (url == nil) return;                 // font not bundled: plain marks
        CFErrorRef error = NULL;
        bool registered = CTFontManagerRegisterFontsForURL(
            (__bridge CFURLRef)url, kCTFontManagerScopeProcess, &error);
        if (!registered && error != NULL &&
            CFErrorGetCode(error) != kCTFontManagerErrorAlreadyRegistered) {
            // Damaged or unreadable font file. Say so once, fall back to
            // plain marks, and leave the console on the system font.
            NSLog(@"SlopNet: colour badge font did not register: %@",
                  (__bridge NSError *)error);
            CFRelease(error);
            return;
        }
        if (error != NULL) CFRelease(error);
        // Trust the font server, not the registration call: the font is
        // only "active" if it can actually be instantiated by name.
        active = ([NSFont fontWithName:kColorFontPSName size:12] != nil);
    });
    return active;
}

+ (NSFont *)consoleFontOfSize:(CGFloat)size {
    if ([self colorFontActive]) {
        NSFont *font = [NSFont fontWithName:kColorFontPSName size:size];
        if (font != nil) return font;
    }
    return [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular];
}

+ (NSString *)markForProvider:(NSString *)providerId {
    const SlopNetBrandEntry *entry = [self entryForProvider:providerId ?: @""];
    if (entry == NULL) return @"•";             // unmapped provider: neutral mark
    if ([self colorFontActive]) {
        // The three-cell badge twin, which is the one show_panels.py uses:
        //   cp = ord(g) + CELLS * 0x100   with CELLS = 3
        // Copied rather than chosen. StormCode's panel proportions come from this
        // width, and picking the two-cell twin instead is why the logos here
        // never looked like the reference.
        unichar wide = entry->codepoint + 0x300;
        return [NSString stringWithCharacters:&wide length:1];
    }
    return entry->mark;
}

+ (NSString *)displayNameForProvider:(NSString *)providerId {
    const SlopNetBrandEntry *entry = [self entryForProvider:providerId ?: @""];
    return entry ? entry->display : (providerId ?: @"");
}

+ (NSArray<NSString *> *)allProviders {
    NSMutableArray<NSString *> *all = [NSMutableArray arrayWithCapacity:kBrandCount];
    for (NSUInteger i = 0; i < kBrandCount; i++) [all addObject:kBrands[i].pid];
    return all;
}

+ (NSString *)providerForTool:(NSString *)toolId {
    // tools.json ids → provider ids. Only real, operator-listed tools.
    static NSDictionary<NSString *, NSString *> *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{ @"codex":       @"openai",
                 @"claude":      @"anthropic",
                 @"kimi":        @"moonshot",
                 // Google retired Gemini CLI for individual plans in favour of
                 // Antigravity; the provider is still google.
                 @"antigravity": @"google",
                 @"grok":        @"xai" };
    });
    return toolId ? map[toolId] : nil;
}

+ (NSString *)providerForLocalModel:(NSString *)model {
    if (model.length == 0) return nil;
    // Hugging Face identifiers carry the org up front: "ibm-granite/…".
    if ([model hasPrefix:@"ibm-granite/"]) return @"ibm_granite";
    return nil;
}

#pragma mark - action glyphs

+ (NSArray<NSString *> *)actionConcepts {
    NSMutableArray<NSString *> *all = [NSMutableArray arrayWithCapacity:kActionCount];
    for (NSUInteger i = 0; i < kActionCount; i++) [all addObject:kActions[i].concept];
    return all;
}

+ (NSUInteger)frameCountForAction:(NSString *)concept {
    const SlopNetActionEntry *entry = [self entryForAction:concept ?: @""];
    if (entry == NULL) return 0;
    return [self colorFontActive] ? entry->frames : 1;
}

+ (NSString *)actionGlyph:(NSString *)concept frame:(NSUInteger)index cells:(NSUInteger)cells {
    NSUInteger width = MAX((NSUInteger)2, MIN(cells, (NSUInteger)3));
    const SlopNetActionEntry *entry = [self entryForAction:concept ?: @""];
    if (entry != NULL && [self colorFontActive]) {
        // Only the N-cell twins carry artwork (build_action_frames.py builds
        // widths 2 and 3); the base codepoint is deliberately blank.
        unichar glyph = (unichar)(entry->first + (index % entry->frames) + width * 0x100);
        return [NSString stringWithCharacters:&glyph length:1];
    }
    // No colour font, or a concept nobody has drawn: a plain spinner in the
    // same number of columns, so nothing shifts and nothing shows as tofu.
    static NSString *const turning[] = { @"◐", @"◓", @"◑", @"◒" };
    NSString *fallback = entry != NULL ? turning[index % 4] : @"·";
    return [fallback stringByPaddingToLength:fallback.length + (width - 1)
                                  withString:@" " startingAtIndex:0];
}

#pragma mark - panels (the StormCode blocks)

/// The badge for a panel row, always kMarkColumns wide in either mode.
+ (NSString *)paddedMarkForProvider:(NSString *)providerId {
    NSString *mark = [self markForProvider:providerId];
    // show_panels.py: `chr(cp) + " " * (CELLS - 1)` — a terminal paints the wide
    // bitmap but only advances one cell, so it pads. AppKit advances the whole
    // glyph itself, so the padding here would be counted twice. Same intent,
    // and the only line of theirs that cannot be copied literally.
    if ([self colorFontActive]) return mark;
    return [mark stringByAppendingString:@"  "];   // their fallback: mark + 2
}

/// The striped IBM wordmark face lives at U+E800, in the order A-Z, a-z, 0-9.
/// Exactly 62 glyphs, which is what the bundled font carries — punctuation was
/// never built, so it is deliberately left in the base face.
static NSString *const kStripedAlphabet =
    @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
static const unichar kStripedBase = 0xE800;

+ (NSString *)stripedText:(NSString *)text {
    if (text.length == 0) return @"";
    // Without the bundled face every one of these codepoints draws as a tofu
    // box, which is worse than the plain word it replaced. Plain text is the
    // fallback, exactly as it is for the provider marks.
    if (![self colorFontActive]) return text;
    NSMutableString *out = [NSMutableString stringWithCapacity:text.length];
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        NSRange found = [kStripedAlphabet rangeOfString:
            [NSString stringWithCharacters:&c length:1]];
        if (found.location == NSNotFound) {
            [out appendFormat:@"%C", c];
        } else {
            [out appendFormat:@"%C", (unichar)(kStripedBase + found.location)];
        }
    }
    return out;
}

+ (NSString *)headerANSI:(NSString *)title width:(NSUInteger)width {
    NSUInteger inner = MAX((NSUInteger)20, width);
    NSString *field = SlopNetFieldSGR([self voidColor]);
    NSString *frame = SlopNetInkSGR([self crimsonColor]);
    // Drawn in the striped face. It is the one piece of the StormCode identity
    // that was bundled and never used — every heading was plain monospace.
    NSString *shown = [self stripedText:title.uppercaseString];
    NSString *label = [NSString stringWithFormat:@"══ %@ ", shown];
    NSInteger fill = (NSInteger)inner - (NSInteger)label.length;
    return [NSString stringWithFormat:@"%@%@\033[1m%@\033[22m%@%@",
            field, frame, label, SlopNetRepeat(@"═", fill), kReset];
}

+ (NSString *)youSaidANSI:(NSString *)text width:(NSUInteger)width {
    // The shape demo_agency.py draws: a panel per message, a header row
    // carrying the speaker and what kind of turn it is, then the words
    // wrapped and indented inside it. The person has no vendor, so the fill
    // is the field itself and the mark is a caret, exactly as the demo does
    // for its own user turns.
    NSUInteger panelWidth = MAX((NSUInteger)24, width);
    NSColor *panel = [self voidColor];
    NSColor *ink = [self inkColor];
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    [rows addObject:[self panelRuleWithWidth:panelWidth left:@"┌" right:@"┐" label:@""]];

    NSString *mark = [self colorFontActive]
        ? [self actionGlyph:@"user-message" frame:0 cells:kMarkColumns]
        : [@"▶" stringByPaddingToLength:kMarkColumns withString:@" " startingAtIndex:0];
    NSString *head = [NSString stringWithFormat:@" %@ \033[1mYou\033[22m", mark];
    [rows addObject:[self panelRowWithWidth:panelWidth panel:panel text:ink
                                       body:head columns:[self visibleColumns:head]]];

    for (NSString *line in [self wrapText:text toColumns:(NSInteger)panelWidth - 6]) {
        NSString *body = [NSString stringWithFormat:@"  %@", line];
        [rows addObject:[self panelRowWithWidth:panelWidth panel:panel text:ink
                                           body:body columns:2 + line.length]];
    }
    [rows addObject:[self panelRuleWithWidth:panelWidth left:@"└" right:@"┘" label:@""]];
    return [NSString stringWithFormat:@"\n%@", [rows componentsJoinedByString:@"\n"]];
}

/// Break text to a column count on word boundaries, the way the demo wraps
/// every panel body. A word longer than the line is left whole rather than
/// cut, because a split identifier is harder to read than a ragged edge.
+ (NSArray<NSString *> *)wrapText:(NSString *)text toColumns:(NSInteger)columns {
    if (columns < 8) columns = 8;
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *paragraph in [text componentsSeparatedByString:@"\n"]) {
        NSMutableString *line = [NSMutableString string];
        for (NSString *word in [paragraph componentsSeparatedByString:@" "]) {
            if (word.length == 0) continue;
            if (line.length == 0) {
                [line appendString:word];
            } else if ((NSInteger)(line.length + 1 + word.length) <= columns) {
                [line appendFormat:@" %@", word];
            } else {
                [lines addObject:[line copy]];
                [line setString:word];
            }
        }
        [lines addObject:[line copy]];
    }
    return lines;
}

+ (NSString *)guideSaidANSI:(NSString *)text
                   provider:(NSString *)providerId
                       name:(NSString *)name
                      width:(NSUInteger)width {
    return [self guideSaidANSI:text provider:providerId name:name
                        action:@"message" frame:0 width:width];
}

+ (NSString *)guideSaidANSI:(NSString *)text
                   provider:(NSString *)providerId
                       name:(NSString *)name
                     action:(NSString *)action
                      frame:(NSUInteger)frame
                      width:(NSUInteger)width {
    NSUInteger panelWidth = MAX((NSUInteger)24, width);
    NSColor *panel = [self backgroundColorForProvider:providerId] ?: [self voidColor];
    NSColor *ink = [self foregroundColorForProvider:providerId] ?: [self inkColor];
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    [rows addObject:[self panelRuleWithWidth:panelWidth left:@"┌" right:@"┐" label:@""]];

    NSString *mark = [self markForProvider:providerId] ?: @"◆";
    NSString *icon = [self colorFontActive]
        ? [self actionGlyph:action frame:frame cells:kMarkColumns]
        : [@"" stringByPaddingToLength:kMarkColumns withString:@" " startingAtIndex:0];
    NSString *label = [[action substringToIndex:1].uppercaseString
        stringByAppendingString:[action substringFromIndex:1]];
    NSString *head = [NSString stringWithFormat:@" %@ \033[1m%@\033[22m  %@ \033[2m%@\033[22m",
                      mark, name, icon, label];
    [rows addObject:[self panelRowWithWidth:panelWidth panel:panel text:ink body:head
                                    columns:[self visibleColumns:head]]];

    for (NSString *line in [self wrapText:text toColumns:(NSInteger)panelWidth - 6]) {
        NSString *body = [NSString stringWithFormat:@"  %@", line];
        [rows addObject:[self panelRowWithWidth:panelWidth panel:panel text:ink
                                           body:body columns:2 + line.length]];
    }
    [rows addObject:[self panelRuleWithWidth:panelWidth left:@"└" right:@"┘" label:@""]];
    return [NSString stringWithFormat:@"\n%@", [rows componentsJoinedByString:@"\n"]];
}

+ (NSString *)guideRepliesANSIForProvider:(NSString *)providerId name:(NSString *)name {
    NSString *mark = [self markForProvider:providerId] ?: @"◆";
    NSColor *tint = [self tintColorForProvider:providerId] ?: [self crimsonColor];
    return [NSString stringWithFormat:@"\n%@%@ %@%@",
            SlopNetInkSGR(tint), mark, [self stripedText:name], kReset];
}

/// One row of a panel: crimson edges, brand fill between them, padded so
/// every row is exactly `width` columns. A row sets its colours at the start
/// of each run and resets once at the very end — never mid-line, which in a
/// real terminal would hand the field back to the user's own profile.
/// How many terminal cells a row body actually occupies.
///
/// Hand-counting this is what keeps breaking the frames: a body is built from
/// a format string with escape sequences in it and badge glyphs that are one
/// character but several cells, and every time the icon width changed someone
/// had to remember to change a number somewhere else. Twice they drifted apart
/// and the right-hand border landed in the wrong column.
///
/// This is StormCode's vlen() with one addition: there, a badge is padded so
/// its character count equals its cell count, and here the glyph carries its
/// own advance, so the extra cells are added instead.
+ (NSUInteger)visibleColumns:(NSString *)body {
    static NSRegularExpression *sgr;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sgr = [NSRegularExpression regularExpressionWithPattern:@"\x1B\\[[0-9;]*m"
                                                        options:0 error:nil];
    });
    NSString *bare = [sgr stringByReplacingMatchesInString:body options:0
                                                     range:NSMakeRange(0, body.length)
                                              withTemplate:@""];
    NSUInteger cells = bare.length;
    for (NSUInteger i = 0; i < bare.length; i++) {
        unichar c = [bare characterAtIndex:i];
        BOOL wide = (c >= 0xE000 && c <= 0xE7FF) || (c >= 0xE900 && c <= 0xEC45);
        if (wide) cells += kMarkColumns - 1;
    }
    return cells;
}

+ (NSString *)panelRowWithWidth:(NSUInteger)width
                          panel:(NSColor *)panel
                           text:(NSColor *)text
                           body:(NSString *)body
                        columns:(NSUInteger)columns {
    NSInteger pad = (NSInteger)width - 2 - (NSInteger)columns;
    return [NSString stringWithFormat:@"%@%@│%@%@%@%@%@%@│%@",
            SlopNetFieldSGR([self voidColor]), SlopNetInkSGR([self crimsonColor]),
            SlopNetFieldSGR(panel), SlopNetInkSGR(text), body, SlopNetRepeat(@" ", pad),
            SlopNetFieldSGR([self voidColor]), SlopNetInkSGR([self crimsonColor]),
            kReset];
}

+ (NSString *)panelRuleWithWidth:(NSUInteger)width
                            left:(NSString *)left
                           right:(NSString *)right
                           label:(NSString *)label {
    NSString *field = SlopNetFieldSGR([self voidColor]);
    NSString *frame = SlopNetInkSGR([self crimsonColor]);
    NSString *head = label.length > 0
        ? [NSString stringWithFormat:@"─ \033[1m%@\033[22m ", label] : @"";
    NSUInteger headColumns = label.length > 0 ? label.length + 3 : 0;
    NSInteger dashes = (NSInteger)width - 2 - (NSInteger)headColumns;
    return [NSString stringWithFormat:@"%@%@%@%@%@%@%@",
            field, frame, left, head, SlopNetRepeat(@"─", dashes), right, kReset];
}

+ (NSString *)panelANSIForProvider:(NSString *)providerId
                             title:(NSString *)title
                            detail:(NSArray<NSString *> *)detail
                            action:(NSString *)action
                             frame:(NSUInteger)frame
                             width:(NSUInteger)width {
    // Floor of 16: enough for the badge, a space and a short name. A lane in
    // a panel strip is narrower than a full-width panel, and clamping it up
    // would push the strip past the width its caller measured.
    NSUInteger panelWidth = MAX((NSUInteger)16, width);
    NSUInteger room = panelWidth - 2;
    NSColor *panel = [self backgroundColorForProvider:providerId];
    NSColor *text = [self foregroundColorForProvider:providerId];
    NSString *name = title.length > 0 ? title : [self displayNameForProvider:providerId];

    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    [rows addObject:[self panelRuleWithWidth:panelWidth left:@"┌" right:@"┐" label:@""]];

    // Header row: the badge, then the recognised name.
    NSUInteger nameRoom = room > kMarkColumns + 3 ? room - kMarkColumns - 3 : 1;
    NSString *shownName = name.length > nameRoom ? [name substringToIndex:nameRoom] : name;
    NSString *header = [NSString stringWithFormat:@" %@ %@",
                        [self paddedMarkForProvider:providerId], shownName];
    // A state word, right-aligned on the header row. show_panels.py puts DONE
    // / RUN / WAIT there, and it is what stops a tile reading as a bare label:
    // the eye lands on the name, then on where it stands.
    NSString *state = nil;
    if (detail.count > 0) {
        NSString *first = detail.firstObject;
        // One word for what the app can do right now. "SET UP" was ambiguous
        // in the worst way — it read equally as "this is set up" and "set this
        // up" — and tiles are only drawn for apps that are connected, so the
        // only two states left are usable, or waiting out a usage limit.
        if ([first isEqualToString:@"ready"]) state = @"READY";
        else if ([first hasPrefix:@"back in"]) state = @"LIMIT";
        // The guide's own words, so a local model reads the same way a coding
        // app does: one word, right-aligned, saying whether it can be used.
        else if ([first isEqualToString:@"loaded"]) state = @"LOADED";
        else if ([first isEqualToString:@"locked"]) state = @"LOCKED";
    }
    if (state.length > 0) {
        NSInteger gap = (NSInteger)panelWidth - 2
            - (NSInteger)(2 + kMarkColumns + shownName.length) - (NSInteger)state.length - 1;
        if (gap < 1) gap = 1;
        NSString *withState = [NSString stringWithFormat:@"%@%@\033[2m%@\033[22m ",
                               header, SlopNetRepeat(@" ", gap), state];
        [rows addObject:[self panelRowWithWidth:panelWidth panel:panel text:text
                                           body:withState
                                        columns:2 + kMarkColumns + shownName.length
                                                + gap + state.length + 1]];
    } else {
        [rows addObject:[self panelRowWithWidth:panelWidth panel:panel text:text
                                           body:header
                                        columns:2 + kMarkColumns + shownName.length]];
    }

    if (action.length > 0 && [self frameCountForAction:action] > 0) {
        // The action row is the panel's live pulse: the glyph animates, and
        // its label takes the brand's tint so the row reads as an accent
        // rather than another line of body text.
        NSString *glyph = [self actionGlyph:action frame:frame cells:2];
        NSString *label = [[action substringToIndex:1].uppercaseString
            stringByAppendingString:[action substringFromIndex:1]];
        NSString *body = [NSString stringWithFormat:@" %@ %@%@",
                          glyph, SlopNetInkSGR([self tintColorForProvider:providerId]), label];
        [rows addObject:[self panelRowWithWidth:panelWidth panel:panel text:text
                                           body:body
                                        columns:2 + 2 + label.length]];
    }

    for (NSString *line in detail) {
        // A bare state marker is the word in the header, not a line of body.
        if ([line isEqualToString:@"loaded"] || [line isEqualToString:@"locked"]) continue;
        NSString *shown = line.length > room - 2 ? [line substringToIndex:room - 2] : line;
        [rows addObject:[self panelRowWithWidth:panelWidth panel:panel text:text
                                           body:[NSString stringWithFormat:@" %@", shown]
                                        columns:1 + shown.length]];
    }

    [rows addObject:[self panelRuleWithWidth:panelWidth left:@"└" right:@"┘" label:@""]];
    return [rows componentsJoinedByString:@"\n"];
}

+ (NSString *)brandSheetANSIForProviders:(NSArray<NSString *> *)providers
                                   label:(NSString *)label
                                   width:(NSUInteger)width {
    NSUInteger cell = 18;                      // badge + a short name
    NSUInteger perRow = MAX((NSUInteger)1, (width - 2) / cell);
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    [rows addObject:[self panelRuleWithWidth:width left:@"┌" right:@"┐" label:label]];
    for (NSUInteger start = 0; start < providers.count; start += perRow) {
        NSMutableString *body = [NSMutableString string];
        NSUInteger columns = 0;
        for (NSUInteger i = start; i < MIN(start + perRow, providers.count); i++) {
            NSString *pid = providers[i];
            NSUInteger nameRoom = cell - kMarkColumns - 2;
            NSString *name = [self displayNameForProvider:pid];
            if (name.length > nameRoom) name = [name substringToIndex:nameRoom];
            NSString *segment = [NSString stringWithFormat:@" %@ %@",
                                 [self paddedMarkForProvider:pid], name];
            NSUInteger used = 2 + kMarkColumns + name.length;
            [body appendFormat:@"%@%@%@%@%@",
                SlopNetFieldSGR([self backgroundColorForProvider:pid]),
                SlopNetInkSGR([self foregroundColorForProvider:pid]),
                segment, SlopNetRepeat(@" ", (NSInteger)cell - (NSInteger)used),
                SlopNetFieldSGR([self voidColor])];
            columns += cell;
        }
        [rows addObject:[NSString stringWithFormat:@"%@%@│%@%@%@%@│%@",
            SlopNetFieldSGR([self voidColor]), SlopNetInkSGR([self crimsonColor]),
            body, SlopNetRepeat(@" ", (NSInteger)width - 2 - (NSInteger)columns),
            SlopNetFieldSGR([self voidColor]), SlopNetInkSGR([self crimsonColor]), kReset]];
    }
    [rows addObject:[self panelRuleWithWidth:width left:@"└" right:@"┘" label:@""]];
    return [rows componentsJoinedByString:@"\n"];
}

+ (NSString *)providerSheetANSIWithWidth:(NSUInteger)width {
    return [self brandSheetANSIForProviders:[self allProviders]
                                      label:@"PROVIDERS"
                                      width:width];
}

+ (NSString *)panelStripANSIForProviders:(NSArray<NSString *> *)providers
                                   width:(NSUInteger)width {
    return [self panelStripANSIForProviders:providers status:nil width:width];
}

+ (NSString *)panelStripANSIForProviders:(NSArray<NSString *> *)providers
                                  status:(NSDictionary<NSString *, NSString *> *)status
                                   width:(NSUInteger)width {
    if (providers.count == 0) return @"";
    // Three lanes at most: past that the names stop fitting and the row turns
    // into a stack of abbreviations. Lanes share the width exactly, with the
    // remainder spread over the leftmost ones, so the strip ends where the
    // panels above it do.
    // Two to a row. Three left each tile too narrow for a name and a status
    // line, which is what made them read as buttons rather than as panels.
    NSUInteger perRow = MIN((NSUInteger)2, MAX((NSUInteger)1, (width + 1) / 27));
    NSUInteger span = width - (perRow - 1);
    NSUInteger base = span / perRow, remainder = span % perRow;
    NSMutableArray<NSString *> *blocks = [NSMutableArray array];
    for (NSUInteger start = 0; start < providers.count; start += perRow) {
        NSMutableArray<NSArray<NSString *> *> *panels = [NSMutableArray array];
        NSUInteger widest = 0;
        for (NSUInteger i = start; i < MIN(start + perRow, providers.count); i++) {
            NSUInteger lane = base + ((i - start) < remainder ? 1 : 0);
            widest = MAX(widest, lane);
            NSString *note = status[providers[i]];
            NSString *panel = [self panelANSIForProvider:providers[i]
                                                  title:nil
                                                 detail:note.length > 0 ? @[note] : nil
                                                 action:nil
                                                  frame:0
                                                  width:lane];
            [panels addObject:[panel componentsSeparatedByString:@"\n"]];
        }
        // Every panel row is exactly `lane` columns and resets its own
        // colours at the end, so laying them side by side is plain
        // concatenation — the property demo_agency relies on too.
        NSUInteger height = 0;
        for (NSArray<NSString *> *panel in panels) height = MAX(height, panel.count);
        NSMutableArray<NSString *> *rows = [NSMutableArray array];
        for (NSUInteger line = 0; line < height; line++) {
            NSMutableArray<NSString *> *pieces = [NSMutableArray array];
            for (NSArray<NSString *> *panel in panels) {
                [pieces addObject:line < panel.count ? panel[line]
                                                     : SlopNetRepeat(@" ", (NSInteger)widest)];
            }
            [rows addObject:[pieces componentsJoinedByString:@" "]];
        }
        [blocks addObject:[rows componentsJoinedByString:@"\n"]];
    }
    return [blocks componentsJoinedByString:@"\n"];
}

+ (NSString *)colourCheckANSIWithWidth:(NSUInteger)width {
    NSUInteger cells = MAX((NSUInteger)16, MIN(width, (NSUInteger)64));
    NSMutableString *ramp = [NSMutableString string];
    NSMutableString *text = [NSMutableString string];
    for (NSUInteger i = 0; i < cells; i++) {
        double position = (double)i / (double)MAX((NSUInteger)1, cells - 1);
        // A sweep from the crimson chrome colour to the Granite green, so both
        // ends are colours this app actually uses.
        NSInteger r = (NSInteger)lround(255 * (1.0 - position));
        NSInteger g = (NSInteger)lround(0 + 171 * position);
        NSInteger b = (NSInteger)lround(60 * (1.0 - position) + 35 * position);
        [ramp appendFormat:@"\033[48;2;%ld;%ld;%ldm ", (long)r, (long)g, (long)b];
        [text appendFormat:@"\033[38;2;%ld;%ld;%ldm▀", (long)r, (long)g, (long)b];
    }
    return [NSString stringWithFormat:@"%@%@\n%@%@\n%@%@24-bit colour check: "
            @"a smooth sweep above means the console carries truecolor.%@",
            ramp, kReset, text, kReset,
            SlopNetFieldSGR([self voidColor]), SlopNetInkSGR([self ghostColor]), kReset];
}

@end
