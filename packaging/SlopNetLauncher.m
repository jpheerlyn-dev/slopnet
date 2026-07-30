// SlopNet — the Mac control window.
//
// Shape: a sidebar on the left (what is connected, the controls, what you
// built before), a terminal filling the middle, and a chat-style box along
// the bottom. A command line wearing a familiar app.
//
// Everything runs INSIDE this window (see SlopNetConsole): no Terminal, no
// AppleScript, no macOS Automation permission.
//
// The rule that shapes the layout: never ask someone to do a thing they
// have already done. Once a server is connected, setup lives in the
// Settings window and this one offers the next real step instead.
//
// "Server" means anything you can reach over SSH: a rented box, a
// dedicated machine, a home server, a Raspberry Pi.

#import <Cocoa/Cocoa.h>
#import <CoreImage/CoreImage.h>
#import <float.h>
#import <math.h>
#import "SlopNetBrand.h"
#import "SlopNetConsole.h"
#import "SlopNetSettings.h"

static NSString *const kHostKey     = @"SlopNetVPSHost";
static NSString *const kUserKey     = @"SlopNetVPSUser";
static NSString *const kPortKey     = @"SlopNetVPSPort";
static NSString *const kReadyKey    = @"SlopNetVPSReady";   // setup finished cleanly

// NSTextView has no native placeholder on the oldest macOS version SlopNet
// supports. Keep the tiny drawing behaviour here instead of putting a fake
// label over the editor (which would steal clicks and accessibility focus).
@interface SlopNetEntryView : NSTextView
@property(nonatomic, copy) NSString *prompt;
@end

@implementation SlopNetEntryView
- (void)setPrompt:(NSString *)prompt {
    _prompt = [prompt copy];
    [self setNeedsDisplay:YES];
}
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    if (self.string.length == 0 && self.prompt.length > 0) {
        NSDictionary *attributes = @{
            NSFontAttributeName: self.font ?: [NSFont systemFontOfSize:12],
            NSForegroundColorAttributeName: [NSColor placeholderTextColor],
        };
        [self.prompt drawAtPoint:NSMakePoint(self.textContainerInset.width,
                                             self.textContainerInset.height + 1)
                   withAttributes:attributes];
    }
}
- (void)didChangeText { [super didChangeText]; [self setNeedsDisplay:YES]; }
@end

@interface SlopNetAppDelegate : NSObject <NSApplicationDelegate, SlopNetConsoleDelegate,
                                          SlopNetSettingsDelegate, NSTextViewDelegate>
@property(nonatomic, strong) NSWindow *window;

// sidebar
@property(nonatomic, strong) NSTextField *statusDot;
@property(nonatomic, strong) NSTextField *statusText;
@property(nonatomic, strong) NSStackView *historyStack;
@property(nonatomic, strong) NSButton *settingsToggle;

// the server, remembered between launches
@property(nonatomic, copy) NSString *host;
@property(nonatomic, copy) NSString *username;
@property(nonatomic, copy) NSString *port;
@property(nonatomic, strong) SlopNetSettings *settings;

// main
@property(nonatomic, strong) SlopNetConsole *console;
@property(nonatomic, strong) NSTextField *projectName;
@property(nonatomic, strong) NSPopUpButton *modePicker;
@property(nonatomic, strong) NSPopUpButton *modelPicker;
@property(nonatomic, strong) SlopNetEntryView *entry;
@property(nonatomic, strong) NSScrollView *entryScroller;
@property(nonatomic, strong) NSLayoutConstraint *entryHeight;
@property(nonatomic, strong) NSButton *sendButton;
@property(nonatomic, strong) NSURL *conversationURL;

// The animated action glyph. One timer drives whichever surface is live:
// the status line under the console while a program runs, or the action row
// of the ready block while nothing does.
@property(nonatomic, strong) NSTimer *actionTimer;
@property(nonatomic, assign) NSUInteger actionTick;
@property(nonatomic, copy) NSString *actionConcept;
@property(nonatomic, copy) NSString *actionCaption;
@property(nonatomic, assign) NSInteger readyBlockToken;

// Dock icon: slow continuous hue + chroma drift for the whole session.
@property(nonatomic, strong) NSTimer *dockIconTimer;
@property(nonatomic, strong) NSImage *baseDockIcon;
@property(nonatomic, strong) CIContext *dockIconContext;
@property(nonatomic, assign) CGFloat dockHueRadians;
@property(nonatomic, assign) CGFloat dockChromaPhase;

@property(nonatomic, assign) BOOL busy;
@property(nonatomic, assign) BOOL setupRunning;
@property(nonatomic, assign) BOOL localHelperRunning;
@property(nonatomic, assign) BOOL planningRunning;
@property(nonatomic, assign) BOOL approvedBuildRunning;
@property(nonatomic, copy) NSString *activeProjectName;
@property(nonatomic, copy) NSString *plannedProjectName;
@property(nonatomic, copy) NSString *localModelName;
@end

@implementation SlopNetAppDelegate

#pragma mark - tiny builders

- (NSTextField *)label:(NSString *)text size:(CGFloat)size grey:(BOOL)grey {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:size];
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.maximumNumberOfLines = 5;
    if (grey) label.textColor = [NSColor secondaryLabelColor];
    return label;
}

// Sidebar rows look and behave like navigation: the whole row is the click
// target, not just the words.
- (NSButton *)sidebarButton:(NSString *)title action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
    button.title = title;
    button.target = self;
    button.action = action;
    button.bezelStyle = NSBezelStyleRecessed;
    button.bordered = NO;
    button.alignment = NSTextAlignmentLeft;
    button.font = [NSFont systemFontOfSize:12.5];
    button.contentTintColor = [NSColor labelColor];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.heightAnchor constraintEqualToConstant:28].active = YES;
    return button;
}

- (NSTextField *)field:(NSString *)placeholder value:(NSString *)value {
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    field.placeholderString = placeholder;
    if (value) field.stringValue = value;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field.heightAnchor constraintEqualToConstant:24].active = YES;
    return field;
}

- (NSStackView *)row:(NSString *)labelText control:(NSView *)control width:(CGFloat)width {
    NSTextField *label = [self label:labelText size:12 grey:NO];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label.widthAnchor constraintEqualToConstant:110].active = YES;
    [control.widthAnchor constraintEqualToConstant:width].active = YES;
    NSStackView *row = [NSStackView stackViewWithViews:@[label, control]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 8;
    return row;
}

- (NSBox *)separator {
    NSBox *line = [[NSBox alloc] initWithFrame:NSZeroRect];
    line.boxType = NSBoxSeparator;
    line.translatesAutoresizingMaskIntoConstraints = NO;
    [line.heightAnchor constraintEqualToConstant:1].active = YES;
    return line;
}

#pragma mark - launch

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 1000, 700)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    self.window.title = @"SlopNet";
    self.window.minSize = NSMakeSize(820, 520);
    [self.window center];

    NSSplitView *split = [[NSSplitView alloc] initWithFrame:NSZeroRect];
    split.vertical = YES;
    split.dividerStyle = NSSplitViewDividerStyleThin;
    split.translatesAutoresizingMaskIntoConstraints = NO;
    [split addArrangedSubview:[self buildSidebar]];
    [split addArrangedSubview:[self buildMain]];

    NSView *content = self.window.contentView;
    [content addSubview:split];
    [NSLayoutConstraint activateConstraints:@[
        [split.topAnchor constraintEqualToAnchor:content.topAnchor],
        [split.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [split.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [split.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];
    [split setPosition:236 ofDividerAtIndex:0];

    [self recall];
    [self refreshState];
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.entry];
    [NSApp activateIgnoringOtherApps:YES];

    // After the window exists: the ready block measures the console to fit
    // its panels, and there is nothing to measure until layout has run.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showReadyBlock];
        // SLOPNET_DEBUG_VISUALS=1 opens on the same view the Providers button
        // shows: every mapped mark, plus a 24-bit colour check. It is how the
        // visual proofs in the register are captured, and the quickest way to
        // see whether the badge font and colour survived a build.
        if ([NSProcessInfo.processInfo.environment[@"SLOPNET_DEBUG_VISUALS"]
                isEqualToString:@"1"]) {
            [self showProviders:nil];
        }
    });

    // First-run is an in-app guide, not a buried hint. It starts before any
    // provider login, planning, or model conversation can be reached.
    if (![self isReady]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self openSettings:nil]; });
    } else {
        [self refreshLocalModelName];
    }

    // Live Dock icon: hue and chroma drift slowly for as long as the app runs.
    [self startDockIconAnimation];
}

#pragma mark - dock icon (hue + chroma)

/// Load the installed app icon once. Prefer the bundle .icns; fall back to
/// whatever macOS already put on the Dock tile. Then punch the white page
/// background to transparent — SlopNet-Logo.png is an opaque white rectangle
/// with art in the middle; the static Dock mask hid that, but a live
/// applicationIconImage shows the corners unless we clear them.
- (NSImage *)loadBaseDockIcon {
    NSImage *fromBundle = [NSImage imageNamed:@"AppIcon"];
    if (fromBundle == nil) {
        NSURL *url = [[NSBundle mainBundle] URLForResource:@"AppIcon" withExtension:@"icns"];
        if (url != nil) fromBundle = [[NSImage alloc] initWithContentsOfURL:url];
    }
    if (fromBundle == nil) fromBundle = [[NSApp applicationIconImage] copy];
    if (fromBundle == nil) return nil;
    return [self iconByMakingWhiteBackgroundTransparent:fromBundle];
}

/// Flood-fill near-white pixels reachable from the edges to alpha 0.
/// Leaves non-white logo ink alone, including light greys inside the mark.
- (NSImage *)iconByMakingWhiteBackgroundTransparent:(NSImage *)source {
    if (source == nil) return nil;
    const NSInteger px = 256;
    const CGFloat edge = 256.0;
    size_t bpr = (size_t)px * 4;
    uint8_t *buf = calloc(1, bpr * (size_t)px);
    if (buf == NULL) return source;

    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(
        buf, (size_t)px, (size_t)px, 8, bpr, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    if (ctx == NULL) {
        CGColorSpaceRelease(space);
        free(buf);
        return source;
    }
    CGContextClearRect(ctx, CGRectMake(0, 0, edge, edge));

    NSSize srcSize = source.size;
    if (srcSize.width < 1 || srcSize.height < 1) srcSize = NSMakeSize(edge, edge);
    CGFloat scale = MIN(edge / srcSize.width, edge / srcSize.height);
    CGSize drawSize = CGSizeMake(srcSize.width * scale, srcSize.height * scale);
    CGRect drawRect = CGRectMake((edge - drawSize.width) * 0.5,
                                 (edge - drawSize.height) * 0.5,
                                 drawSize.width, drawSize.height);
    NSGraphicsContext *previous = [NSGraphicsContext currentContext];
    [NSGraphicsContext setCurrentContext:
        [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:NO]];
    [source drawInRect:NSRectFromCGRect(drawRect)
              fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver
              fraction:1.0
        respectFlipped:NO
                 hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
    [NSGraphicsContext setCurrentContext:previous];

    // BGRA/RGBA bytes: R,G,B,A with premultiplied last in our format.
    // Treat a pixel as "paper white" if it's bright and nearly neutral.
    BOOL *visited = calloc((size_t)px * (size_t)px, sizeof(BOOL));
    NSInteger *stack = malloc(sizeof(NSInteger) * (size_t)px * (size_t)px);
    NSInteger sp = 0;
    if (visited == NULL || stack == NULL) {
        free(visited); free(stack);
        CGImageRef cgFail = CGBitmapContextCreateImage(ctx);
        CGContextRelease(ctx); CGColorSpaceRelease(space); free(buf);
        if (!cgFail) return source;
        NSImage *img = [[NSImage alloc] initWithCGImage:cgFail size:NSMakeSize(edge, edge)];
        CGImageRelease(cgFail);
        return img;
    }

    void (^push)(NSInteger, NSInteger) = ^(NSInteger x, NSInteger y) {
        if (x < 0 || y < 0 || x >= px || y >= px) return;
        NSInteger i = y * px + x;
        if (visited[i]) return;
        uint8_t *p = buf + (size_t)i * 4;
        uint8_t r = p[0], g = p[1], b = p[2], a = p[3];
        if (a < 8) { visited[i] = YES; return; } // already clear
        // Near-white paper (logo corners measure ~254–255).
        int maxc = r > g ? (r > b ? r : b) : (g > b ? g : b);
        int minc = r < g ? (r < b ? r : b) : (g < b ? g : b);
        if (maxc < 245 || (maxc - minc) > 18) return; // not white-ish
        visited[i] = YES;
        stack[sp++] = i;
    };

    // Seed from all four edges so the page background is fully reachable.
    for (NSInteger x = 0; x < px; x++) { push(x, 0); push(x, px - 1); }
    for (NSInteger y = 0; y < px; y++) { push(0, y); push(px - 1, y); }

    while (sp > 0) {
        NSInteger i = stack[--sp];
        uint8_t *p = buf + (size_t)i * 4;
        p[0] = p[1] = p[2] = p[3] = 0; // transparent
        NSInteger x = i % px, y = i / px;
        push(x + 1, y); push(x - 1, y); push(x, y + 1); push(x, y - 1);
    }
    free(visited);
    free(stack);

    CGImageRef cg = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    CGColorSpaceRelease(space);
    free(buf);
    if (cg == NULL) return source;
    NSImage *out = [[NSImage alloc] initWithCGImage:cg size:NSMakeSize(edge, edge)];
    CGImageRelease(cg);
    return out;
}

- (void)startDockIconAnimation {
    [self stopDockIconAnimation];
    self.baseDockIcon = [self loadBaseDockIcon];
    if (self.baseDockIcon == nil) return;

    self.dockIconContext = [CIContext contextWithOptions:@{
        kCIContextUseSoftwareRenderer: @NO,
    }];
    self.dockHueRadians = 0;
    self.dockChromaPhase = 0;

    // ~8 fps is enough for a slow drift and keeps Core Image cost tiny.
    __weak typeof(self) weakSelf = self;
    self.dockIconTimer = [NSTimer scheduledTimerWithTimeInterval:0.125
                                                         repeats:YES
                                                           block:^(__unused NSTimer *timer) {
        [weakSelf tickDockIconAnimation];
    }];
    // Fire once immediately so the Dock moves before the first interval.
    [self tickDockIconAnimation];
}

- (void)stopDockIconAnimation {
    [self.dockIconTimer invalidate];
    self.dockIconTimer = nil;
    if (self.baseDockIcon != nil) {
        NSApp.applicationIconImage = self.baseDockIcon;
    }
}

/// Apply a slow hue rotate and a gentle chroma (saturation) oscillation.
/// Hue walks the full circle; saturation breathes between muted and vivid.
- (void)tickDockIconAnimation {
    if (self.baseDockIcon == nil || self.dockIconContext == nil) return;

    // Full hue cycle ≈ 48 s; chroma breath ≈ 14 s (independent periods).
    self.dockHueRadians += (CGFloat)(2.0 * M_PI * 0.125 / 48.0);
    if (self.dockHueRadians > (CGFloat)(2.0 * M_PI)) {
        self.dockHueRadians -= (CGFloat)(2.0 * M_PI);
    }
    self.dockChromaPhase += (CGFloat)(2.0 * M_PI * 0.125 / 14.0);
    if (self.dockChromaPhase > (CGFloat)(2.0 * M_PI)) {
        self.dockChromaPhase -= (CGFloat)(2.0 * M_PI);
    }
    // Saturation: 0.55 … 1.45 around neutral 1.0.
    CGFloat saturation = 1.0 + 0.45 * sin(self.dockChromaPhase);

    NSImage *tinted = [self imageByShiftingHue:self.dockHueRadians
                                    saturation:saturation
                                      ofImage:self.baseDockIcon];
    if (tinted != nil) NSApp.applicationIconImage = tinted;
}

- (NSImage *)imageByShiftingHue:(CGFloat)hueRadians
                     saturation:(CGFloat)saturation
                       ofImage:(NSImage *)source {
    if (source == nil || self.dockIconContext == nil) return nil;

    // Fixed Dock-friendly size. Must keep a real alpha channel: white/opaque
    // corners are the usual failure mode when transparency is lost.
    const CGFloat edge = 256.0;
    const NSInteger px = 256;
    size_t bytesPerRow = (size_t)px * 4;
    size_t total = bytesPerRow * (size_t)px;
    void *buffer = calloc(1, total);
    if (buffer == NULL) return nil;

    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(
        buffer, (size_t)px, (size_t)px, 8, bytesPerRow, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    if (ctx == NULL) {
        CGColorSpaceRelease(space);
        free(buffer);
        return nil;
    }

    // Fully transparent canvas (not white).
    CGContextSetBlendMode(ctx, kCGBlendModeCopy);
    CGContextClearRect(ctx, CGRectMake(0, 0, edge, edge));
    CGContextSetBlendMode(ctx, kCGBlendModeNormal);

    // Draw the source icon, aspect-fit, preserving its alpha.
    NSSize srcSize = source.size;
    if (srcSize.width < 1 || srcSize.height < 1) srcSize = NSMakeSize(edge, edge);
    CGFloat scale = MIN(edge / srcSize.width, edge / srcSize.height);
    CGSize drawSize = CGSizeMake(srcSize.width * scale, srcSize.height * scale);
    CGRect drawRect = CGRectMake((edge - drawSize.width) * 0.5,
                                 (edge - drawSize.height) * 0.5,
                                 drawSize.width, drawSize.height);

    NSGraphicsContext *previous = [NSGraphicsContext currentContext];
    NSGraphicsContext *gfx =
        [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:NO];
    [NSGraphicsContext setCurrentContext:gfx];
    [source drawInRect:NSRectFromCGRect(drawRect)
              fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver
              fraction:1.0
        respectFlipped:NO
                 hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
    [NSGraphicsContext setCurrentContext:previous];

    CGImageRef sourceCG = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    CGColorSpaceRelease(space);
    free(buffer);
    if (sourceCG == NULL) return nil;

    CIImage *input = [[CIImage alloc] initWithCGImage:sourceCG];
    CGImageRelease(sourceCG);
    if (input == nil) return nil;

    CIFilter *sat = [CIFilter filterWithName:@"CIColorControls"];
    [sat setValue:input forKey:kCIInputImageKey];
    [sat setValue:@(saturation) forKey:kCIInputSaturationKey];
    [sat setValue:@0 forKey:kCIInputBrightnessKey];
    [sat setValue:@1 forKey:kCIInputContrastKey];
    CIImage *afterSat = sat.outputImage;
    if (afterSat == nil) return nil;

    CIFilter *hue = [CIFilter filterWithName:@"CIHueAdjust"];
    [hue setValue:afterSat forKey:kCIInputImageKey];
    [hue setValue:@(hueRadians) forKey:kCIInputAngleKey];
    CIImage *shifted = hue.outputImage;
    if (shifted == nil) return nil;

    // Keep shifted colours, masked by the original alpha so transparent
    // corners stay invisible even if a filter dirtied A=0 pixels.
    CIFilter *sourceIn = [CIFilter filterWithName:@"CISourceInCompositing"];
    [sourceIn setValue:shifted forKey:kCIInputImageKey];
    [sourceIn setValue:input forKey:kCIInputBackgroundImageKey];
    CIImage *output = sourceIn.outputImage ?: shifted;

    CGRect extent = input.extent;
    if (CGRectIsInfinite(extent) || CGRectIsEmpty(extent)) {
        extent = CGRectMake(0, 0, edge, edge);
    }

    CGColorSpaceRef outSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef cg = [self.dockIconContext createCGImage:output
                                               fromRect:extent
                                                 format:kCIFormatRGBA8
                                             colorSpace:outSpace];
    CGColorSpaceRelease(outSpace);
    if (cg == NULL) {
        cg = [self.dockIconContext createCGImage:output fromRect:extent];
    }
    if (cg == NULL) return nil;

    NSImage *result = [[NSImage alloc] initWithCGImage:cg size:NSMakeSize(edge, edge)];
    CGImageRelease(cg);
    return result;
}

- (NSView *)buildSidebar {
    NSString *version = [[NSBundle mainBundle]
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";

    NSTextField *title = [self label:@"SlopNet" size:20 grey:NO];
    title.font = [NSFont boldSystemFontOfSize:20];

    self.statusDot = [self label:@"●" size:13 grey:NO];
    self.statusText = [self label:@"Checking…" size:12 grey:YES];
    NSStackView *status = [NSStackView stackViewWithViews:@[self.statusDot, self.statusText]];
    status.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    status.alignment = NSLayoutAttributeCenterY;
    status.spacing = 6;

    NSButton *newButton = [self sidebarButton:@"＋   New"
                                       action:@selector(newConversation:)];

    NSTextField *historyTitle = [self label:@"RECENT REQUESTS" size:10 grey:YES];
    self.historyStack = [NSStackView stackViewWithViews:@[]];
    self.historyStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.historyStack.alignment = NSLayoutAttributeLeading;
    self.historyStack.spacing = 1;

    // A spacer that expands, so Settings sits at the BOTTOM of the sidebar
    // where people expect to find it.
    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];

    self.settingsToggle = [self sidebarButton:@"⚙   Settings"
                                       action:@selector(openSettings:)];
    NSButton *providersButton = [self sidebarButton:@"◫   Providers"
                                            action:@selector(showProviders:)];

    NSStackView *sidebar = [NSStackView stackViewWithViews:@[
        title, status,
        [self separator],
        newButton,
        historyTitle, self.historyStack,
        spacer,
        [self separator],
        providersButton,
        self.settingsToggle,
        [self label:[NSString stringWithFormat:@"v%@", version] size:10 grey:YES]]];
    sidebar.orientation = NSUserInterfaceLayoutOrientationVertical;
    sidebar.alignment = NSLayoutAttributeLeading;
    sidebar.spacing = 6;
    sidebar.edgeInsets = NSEdgeInsetsMake(18, 12, 14, 12);
    [sidebar setHuggingPriority:NSLayoutPriorityDefaultLow
                 forOrientation:NSLayoutConstraintOrientationVertical];
    // Every row fills the sidebar's width. Without this, rows keep their
    // natural size and the panel looks ragged — and separators appear as
    // stubs — however the divider is dragged.
    for (NSView *rowView in sidebar.arrangedSubviews) {
        [rowView.widthAnchor constraintEqualToAnchor:sidebar.widthAnchor
                                           constant:-24].active = YES;
    }
    [self.historyStack.widthAnchor constraintEqualToAnchor:sidebar.widthAnchor
                                                 constant:-24].active = YES;
    return sidebar;
}

- (NSView *)buildMain {
    self.console = [[SlopNetConsole alloc] initWithFrame:NSZeroRect];
    self.console.delegate = self;
    self.console.translatesAutoresizingMaskIntoConstraints = NO;

    // The chat bar. What it does depends on what is happening: answer the
    // running program's question, or describe the thing you want built.
    // It starts comfortably large, grows with a long request, then scrolls
    // rather than stealing the entire console.
    self.projectName = [self field:@"project name" value:nil];
    [self.projectName.widthAnchor constraintEqualToConstant:130].active = YES;

    self.modePicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.modePicker addItemWithTitle:@"Chat"];
    [self.modePicker addItemWithTitle:@"Build"];
    self.modePicker.target = self;
    self.modePicker.action = @selector(modeChanged:);
    self.modePicker.translatesAutoresizingMaskIntoConstraints = NO;
    [self.modePicker.widthAnchor constraintEqualToConstant:76].active = YES;

    self.modelPicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.modelPicker.target = self;
    self.modelPicker.action = @selector(modelChanged:);
    self.modelPicker.translatesAutoresizingMaskIntoConstraints = NO;
    [self.modelPicker.widthAnchor constraintEqualToConstant:180].active = YES;
    [self refreshModelPicker];
    self.entry = [[SlopNetEntryView alloc] initWithFrame:NSZeroRect];
    self.entry.delegate = self;
    self.entry.richText = NO;
    self.entry.allowsUndo = YES;
    self.entry.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.entry.textContainerInset = NSMakeSize(8, 8);
    self.entry.prompt = @"Describe what you want built… Return sends · Shift-Return adds a line";
    self.entry.automaticQuoteSubstitutionEnabled = NO;
    self.entry.automaticDashSubstitutionEnabled = NO;
    self.entry.automaticTextReplacementEnabled = NO;
    self.entry.minSize = NSMakeSize(0, 0);
    self.entry.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    self.entry.verticallyResizable = YES;
    self.entry.horizontallyResizable = NO;
    self.entry.textContainer.widthTracksTextView = YES;

    self.entryScroller = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.entryScroller.hasVerticalScroller = NO;
    self.entryScroller.autohidesScrollers = YES;
    self.entryScroller.borderType = NSBezelBorder;
    self.entryScroller.documentView = self.entry;
    self.entryScroller.translatesAutoresizingMaskIntoConstraints = NO;
    self.entryHeight = [self.entryScroller.heightAnchor constraintEqualToConstant:56];
    self.entryHeight.active = YES;
    [self.entryScroller setContentHuggingPriority:NSLayoutPriorityDefaultLow
                           forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.sendButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    self.sendButton.title = @"Build it";
    self.sendButton.bezelStyle = NSBezelStyleRounded;
    self.sendButton.target = self;
    self.sendButton.action = @selector(sendPressed:);

    NSStackView *chatBar = [NSStackView stackViewWithViews:@[
        self.modePicker, self.modelPicker, self.projectName, self.entryScroller, self.sendButton]];
    chatBar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    chatBar.alignment = NSLayoutAttributeTop;
    chatBar.spacing = 8;
    chatBar.translatesAutoresizingMaskIntoConstraints = NO;

    // Plain constraints rather than a stack here: two children, and the
    // console must take every spare pixel at any window size.
    NSView *main = [[NSView alloc] initWithFrame:NSZeroRect];
    [main addSubview:self.console];
    [main addSubview:chatBar];
    [NSLayoutConstraint activateConstraints:@[
        [self.console.topAnchor constraintEqualToAnchor:main.topAnchor constant:16],
        [self.console.leadingAnchor constraintEqualToAnchor:main.leadingAnchor constant:16],
        [self.console.trailingAnchor constraintEqualToAnchor:main.trailingAnchor constant:-16],

        [chatBar.topAnchor constraintEqualToAnchor:self.console.bottomAnchor constant:10],
        [chatBar.leadingAnchor constraintEqualToAnchor:main.leadingAnchor constant:16],
        [chatBar.trailingAnchor constraintEqualToAnchor:main.trailingAnchor constant:-16],
        [chatBar.bottomAnchor constraintEqualToAnchor:main.bottomAnchor constant:-16],
    ]];
    return main;
}

#pragma mark - one place decides what the window shows

- (BOOL)isReady {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kReadyKey] &&
           self.host.length > 0;
}

- (BOOL)isChatMode { return self.modePicker.indexOfSelectedItem == 0; }

- (void)refreshState {
    BOOL ready = [self isReady];
    BOOL chat = [self isChatMode];
    if (ready) {
        self.statusDot.textColor = [NSColor systemGreenColor];
        self.statusText.stringValue = [NSString stringWithFormat:@"Ready — %@", self.host];
    } else {
        self.statusDot.textColor = [NSColor systemGrayColor];
        self.statusText.stringValue = @"No server yet";
    }
    self.modePicker.enabled = ready && !self.busy;
    self.modelPicker.hidden = !ready || !chat;
    self.modelPicker.enabled = ready && !self.busy && chat;
    self.projectName.hidden = !ready || chat;
    if (self.busy) {
        self.entry.prompt = @"Type your answer here, then press Return (for example: y)";
        self.sendButton.title = @"Answer";
        self.entry.editable = YES;
    } else if (ready && chat) {
        self.entry.prompt = @"Ask the local guide about setup or how to prepare a request…";
        self.sendButton.title = @"Ask";
        self.entry.editable = YES;
    } else if (ready && self.plannedProjectName.length > 0) {
        self.entry.prompt = @"Read the plan above. Start only when you are ready for coding agents.";
        self.sendButton.title = @"Start approved build";
        self.entry.editable = NO;
    } else if (ready) {
        self.entry.prompt =
            @"Describe what you want built… SlopNet will make a plan, then stop.";
        self.sendButton.title = @"Make a plan";
        self.entry.editable = YES;
    } else {
        self.entry.prompt = @"Open Settings to connect a server first";
        self.sendButton.title = @"Set up";
        self.entry.editable = YES;
    }
    [self resizeEntry];
    [self rebuildHistory];
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    [self refreshState];
}

- (void)rebuildHistory {
    for (NSView *view in [self.historyStack.arrangedSubviews copy]) {
        [self.historyStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    NSArray<NSURL *> *conversations = [self conversationURLs];
    if (conversations.count == 0) {
        [self.historyStack addArrangedSubview:[self label:@"nothing yet" size:11 grey:YES]];
        return;
    }
    NSUInteger visible = MIN(conversations.count, 12);
    for (NSUInteger index = 0; index < visible; index++) {
        NSURL *url = conversations[index];
        NSButton *button = [self sidebarButton:[@"•  " stringByAppendingString:
                                           [self conversationTitle:url]]
                                          action:@selector(openConversation:)];
        button.identifier = url.path;
        [self.historyStack addArrangedSubview:button];
    }
}

- (NSURL *)historyDirectory {
    NSURL *support = [[NSFileManager defaultManager]
        URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return [support URLByAppendingPathComponent:@"SlopNet/history" isDirectory:YES];
}

- (NSArray<NSURL *> *)conversationURLs {
    NSURL *directory = [self historyDirectory];
    NSArray<NSURL *> *items = [[NSFileManager defaultManager]
        contentsOfDirectoryAtURL:directory
        includingPropertiesForKeys:@[NSURLContentModificationDateKey, NSURLIsRegularFileKey]
                           options:NSDirectoryEnumerationSkipsHiddenFiles error:nil] ?: @[];
    NSPredicate *markdown = [NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *_) {
        NSNumber *regular = nil;
        [url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
        return regular.boolValue && [url.pathExtension.lowercaseString isEqualToString:@"md"];
    }];
    return [[items filteredArrayUsingPredicate:markdown]
        sortedArrayUsingComparator:^NSComparisonResult(NSURL *left, NSURL *right) {
            NSDate *leftDate = nil;
            NSDate *rightDate = nil;
            [left getResourceValue:&leftDate forKey:NSURLContentModificationDateKey error:nil];
            [right getResourceValue:&rightDate forKey:NSURLContentModificationDateKey error:nil];
            NSDate *safeLeft = leftDate ?: [NSDate distantPast];
            NSDate *safeRight = rightDate ?: [NSDate distantPast];
            return [safeRight compare:safeLeft];
        }];
}

- (NSString *)conversationTitle:(NSURL *)url {
    NSString *text = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    NSString *first = lines.firstObject ?: @"";
    if ([first hasPrefix:@"# "] && first.length > 2) return [first substringFromIndex:2];
    return @"untitled request";
}

- (void)newConversation:(id)sender {
    self.conversationURL = nil;
    self.plannedProjectName = nil;
    self.activeProjectName = nil;
    [self.modePicker selectItemAtIndex:0];
    self.projectName.stringValue = @"";
    self.entry.string = @"";
    [self.console note:
        @"\nNew chat. Ask the local guide about setup, or choose Build when you are ready to make a plan."];
    [self showReadyBlock];
    [self.window makeFirstResponder:self.entry];
    [self resizeEntry];
}

- (void)openConversation:(NSButton *)sender {
    NSURL *url = [NSURL fileURLWithPath:sender.identifier ?: @""];
    NSString *text = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
    if (text.length == 0) return;
    self.conversationURL = url;
    self.plannedProjectName = nil;
    [self.modePicker selectItemAtIndex:1];
    self.projectName.stringValue = [self conversationTitle:url];
    NSRange marker = [text rangeOfString:@"## Request\n\n" options:NSBackwardsSearch];
    if (marker.location != NSNotFound) {
        NSUInteger start = NSMaxRange(marker);
        NSRange next = [text rangeOfString:@"\n\n## " options:0
                                     range:NSMakeRange(start, text.length - start)];
        NSUInteger end = next.location == NSNotFound ? text.length : next.location;
        self.entry.string = [[text substringWithRange:NSMakeRange(start, end - start)]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    [self.console note:@"\nOpened a local request note. Its project request is back in the box; edit it or add a new one."];
    [self.window makeFirstResponder:self.entry];
    [self resizeEntry];
}

// History intentionally records only an idle project request. It never
// captures console output or an answer to a live prompt: either could contain
// a VPS password or provider information.
- (void)rememberRequest:(NSString *)idea project:(NSString *)name {
    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *directory = [self historyDirectory];
    NSError *error = nil;
    if (![files createDirectoryAtURL:directory withIntermediateDirectories:YES
                          attributes:@{NSFilePosixPermissions: @0700} error:&error]) {
        [self.console note:@"\nSlopNet could not save this request history on this Mac. The build can still continue."];
        return;
    }

    NSString *existing = self.conversationURL
        ? [NSString stringWithContentsOfURL:self.conversationURL encoding:NSUTF8StringEncoding error:nil]
        : nil;
    BOOL sameProject = existing.length > 0 &&
        [[self conversationTitle:self.conversationURL] isEqualToString:name];
    if (!sameProject) {
        self.conversationURL = [directory URLByAppendingPathComponent:
            [NSString stringWithFormat:@"request-%@.md", NSUUID.UUID.UUIDString.lowercaseString]];
        existing = [NSString stringWithFormat:@"# %@\n\nCreated locally by SlopNet.\n", name];
    }
    NSString *updated = [NSString stringWithFormat:@"%@\n## Request\n\n%@\n", existing, idea];
    if (![updated writeToURL:self.conversationURL atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        [self.console note:@"\nSlopNet could not save this request history on this Mac. The build can still continue."];
        return;
    }
    [files setAttributes:@{NSFilePosixPermissions: @0600}
             ofItemAtPath:self.conversationURL.path error:nil];
    [self rebuildHistory];
}

#pragma mark - remembering (never a password, never inside the repo)

// Only the three details from your provider's welcome email are kept, in
// macOS's own preferences for this app. A password is NEVER stored: it goes
// from the console straight to your server. The SSH key that setup creates
// stays in the macOS Keychain. Nothing is written into the SlopNet folder,
// so none of it can be committed or uploaded by accident.
- (void)remember {
    NSUserDefaults *store = [NSUserDefaults standardUserDefaults];
    [store setObject:self.host ?: @"" forKey:kHostKey];
    [store setObject:self.username ?: @"root" forKey:kUserKey];
    [store setObject:self.port ?: @"22" forKey:kPortKey];
}

- (void)recall {
    NSUserDefaults *store = [NSUserDefaults standardUserDefaults];
    self.host = [store stringForKey:kHostKey] ?: @"";
    self.username = [store stringForKey:kUserKey] ?: @"root";
    self.port = [store stringForKey:kPortKey] ?: @"22";

    if ([self isReady]) {
        [self.console note:[NSString stringWithFormat:
            @"Your server (%@) is set up and ready.\n"
            @"Chat uses only your private local model. Choose Build only when you want a paid coding app to make a plan. "
            @"Your local request notes appear on the left.", self.host]];
    } else {
        [self.console note:@"Welcome. The setup guide is opening now.\n"
                           @"First connect your server; then SlopNet can install and prove its private local guide."];
    }
}

#pragma mark - the ready block (what the console shows when nothing is running)

/// How wide the panels may be: narrower than the console, so they read as
/// blocks on the field rather than full-width bars.
- (NSUInteger)panelWidth {
    NSUInteger columns = self.console.columns;
    return MAX((NSUInteger)44, MIN(columns - 2, (NSUInteger)66));
}

/// The coding apps from tools.json, as provider ids. Only real, listed
/// tools — nothing invented, and unmapped ids are simply left out.
- (NSArray<NSString *> *)codingToolProviders {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"tools" ofType:@"json"];
    NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
    NSDictionary *root = data
        ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSArray *tools = [root isKindOfClass:NSDictionary.class] ? root[@"tools"] : nil;
    NSMutableArray<NSString *> *providers = [NSMutableArray array];
    for (NSDictionary *tool in tools) {
        if (![tool isKindOfClass:NSDictionary.class]) continue;
        NSString *provider = [SlopNetBrand providerForTool:tool[@"id"]];
        if (provider != nil && ![providers containsObject:provider]) {
            [providers addObject:provider];
        }
    }
    return providers;
}

/// The StormCode-style status block: a crimson header, a filled panel for
/// the private local model with an animated action glyph, and a row of the
/// coding apps on their own brand surfaces. Compact on purpose — the full
/// 38-logo sheet lives behind the Providers button, not the front door.
- (NSString *)readyBlockANSI {
    NSUInteger width = [self panelWidth];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    [parts addObject:[SlopNetBrand headerANSI:@"SlopNet" width:width]];

    NSString *model = self.localModelName;
    NSString *provider = [SlopNetBrand providerForLocalModel:model] ?: @"ibm_granite";
    BOOL known = model.length > 0;
    NSArray<NSString *> *detail = known
        ? @[model, @"private · no API key · no open port"]
        : @[@"not set up yet — open Settings", @"Chat needs the private local guide"];
    [parts addObject:[SlopNetBrand panelANSIForProvider:provider
                                                 title:known ? @"Granite — local guide"
                                                             : @"Granite — local guide (not set up)"
                                                detail:detail
                                                action:self.actionConcept
                                                 frame:self.actionTick
                                                 width:width]];

    NSArray<NSString *> *tools = [self codingToolProviders];
    if (tools.count > 0) {
        [parts addObject:[SlopNetBrand headerANSI:@"Coding apps" width:width]];
        [parts addObject:[SlopNetBrand panelStripANSIForProviders:tools width:width]];
    }
    return [parts componentsJoinedByString:@"\n"];
}

- (void)showReadyBlock {
    self.actionConcept = @"think";
    self.actionTick = 0;
    self.readyBlockToken = [self.console noteReplaceable:[self readyBlockANSI]];
    [self startActionAnimation];
}

#pragma mark - the animated action glyph

- (void)startActionAnimation {
    [self.actionTimer invalidate];
    // ~8 fps, the rate scripts/show_frames.py plays these at. The block holds
    // the delegate weakly: a repeating timer retains its block, so a strong
    // self here would keep the window alive after it closed.
    __weak typeof(self) weakSelf = self;
    self.actionTimer = [NSTimer scheduledTimerWithTimeInterval:0.125
                                                       repeats:YES
                                                         block:^(NSTimer *timer) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) { [timer invalidate]; return; }
        [strongSelf tickActionAnimation:timer];
    }];
}

- (void)tickActionAnimation:(NSTimer *)timer {
    self.actionTick++;
    if (self.busy) {
        // A run owns the screen: the glyph lives in the status line, which
        // never scrolls and never fights the program's cursor.
        NSString *glyph = [SlopNetBrand actionGlyph:self.actionConcept ?: @"think"
                                              frame:self.actionTick
                                              cells:2];
        [self.console setStatusText:self.actionCaption ?: @"Working…"
                              glyph:glyph
                               tint:[SlopNetBrand crimsonColor]];
        return;
    }
    // Idle: redraw the ready block's own lines in place. Once they scroll out
    // of the buffer the console says so, and the animation stops rather than
    // redrawing rows that now belong to something else.
    if (self.readyBlockToken < 0) { [timer invalidate]; self.actionTimer = nil; return; }
    if (![self.console replaceLinesFromToken:self.readyBlockToken with:[self readyBlockANSI]]) {
        self.readyBlockToken = -1;
        [timer invalidate];
        self.actionTimer = nil;
    }
}

/// Name what is happening while a program runs, and animate it.
- (void)beginActivity:(NSString *)concept caption:(NSString *)caption {
    self.actionConcept = concept;
    self.actionCaption = caption;
    self.actionTick = 0;
    self.readyBlockToken = -1;      // the ready block is history now
    [self startActionAnimation];
}

#pragma mark - actions

- (void)openSettings:(id)sender {
    self.settings = [[SlopNetSettings alloc] initWithHost:self.host
                                                     port:self.port
                                                     user:self.username
                                                connected:[self isReady]];
    self.settings.window.title = [self isReady] ? @"Settings" : @"Set up SlopNet — step 1 of 2";
    self.settings.delegate = self;
    [self.settings presentFrom:self.window];
}

- (void)openLocalGuideSettings {
    self.settings = [[SlopNetSettings alloc] initWithHost:self.host
                                                     port:self.port
                                                     user:self.username
                                                connected:YES];
    self.settings.window.title = @"Set up SlopNet — step 2 of 2";
    self.settings.delegate = self;
    [self.settings presentFrom:self.window];
}

- (void)openServerHelp:(id)sender {
    [self.console note:
        @"\nSlopNet works with ANY computer you can reach over SSH:\n"
        @"  • a rented server (Hetzner, Contabo, Hostinger and many others)\n"
        @"  • a dedicated machine you already pay for\n"
        @"  • a home server, or a Raspberry Pi on your own network\n"
        @"You need three things from it: its address, a login name, and the "
        @"port (almost always 22). Put them in Settings, bottom left.\n"
        @"A small Linux machine is plenty to start with."];
}

- (void)clearConsole:(id)sender {
    [self.console clear];
    [self showReadyBlock];
}

/// The whole mapped provider set, on demand. Deliberately not the default
/// view: the operator asked for the demos' visual system, not a collage of
/// every logo on every launch.
- (void)showProviders:(id)sender {
    NSUInteger width = self.console.columns - 2;
    [self.console note:[SlopNetBrand providerSheetANSIWithWidth:width]];
    [self.console note:[SlopNetBrand colorFontActive]
        ? @"Colour badge font active — these are the real marks."
        : @"Colour badge font not active — these are portable Unicode marks."];
    [self.console note:[SlopNetBrand colourCheckANSIWithWidth:width]];
    self.readyBlockToken = -1;
}

- (void)resizeEntry {
    if (self.entry == nil || self.entryHeight == nil) return;
    [self.entry.layoutManager ensureLayoutForTextContainer:self.entry.textContainer];
    CGFloat textHeight = [self.entry.layoutManager usedRectForTextContainer:self.entry.textContainer].size.height + 16;
    CGFloat maximum = 168;
    self.entryHeight.constant = MIN(MAX(textHeight, 56), maximum);
    self.entryScroller.hasVerticalScroller = textHeight > maximum;
}

- (void)modeChanged:(id)sender {
    self.plannedProjectName = nil;
    [self refreshState];
    [self.window makeFirstResponder:self.entry];
}

- (void)refreshModelPicker {
    if (self.modelPicker == nil) return;
    NSString *provider = [SlopNetBrand providerForLocalModel:self.localModelName];
    NSString *badge = provider ? [SlopNetBrand markForProvider:provider] : nil;
    NSString *title = self.localModelName.length > 0
        ? [NSString stringWithFormat:@"%@ — local", self.localModelName]
        : @"Local model — set up in Settings";
    if (badge != nil) title = [NSString stringWithFormat:@"%@ %@", badge, title];
    [self.modelPicker removeAllItems];
    [self.modelPicker addItemWithTitle:title];
    // Menus draw in the menu font, which has no badge glyphs; give the badge
    // characters the console face so the real logo shows in the picker.
    if (badge != nil && [SlopNetBrand colorFontActive]) {
        NSMenuItem *item = [self.modelPicker itemAtIndex:0];
        NSMutableAttributedString *styled = [[NSMutableAttributedString alloc]
            initWithString:title
                attributes:@{NSFontAttributeName: [NSFont menuFontOfSize:0]}];
        [styled addAttribute:NSFontAttributeName
                       value:[SlopNetBrand consoleFontOfSize:13]
                       range:NSMakeRange(0, badge.length)];
        item.attributedTitle = styled;
    }
    [self.modelPicker addItemWithTitle:@"Choose local model in Settings…"];
    [self.modelPicker selectItemAtIndex:0];
}

- (void)modelChanged:(id)sender {
    if (self.modelPicker.indexOfSelectedItem != 1) return;
    [self.modelPicker selectItemAtIndex:0];
    [self openSettings:nil];
}

- (void)textDidChange:(NSNotification *)notification { [self resizeEntry]; }

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (commandSelector == @selector(insertNewline:)) {
        NSEvent *event = NSApp.currentEvent;
        if ((event.modifierFlags & NSEventModifierFlagShift) != 0) return NO;
        [self sendPressed:textView];
        return YES;
    }
    return NO;
}

- (BOOL)matches:(NSString *)value pattern:(NSString *)pattern {
    NSRange range = NSMakeRange(0, value.length);
    NSRegularExpression *expression =
        [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    return [expression firstMatchInString:value options:0 range:range] != nil;
}

- (BOOL)connectionValid {
    if (![self matches:self.host ?: @"" pattern:@"^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$"] ||
        ![self matches:self.username ?: @"" pattern:@"^[A-Za-z_][A-Za-z0-9_-]{0,31}$"] ||
        self.port.integerValue < 1 || self.port.integerValue > 65535) {
        [self.console note:@"\nCheck your server's address and login name in Settings. "
                           @"The port is almost always 22."];
        return NO;
    }
    return YES;
}

- (NSString *)helper:(NSString *)name {
    return [[NSBundle mainBundle] pathForResource:name ofType:@"sh"];
}

#pragma mark - settings window asks, this window does

- (void)settings:(SlopNetSettings *)settings
   connectToHost:(NSString *)host port:(NSString *)port user:(NSString *)user {
    self.host = host;
    self.port = port.length ? port : @"22";
    self.username = user.length ? user : @"root";
    [self remember];
    if (self.busy || ![self connectionValid]) return;
    NSString *script = [self helper:@"slopnet-vps-onboard"];
    if (script == nil) {
        [self.console note:@"The server setup helper is missing from this app. Build it again."];
        return;
    }
    [self.console note:[SlopNetBrand headerANSI:@"Preparing your server"
                                          width:[self panelWidth]]];
    self.setupRunning = YES;
    [self beginActivity:@"search" caption:@"Checking your server…"];
    [self setBusy:YES];
    if (![self.console runExecutable:@"/bin/bash"
                           arguments:@[script, self.host, self.port, self.username]]) {
        self.setupRunning = NO;
        [self setBusy:NO];
    }
}

- (void)settings:(SlopNetSettings *)settings runOnServer:(NSString *)command
           title:(NSString *)title {
    if (self.busy || ![self connectionValid]) return;
    [self.console note:[SlopNetBrand headerANSI:title width:[self panelWidth]]];
    [self beginActivity:@"search" caption:title];
    [self setBusy:YES];
    NSString *target = [NSString stringWithFormat:@"%@@%@", self.username, self.host];
    // A real terminal on the far end, so a sudo password prompt works.
    if (![self.console runExecutable:@"/usr/bin/ssh"
                           arguments:@[@"-t", @"-p", self.port,
                                       @"-o", @"StrictHostKeyChecking=accept-new",
                                       target, command]]) {
        [self setBusy:NO];
    }
}

- (void)settingsDidForget:(SlopNetSettings *)settings {
    NSUserDefaults *store = [NSUserDefaults standardUserDefaults];
    for (NSString *key in @[kHostKey, kUserKey, kPortKey, kReadyKey]) {
        [store removeObjectForKey:key];
    }
    self.host = @"";
    self.username = @"root";
    self.port = @"22";
    [self.console note:@"\nForgotten on this Mac. Your server itself is untouched, and "
                       @"no password was ever stored."];
    [self refreshState];
}

- (void)settingsCheckConnection:(SlopNetSettings *)settings { [self checkConnection:nil]; }

- (void)settingsClearConsole:(SlopNetSettings *)settings { [self clearConsole:nil]; }

- (void)settingsShowServerHelp:(SlopNetSettings *)settings { [self openServerHelp:nil]; }

- (void)settings:(SlopNetSettings *)settings setupLocalHelperModel:(NSString *)model {
    if (self.busy || ![self connectionValid]) return;
    NSString *script = [self helper:@"slopnet-vps-local-helper"];
    if (script == nil) {
        [self.console note:@"The local-helper setup is missing from this app. Build it again."];
        return;
    }
    NSString *helperProvider = [SlopNetBrand providerForLocalModel:model];
    [self.console note:[SlopNetBrand headerANSI:@"Preparing the local guide"
                                          width:[self panelWidth]]];
    if (helperProvider != nil) {
        [self.console note:[SlopNetBrand panelANSIForProvider:helperProvider
                                                       title:nil
                                                      detail:@[model]
                                                      action:nil
                                                       frame:0
                                                       width:[self panelWidth]]];
    }
    [self.console note:
        @"This happens only on your server. It will show the real capacity before "
         "it downloads anything, keeps this small helper to a 4K context and a "
         "15-minute test, and never opens a model port."];
    self.localHelperRunning = YES;
    [self beginActivity:@"db-research" caption:@"Preparing the local guide…"];
    [self setBusy:YES];
    if (![self.console runExecutable:@"/bin/bash"
                           arguments:@[script, self.host, self.port, self.username, model]]) {
        [self setBusy:NO];
    }
}

- (void)refreshLocalModelName {
    if (![self isReady] || self.host.length == 0) {
        self.localModelName = nil;
        [self refreshModelPicker];
        return;
    }
    // A quiet read-only check. It never starts a model, calls a coding CLI,
    // asks for a password, or changes the VPS. A non-root login may not be
    // able to read this private file; chat itself will then explain what is
    // missing in the visible console.
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ssh"];
    task.arguments = @[@"-p", self.port,
                       @"-o", @"BatchMode=yes",
                       @"-o", @"ConnectTimeout=10",
                       @"-o", @"StrictHostKeyChecking=accept-new",
                       [NSString stringWithFormat:@"%@@%@", self.username, self.host],
                       @"home=$(getent passwd slopnet | cut -d: -f6); test -n \"$home\" && sed -n 's/^SLOPNET_LOCAL_HELPER_MODEL=//p' \"$home/.local/share/slopnet/local-helper.env\" 2>/dev/null | head -n 1"];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSPipe pipe];
    __weak typeof(self) weakSelf = self;
    task.terminationHandler = ^(NSTask *finished) {
        NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        NSString *model = [text stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (strongSelf == nil) return;
            if (finished.terminationStatus == 0 &&
                [strongSelf matches:model pattern:@"^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*(:[A-Za-z0-9][A-Za-z0-9._-]*)?$"]) {
                strongSelf.localModelName = model;
            } else {
                strongSelf.localModelName = nil;
            }
            [strongSelf refreshModelPicker];
        });
    };
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        self.localModelName = nil;
        [self refreshModelPicker];
    }
}

- (void)checkConnection:(id)sender {
    if (self.busy || ![self connectionValid]) return;
    [self.console note:[SlopNetBrand headerANSI:@"Checking the connection"
                                          width:[self panelWidth]]];
    [self beginActivity:@"search" caption:@"Reaching your server…"];
    [self setBusy:YES];
    NSString *target = [NSString stringWithFormat:@"%@@%@", self.username, self.host];
    if (![self.console runExecutable:@"/usr/bin/ssh"
                           arguments:@[@"-p", self.port,
                                       @"-o", @"BatchMode=yes",
                                       @"-o", @"ConnectTimeout=10",
                                       @"-o", @"StrictHostKeyChecking=accept-new",
                                       target, @"echo SlopNet reached your server."]]) {
        [self setBusy:NO];
    }
}

/// The chat box has three deliberately separate paths. Running → the text
/// answers the visible program. Chat → one finite, private local-model reply.
/// Build → an explicit plan, then a second explicit approval before agents run.
- (void)sendPressed:(id)sender {
    if (self.busy) {
        [self.console sendLine:self.entry.string];
        self.entry.string = @"";
        [self resizeEntry];
        return;
    }
    if (![self isReady]) {
        [self.console note:@"\nConnect a server first — press Settings, bottom left."];
        [self openSettings:nil];
        return;
    }
    NSString *idea = [self.entry.string stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([self isChatMode]) {
        if (idea.length == 0) {
            [self.console note:@"\nAsk the local guide a question first."];
            return;
        }
        NSString *script = [self helper:@"slopnet-vps-chat"];
        if (script == nil) {
            [self.console note:@"The private-chat helper is missing from this app. Build it again."];
            return;
        }
        NSString *chatProvider =
            [SlopNetBrand providerForLocalModel:self.localModelName] ?: @"ibm_granite";
        [self.console note:[SlopNetBrand headerANSI:@"Private local-model chat"
                                              width:[self panelWidth]]];
        [self.console note:[SlopNetBrand panelANSIForProvider:chatProvider
                                                       title:nil
                                                      detail:@[idea]
                                                      action:@"think"
                                                       frame:0
                                                       width:[self panelWidth]]];
        [self.console note:
            @"This reply uses only the selected local model on your VPS. "
             "It cannot start a plan, coding agent, or build."];
        self.entry.string = @"";
        [self resizeEntry];
        [self beginActivity:@"think" caption:@"The local guide is thinking…"];
        [self setBusy:YES];
        if (![self.console runExecutable:@"/bin/bash"
                               arguments:@[script, self.host, self.port, self.username, idea]]) {
            [self setBusy:NO];
        }
        return;
    }
    if (self.plannedProjectName.length > 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Start coding agents?";
        alert.informativeText = [NSString stringWithFormat:
            @"You approved the plan for %@. This starts the multi-agent coding run on your VPS and spends from the proved coding subscription. Agents may edit only that project; walls and its test command decide what can merge.",
            self.plannedProjectName];
        [alert addButtonWithTitle:@"Start coding agents"];
        [alert addButtonWithTitle:@"Keep plan only"];
        if ([alert runModal] != NSAlertFirstButtonReturn) return;
        NSString *script = [self helper:@"slopnet-vps-build"];
        if (script == nil) {
            [self.console note:@"The approved-build helper is missing from this app. Build it again."];
            return;
        }
        [self.console note:[SlopNetBrand headerANSI:@"Starting approved build"
                                              width:[self panelWidth]]];
        [self.console note:[NSString stringWithFormat:
            @"%@ — you explicitly approved this coding run.", self.plannedProjectName]];
        self.approvedBuildRunning = YES;
        self.activeProjectName = self.plannedProjectName;
        [self beginActivity:@"write" caption:@"Coding agents are working…"];
        [self setBusy:YES];
        if (![self.console runExecutable:@"/bin/bash"
                               arguments:@[script, self.host, self.port, self.username,
                                           self.plannedProjectName]]) {
            self.approvedBuildRunning = NO;
            [self setBusy:NO];
        }
        return;
    }
    NSString *name = [self.projectName.stringValue stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![self matches:name pattern:@"^[a-z0-9][a-z0-9-]{0,62}$"]) {
        [self.console note:@"\nGive the project a short name in the small box: lowercase "
                           @"letters, numbers and hyphens, like photo-sheet."];
        [self.window makeFirstResponder:self.projectName];
        return;
    }
    if (idea.length == 0) {
        [self.console note:@"\nSay what you want built, in one sentence."];
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Make a plan, then stop?";
    alert.informativeText = [NSString stringWithFormat:
        @"SlopNet will ask the proved coding app to make a plan for %@ on your VPS. This uses that coding subscription, but does not start coding agents or change project files. You will read the plan and explicitly approve any build afterwards.",
        name];
    [alert addButtonWithTitle:@"Make plan"];
    [alert addButtonWithTitle:@"Keep editing"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSString *script = [self helper:@"slopnet-vps-project"];
    if (script == nil) {
        [self.console note:@"The project helper is missing from this app. Build it again."];
        return;
    }
    [self rememberRequest:idea project:name];
    [self.console note:[SlopNetBrand headerANSI:@"Making a plan" width:[self panelWidth]]];
    [self.console note:[NSString stringWithFormat:@"%@ — %@", name, idea]];
    self.activeProjectName = name;
    self.planningRunning = YES;
    self.entry.string = @"";
    [self resizeEntry];
    [self beginActivity:@"think" caption:@"Planning…"];
    [self setBusy:YES];
    if (![self.console runExecutable:@"/bin/bash"
                           arguments:@[script, self.host, self.port,
                                       self.username, name, idea]]) {
        [self setBusy:NO];
    }
}

#pragma mark - console callbacks

- (void)console:(SlopNetConsole *)console finishedWithStatus:(int)status {
    // A server counts as ready only when SETUP itself finished cleanly —
    // not because someone typed an address. That is what makes the green
    // dot in the sidebar worth trusting.
    if (self.setupRunning) {
        self.setupRunning = NO;
        if (status == 0) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kReadyKey];
            [self.console note:@"Your server is ready. Step 2 is to install and prove the private local guide. "
                               @"It does not use your coding subscription."];
            [self refreshLocalModelName];
            dispatch_async(dispatch_get_main_queue(), ^{ [self openLocalGuideSettings]; });
        }
    }
    if (self.localHelperRunning) {
        self.localHelperRunning = NO;
        if (status == 0) {
            [self.console note:@"The private local guide is ready. Choose Chat to ask it about setup, or Build when you want a separate coding plan."];
            [self refreshLocalModelName];
        }
    }
    if (self.planningRunning) {
        self.planningRunning = NO;
        if (status == 0 && self.activeProjectName.length > 0) {
            self.plannedProjectName = self.activeProjectName;
            [self.console note:@"The plan is ready above. Read it. No coding agent has run. Choose Build and press Start approved build only when you want the multi-agent run to begin."];
        }
    }
    if (self.approvedBuildRunning) {
        self.approvedBuildRunning = NO;
        self.plannedProjectName = nil;
        if (status == 0) {
            [self.console note:@"The approved build finished. Read the result above; SlopNet kept only work that passed its walls and project tests."];
        }
    }
    [self setBusy:NO];
    if (status != 0) {
        [self.console note:@"Nothing was left half-done. Read the last few lines above, "
                           @"fix what they mention, and try again."];
    }
    // Back to the branded ready view, with a fresh animation token.
    [self showReadyBlock];
    [self.window makeFirstResponder:self.entry];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app { return YES; }

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self stopDockIconAnimation];
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        (void)argc;
        (void)argv;
        NSApplication *app = [NSApplication sharedApplication];
        SlopNetAppDelegate *delegate = [[SlopNetAppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
    }
    return 0;
}
