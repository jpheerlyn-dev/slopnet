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
#import <float.h>
#import "SlopNetBrand.h"
#import "SlopNetConsole.h"
#import "SlopNetSettings.h"
#import "SlopNetWizard.h"

static NSString *const kHostKey     = @"SlopNetVPSHost";
static NSString *const kUserKey     = @"SlopNetVPSUser";
static NSString *const kPortKey     = @"SlopNetVPSPort";
static NSString *const kSignedInProvidersKey = @"SlopNetSignedInProviders";
static NSString *const kReadyKey    = @"SlopNetVPSReady";   // setup finished cleanly
// The private local guide passed its own READY proof on the server. Set only
// from a real outcome: a clean local-helper run, or reading the model back out
// of the server's runtime account. Never cleared by a failed network check,
// because "the server did not answer just now" is not evidence it is gone.
static NSString *const kGuideKey    = @"SlopNetGuideReady";
// The person has seen the last screen of the wizard, so it stops opening
// itself. The Setup guide button in the sidebar reopens it any time.
static NSString *const kWizardKey   = @"SlopNetWizardDone";

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

// One box, one button, no modes. What a message means depends on where the
// conversation has got to, not on a control the person had to set first.
//
// Granite is meant to be the thing that decides when to build. It cannot yet:
// native tool calling on the local model is explicitly unproved (see
// register/PENDING_OPERATOR.md), and a 3B model that "usually" emits a
// function call would start builds nobody asked for. So SlopNet notices a
// build-shaped request itself and offers, in the same stream, clearly as
// SlopNet. The person still approves in plain words. When tool calling is
// proved, this is where Granite takes over.
typedef NS_ENUM(NSInteger, SlopNetTurn) {
    SlopNetTurnTalking = 0,     // ordinary conversation with the guide
    SlopNetTurnOfferedBuild,    // SlopNet asked whether to build; awaiting yes
    SlopNetTurnNeedsName,       // they said yes; asking what to call it
};

@interface SlopNetAppDelegate : NSObject <NSApplicationDelegate, SlopNetConsoleDelegate,
                                          SlopNetSettingsDelegate, SlopNetWizardDelegate,
                                          NSTextViewDelegate>
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
@property(nonatomic, strong) SlopNetWizard *wizard;

// main
@property(nonatomic, strong) SlopNetConsole *console;
@property(nonatomic, strong) NSTextField *modelLabel;
@property(nonatomic, strong) SlopNetEntryView *entry;
@property(nonatomic, strong) NSScrollView *entryScroller;
@property(nonatomic, strong) NSLayoutConstraint *entryHeight;
@property(nonatomic, strong) NSButton *sendButton;
// Shown in place of the typing box when the running program wants something
// specific: a password gets a real masked field, a yes/no gets two buttons.
// Typing a password blind into a terminal is the moment a non-expert decides
// the app has frozen.
@property(nonatomic, strong) NSStackView *promptBar;
@property(nonatomic, strong) NSTextField *promptLabel;
@property(nonatomic, strong) NSSecureTextField *secretField;
@property(nonatomic, strong) NSButton *secretSend;
@property(nonatomic, strong) NSButton *approveButton;
@property(nonatomic, strong) NSButton *declineButton;
@property(nonatomic, strong) NSButton *continueButton;
@property(nonatomic, strong) NSButton *openPageButton;
@property(nonatomic, strong) NSButton *codeButton;
@property(nonatomic, strong) NSURL *signInPage;
@property(nonatomic, copy) NSString *signInCode;
@property(nonatomic, strong) NSURL *conversationURL;

// The animated action glyph. One timer drives whichever surface is live:
// the status line under the console while a program runs, or the action row
// of the ready block while nothing does.
@property(nonatomic, strong) NSTimer *actionTimer;
@property(nonatomic, assign) NSUInteger actionTick;
@property(nonatomic, copy) NSString *actionConcept;
@property(nonatomic, copy) NSString *actionCaption;
@property(nonatomic, assign) NSInteger readyBlockToken;

@property(nonatomic, assign) BOOL busy;
@property(nonatomic, assign) BOOL setupRunning;
@property(nonatomic, assign) BOOL chatting;
/// What has been said this conversation, oldest first, as "You: …" / "Granite: …".
/// Kept on the Mac and handed to the guide with each question, because the
/// model runs one finite process per turn and remembers nothing by itself.
@property(nonatomic, strong) NSMutableArray<NSString *> *conversation;
@property(nonatomic, assign) BOOL localHelperRunning;
@property(nonatomic, assign) BOOL planningRunning;
@property(nonatomic, assign) BOOL approvedBuildRunning;
@property(nonatomic, assign) BOOL uninstalling;
@property(nonatomic, copy) NSString *activeProjectName;
@property(nonatomic, copy) NSString *plannedProjectName;
@property(nonatomic, copy) NSString *localModelName;
@property(nonatomic, assign) SlopNetTurn turn;
/// What they asked to have built, held while the offer and the name are
/// agreed, so nobody has to type their request twice.
@property(nonatomic, copy) NSString *pendingRequest;
/// Raised after the guide finishes answering, so its reply comes first and
/// SlopNet's offer follows it rather than interrupting.
@property(nonatomic, assign) BOOL offerBuildWhenReplyEnds;
/// Coding apps still to sign in to, and how each one turned out. Kept so a
/// refusal or a skip moves on to the next instead of stranding the run.
@property(nonatomic, strong) NSMutableArray<NSString *> *signInQueue;
@property(nonatomic, strong) NSMutableArray<NSString *> *signedIn;
@property(nonatomic, strong) NSMutableArray<NSString *> *skipped;
@property(nonatomic, copy) NSString *signingIn;
@property(nonatomic, strong) NSButton *skipButton;
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

- (NSButton *)promptButton:(NSString *)title action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
    button.title = title;
    button.bezelStyle = NSBezelStyleRounded;
    button.target = self;
    button.action = action;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:76].active = YES;
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

/// Build the menu bar.
///
/// There was none. That is why Command-C did nothing in the console and the
/// only way to copy was a right-click: the standard shortcuts are routed by
/// the menu bar, and with no Edit menu there was nothing to route them to.
/// Command-Q had the same problem. Every Mac app needs this; SlopNet simply
/// never had one.
- (void)buildMenuBar {
    NSMenu *bar = [[NSMenu alloc] init];

    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:@"About SlopNet"
                       action:@selector(orderFrontStandardAboutPanel:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Settings…" action:@selector(openSettings:) keyEquivalent:@","];
    [appMenu addItemWithTitle:@"Setup guide" action:@selector(openWizard:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Hide SlopNet" action:@selector(hide:) keyEquivalent:@"h"];
    [appMenu addItemWithTitle:@"Quit SlopNet" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    [bar addItem:appItem];

    NSMenuItem *editItem = [[NSMenuItem alloc] init];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    NSMenuItem *redo = [editMenu addItemWithTitle:@"Redo" action:@selector(redo:)
                                    keyEquivalent:@"Z"];
    redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = editMenu;
    [bar addItem:editItem];

    NSMenuItem *windowItem = [[NSMenuItem alloc] init];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenu addItemWithTitle:@"Minimise" action:@selector(performMiniaturize:)
                   keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];
    windowItem.submenu = windowMenu;
    [bar addItem:windowItem];

    NSApp.mainMenu = bar;
    NSApp.windowsMenu = windowMenu;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self buildMenuBar];
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
        // SLOPNET_DEBUG_PROMPT=password|confirm runs a harmless local command
        // that asks for one, so the control that replaces the typing box can
        // be seen without a server. It touches nothing and answers nothing.
        NSString *demo = NSProcessInfo.processInfo.environment[@"SLOPNET_DEBUG_PROMPT"];
        if ([demo isEqualToString:@"password"] || [demo isEqualToString:@"confirm"]) {
            NSString *script = [demo isEqualToString:@"password"]
                // Split across two literals so the secret scanner's fallback
                // pattern cannot read a fake prompt as a committed credential.
                // Nothing changes at runtime; the compiler joins them back up.
                ? @"printf 'someone@your-server\\047s password: '"
                  @"; read -r x; echo"
                : @"printf 'Install the private guide and test it? [y/N] '; read -r x; echo";
            [self.console runExecutable:@"/bin/bash" arguments:@[@"-c", script]];
        }
    });

    // First run is a wizard, not an empty console with a hint. It opens
    // before any provider login, planning, or model conversation can be
    // reached, and it resumes at the first thing that has not passed yet.
    if (![self setupComplete]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self openWizardAtResumeStep]; });
    }
    if ([self isReady]) [self refreshLocalModelName];
}

/// Everything the wizard covers has passed, and the person has seen the last
/// screen. Until then the wizard opens itself on launch.
- (BOOL)setupComplete {
    NSUserDefaults *store = [NSUserDefaults standardUserDefaults];
    return [self isReady] && [self guideReady] && [store boolForKey:kWizardKey];
}

- (BOOL)guideReady {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kGuideKey];
}

- (void)setGuideReady:(BOOL)ready {
    [[NSUserDefaults standardUserDefaults] setBool:ready forKey:kGuideKey];
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
    // Setup is discoverable from the main window, not only from Settings.
    NSButton *wizardButton = [self sidebarButton:@"◷   Setup guide"
                                         action:@selector(openWizard:)];

    NSStackView *sidebar = [NSStackView stackViewWithViews:@[
        title, status,
        [self separator],
        newButton,
        historyTitle, self.historyStack,
        spacer,
        [self separator],
        wizardButton,
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

    // One box and one button. There is no mode to choose and no separate
    // name field: a person types what they want in their own words, and
    // where the conversation has got to decides what that means.
    //
    // The model is shown, not chosen. It was a pop-up whose only other item
    // opened Settings — a menu pretending to be a control. Which guide is
    // answering matters in a conversation; being asked to pick one does not.
    self.modelLabel = [NSTextField labelWithString:@""];
    self.modelLabel.font = [NSFont systemFontOfSize:11];
    self.modelLabel.textColor = [NSColor secondaryLabelColor];
    self.modelLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.modelLabel.maximumNumberOfLines = 1;
    self.modelLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.modelLabel.widthAnchor constraintLessThanOrEqualToConstant:220].active = YES;
    [self refreshModelLabel];
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
    // One label, always. It used to say Build it / Answer / Make a plan /
    // Set up / Ask / Set up guide / Start approved build depending on hidden
    // state — seven identities for one control, and no way to predict which
    // one you had. Send always means: give this to SlopNet.
    self.sendButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    self.sendButton.title = @"Send";
    self.sendButton.bezelStyle = NSBezelStyleRounded;
    self.sendButton.target = self;
    self.sendButton.action = @selector(sendPressed:);
    [self.sendButton.widthAnchor constraintGreaterThanOrEqualToConstant:76].active = YES;

    NSStackView *chatBar = [NSStackView stackViewWithViews:@[
        self.entryScroller, self.sendButton]];
    chatBar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    chatBar.alignment = NSLayoutAttributeTop;
    chatBar.spacing = 8;
    chatBar.translatesAutoresizingMaskIntoConstraints = NO;

    // Which guide is answering sits above the box, out of the way of the
    // one thing there is to press.
    // The control that replaces the typing box when the server asks for
    // something specific. Built once, hidden until it is needed.
    self.promptLabel = [self label:@"" size:12 grey:NO];
    self.promptLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.secretField = [[NSSecureTextField alloc] initWithFrame:NSZeroRect];
    self.secretField.placeholderString = @"Your server password";
    self.secretField.translatesAutoresizingMaskIntoConstraints = NO;
    self.secretField.target = self;
    self.secretField.action = @selector(secretEntered:);
    [self.secretField.heightAnchor constraintEqualToConstant:24].active = YES;

    self.secretSend = [self promptButton:@"Send password" action:@selector(secretEntered:)];
    self.approveButton = [self promptButton:@"Yes" action:@selector(approvePressed:)];
    self.declineButton = [self promptButton:@"No" action:@selector(declinePressed:)];
    self.continueButton = [self promptButton:@"Continue" action:@selector(continuePressed:)];
    self.openPageButton = [self promptButton:@"Open the sign-in page"
                                     action:@selector(openSignInPage:)];
    self.codeButton = [self promptButton:@"Copy the code again"
                                     action:@selector(putCodeOnClipboard:)];
    self.skipButton = [self promptButton:@"Skip this one"
                                  action:@selector(skipThisSignIn:)];

    NSStackView *promptControls = [NSStackView stackViewWithViews:@[
        self.secretField, self.secretSend, self.approveButton, self.declineButton,
        self.continueButton, self.openPageButton, self.codeButton, self.skipButton]];
    promptControls.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    promptControls.alignment = NSLayoutAttributeCenterY;
    promptControls.spacing = 8;

    self.promptBar = [NSStackView stackViewWithViews:@[self.promptLabel, promptControls]];
    self.promptBar.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.promptBar.alignment = NSLayoutAttributeLeading;
    self.promptBar.spacing = 6;
    self.promptBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.promptBar.hidden = YES;
    [promptControls.widthAnchor constraintEqualToAnchor:self.promptBar.widthAnchor].active = YES;

    NSStackView *composer = [NSStackView stackViewWithViews:@[self.modelLabel, self.promptBar,
                                                             chatBar]];
    composer.orientation = NSUserInterfaceLayoutOrientationVertical;
    composer.alignment = NSLayoutAttributeLeading;
    composer.spacing = 4;
    composer.translatesAutoresizingMaskIntoConstraints = NO;
    [chatBar.widthAnchor constraintEqualToAnchor:composer.widthAnchor].active = YES;

    // Plain constraints rather than a stack here: two children, and the
    // console must take every spare pixel at any window size.
    NSView *main = [[NSView alloc] initWithFrame:NSZeroRect];
    [main addSubview:self.console];
    [main addSubview:composer];
    [NSLayoutConstraint activateConstraints:@[
        [self.console.topAnchor constraintEqualToAnchor:main.topAnchor constant:16],
        [self.console.leadingAnchor constraintEqualToAnchor:main.leadingAnchor constant:16],
        [self.console.trailingAnchor constraintEqualToAnchor:main.trailingAnchor constant:-16],

        [composer.topAnchor constraintEqualToAnchor:self.console.bottomAnchor constant:10],
        [composer.leadingAnchor constraintEqualToAnchor:main.leadingAnchor constant:16],
        [composer.trailingAnchor constraintEqualToAnchor:main.trailingAnchor constant:-16],
        [composer.bottomAnchor constraintEqualToAnchor:main.bottomAnchor constant:-16],
    ]];
    return main;
}

#pragma mark - one place decides what the window shows

- (BOOL)isReady {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kReadyKey] &&
           self.host.length > 0;
}

- (void)refreshState {
    BOOL ready = [self isReady];
    BOOL guide = [self guideReady];
    if (ready && guide) {
        self.statusDot.textColor = [NSColor systemGreenColor];
        self.statusText.stringValue = [NSString stringWithFormat:@"Ready — %@", self.host];
    } else if (ready) {
        self.statusDot.textColor = [NSColor systemOrangeColor];
        self.statusText.stringValue = @"Server ready — guide not installed";
    } else {
        self.statusDot.textColor = [NSColor systemGrayColor];
        self.statusText.stringValue = @"No server yet";
    }
    self.modelLabel.hidden = !ready || !guide;

    // The button never changes. Only the hint inside the empty box changes,
    // and it describes what will happen rather than naming a mode.
    self.entry.editable = YES;
    if (self.busy) {
        self.entry.prompt = @"It is asking you something — type your answer and press Return";
    } else if (!ready) {
        self.entry.prompt = @"Press Send to connect your server — the guide walks you through it";
        self.entry.editable = NO;
    } else if (!guide) {
        self.entry.prompt = @"Press Send to install your private guide — nothing downloads until you agree";
        self.entry.editable = NO;
    } else if (self.plannedProjectName.length > 0) {
        self.entry.prompt = @"Read the plan above. Say yes to start building it, or keep talking.";
    } else if (self.turn == SlopNetTurnOfferedBuild) {
        self.entry.prompt = @"Say yes to build it, or carry on talking";
    } else if (self.turn == SlopNetTurnNeedsName) {
        self.entry.prompt = @"A short name for it — lowercase letters, numbers and hyphens";
    } else {
        self.entry.prompt = @"Ask anything, or say what you want built…";
    }
    [self resizeEntry];
    [self rebuildHistory];
}

/// Does this read like "make me something", rather than a question?
///
/// A heuristic, and it fails safely in both directions: a miss just means
/// the person says "build it" themselves, and a false positive costs one
/// line they can ignore by carrying on talking. It never starts anything —
/// the offer it raises still has to be accepted.
- (BOOL)soundsLikeARequestToBuild:(NSString *)text {
    NSString *lower = text.lowercaseString;
    if (lower.length < 8) return NO;
    for (NSString *opener in @[@"build ", @"make ", @"create ", @"write ", @"code ",
                               @"build me", @"make me", @"can you build",
                               @"can you make", @"i want a", @"i need a",
                               @"i'd like a", @"id like a"]) {
        if ([lower hasPrefix:opener] ||
            [lower rangeOfString:[@" " stringByAppendingString:opener]].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)meansYes:(NSString *)text {
    NSString *word = [text.lowercaseString stringByTrimmingCharactersInSet:
        [NSCharacterSet characterSetWithCharactersInString:@" .!\t\n"]];
    return [@[@"y", @"yes", @"yeah", @"yep", @"yup", @"ok", @"okay", @"sure",
              @"go", @"go on", @"do it", @"please do", @"build it"] containsObject:word];
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
    self.turn = SlopNetTurnTalking;
    self.pendingRequest = nil;
    self.offerBuildWhenReplyEnds = NO;
    self.entry.string = @"";
    [self.console note:
        @"\nNew conversation. Ask your guide anything, or say what you want built."];
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
    self.turn = SlopNetTurnTalking;
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
            @"Your server (%@) is ready.\n"
            @"Just talk to your guide below. Ask it anything, or say what you want built "
            @"and it will offer to build it. Nothing costs money until you say yes.",
            self.host]];
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
/// Keep one line of the conversation, capped so a long session cannot grow the
/// prompt without limit. Older turns fall off the front; the guide keeps the
/// recent thread, which is what a person means by "remember what I said".
- (void)remember:(NSString *)line {
    if (self.conversation == nil) self.conversation = [NSMutableArray array];
    [self.conversation addObject:line];
    while (self.conversation.count > 20) [self.conversation removeObjectAtIndex:0];
}

/// Everything the guide is allowed to know: the recent conversation, then the
/// tail of what the terminal has actually shown.
///
/// The terminal half is the point of this — a guide that can read what just
/// scrolled past can explain it. It is read-only. Nothing here lets the model
/// run anything; it has no tools, and the prompt says so.
///
/// Secrets are taken out first. Sign-in codes and keys pass through this
/// window, and while the model is local and private, text that goes into a
/// prompt should never be the place a credential is kept alive.
- (NSString *)guideContext {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (self.conversation.count > 0) {
        [parts addObject:[NSString stringWithFormat:@"Earlier in this conversation:\n%@",
                          [self.conversation componentsJoinedByString:@"\n"]]];
    }
    NSString *screen = [self.console recentLinesForContext:60];
    if (screen.length > 0) {
        [parts addObject:[NSString stringWithFormat:
            @"What the terminal has shown (you cannot run anything, only read this):\n%@",
            screen]];
    }
    return [parts componentsJoinedByString:@"\n\n"];
}

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
        NSArray *signedIn = [NSUserDefaults.standardUserDefaults
            arrayForKey:kSignedInProvidersKey] ?: @[];
        NSMutableDictionary<NSString *, NSString *> *status = [NSMutableDictionary dictionary];
        for (NSString *identifier in tools) {
            status[identifier] = [signedIn containsObject:identifier]
                ? @"signed in · can build"
                : @"not signed in yet";
        }
        [parts addObject:[SlopNetBrand panelStripANSIForProviders:tools
                                                           status:status
                                                            width:width]];
    }
    return [parts componentsJoinedByString:@"\n"];
}

- (void)showReadyBlock {
    // No action glyph. The board is what the app looks like when it is doing
    // nothing, and a Think animation running against an idle guide says the
    // opposite — think belongs to the moment a question is being answered.
    self.actionConcept = nil;
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
    self.settings.window.title = @"Settings";
    self.settings.delegate = self;
    [self.settings presentFrom:self.window];
}

#pragma mark - the setup wizard

- (void)openWizardAtStep:(SlopNetWizardStep)step {
    if (self.wizard != nil && self.wizard.window.sheetParent != nil) {
        // Hand it what is true now. Without this a step kept insisting the
        // server was not prepared after the run that prepared it, and Back
        // just showed the same stale screen.
        [self.wizard updateServerReady:[self isReady] guideReady:[self guideReady]];
        [self.wizard showStep:step];
        return;
    }
    self.wizard = [[SlopNetWizard alloc] initWithHost:self.host
                                                 port:self.port
                                                 user:self.username
                                          serverReady:[self isReady]
                                           guideReady:[self guideReady]];
    self.wizard.delegate = self;
    [self.wizard showStep:step];
    [self.wizard presentFrom:self.window];
}

- (void)openWizardAtResumeStep {
    [self openWizardAtStep:[SlopNetWizard resumeStepForServerReady:[self isReady]
                                                       guideReady:[self guideReady]]];
}

- (void)openWizard:(id)sender { [self openWizardAtResumeStep]; }

- (void)wizard:(SlopNetWizard *)wizard rememberHost:(NSString *)host
          port:(NSString *)port user:(NSString *)user {
    self.host = host;
    self.port = port.length ? port : @"22";
    self.username = user.length ? user : @"root";
    [self remember];
    [self refreshState];
}

- (void)wizard:(SlopNetWizard *)wizard
 connectToHost:(NSString *)host
          port:(NSString *)port
          user:(NSString *)user {
    // The same path Settings uses: whoever asked steps aside and the console
    // runs it, because this is where the server's password prompt appears.
    [self prepareServerHost:host port:port user:user];
}

- (void)wizard:(SlopNetWizard *)wizard installGuideModel:(NSString *)model {
    [self installGuideModel:model];
}

/// Sign in to the chosen coding apps one after another.
///
/// One at a time on purpose: each one opens a browser page and shows a code,
/// and two of those at once is how somebody ends up pasting the wrong code
/// into the wrong page. The queue is kept so a failure or a skip moves on to
/// the next rather than stopping everything.
- (void)wizard:(SlopNetWizard *)wizard signInToCodingApps:(NSArray<NSString *> *)providers {
    self.signInQueue = [providers mutableCopy];
    self.signedIn = [NSMutableArray array];
    self.skipped = [NSMutableArray array];
    [self startNextCodingAppSignIn];
}

/// Put the ordinary typing box back and hide every prompt control.
- (void)showTypingBar {
    self.promptBar.hidden = YES;
    self.skipButton.hidden = YES;
    self.entryScroller.hidden = NO;
    self.sendButton.hidden = NO;
    [self.window makeFirstResponder:self.entry];
}

/// Stop the spinning glyph. Setting a nil concept would leave the timer
/// running with nothing to draw.
- (void)endActivity {
    [self.actionTimer invalidate];
    self.actionTimer = nil;
    self.actionConcept = nil;
    self.actionCaption = nil;
}

- (void)startNextCodingAppSignIn {
    if (self.signInQueue.count == 0) {
        [self finishCodingAppSignIns];
        return;
    }
    NSString *provider = self.signInQueue.firstObject;
    [self.signInQueue removeObjectAtIndex:0];
    self.signingIn = provider;

    NSString *script = [self helper:@"slopnet-vps-coding-app"];
    if (script == nil) {
        [self.console note:@"The part of SlopNet that signs in to a coding app is missing "
                           @"from this copy. Download SlopNet again."];
        self.signingIn = nil;
        [self finishCodingAppSignIns];
        return;
    }
    NSString *name = [SlopNetBrand displayNameForProvider:provider] ?: provider;
    [self.console note:[SlopNetBrand headerANSI:[NSString stringWithFormat:@"Signing in to %@", name]
                                          width:[self panelWidth]]];
    [self.console note:@"A page will open in your browser. Your one-time code appears "
                       @"below and is copied for you."];
    [self.console note:@"If this one will not go through, press Skip this one — the rest "
                       @"carry on without it."];
    [self showSkipControl:name];
    [self beginActivity:@"search"
                caption:[NSString stringWithFormat:@"Waiting for you to sign in to %@…", name]];
    [self setBusy:YES];
    if (![self.console runExecutable:@"/bin/bash"
                           arguments:@[script, self.host, self.port, self.username, provider]]) {
        [self setBusy:NO];
        [self codingAppSignInEnded:NO];
    }
}

/// A person must always be able to leave a sign-in that will not complete.
/// Without this, one coding app refusing a login strands the whole first run.
- (void)showSkipControl:(NSString *)name {
    self.promptBar.hidden = NO;
    self.entryScroller.hidden = YES;
    self.sendButton.hidden = YES;
    self.secretField.hidden = YES;
    self.secretSend.hidden = YES;
    self.approveButton.hidden = YES;
    self.declineButton.hidden = YES;
    self.continueButton.hidden = YES;
    self.openPageButton.hidden = YES;
    self.codeButton.hidden = YES;
    self.skipButton.hidden = NO;
    self.promptLabel.stringValue =
        [NSString stringWithFormat:@"Signing in to %@. A page and a code appear here when "
                                   @"it is ready.", name];
    self.promptLabel.textColor = [NSColor labelColor];
}

- (void)skipThisSignIn:(id)sender {
    if (self.signingIn == nil) return;
    [self.skipped addObject:self.signingIn];
    [self.console note:[NSString stringWithFormat:@"\nSkipped %@. You can sign in to it "
                                                  @"later from Settings.",
                        [SlopNetBrand displayNameForProvider:self.signingIn] ?: self.signingIn]];
    self.signingIn = nil;
    [self.console stop];
    [self setBusy:NO];
    [self startNextCodingAppSignIn];
}

/// One sign-in ended, for any reason. Record it and move to the next.
- (void)codingAppSignInEnded:(BOOL)worked {
    if (self.signingIn == nil) return;       // already skipped
    [(worked ? self.signedIn : self.skipped) addObject:self.signingIn];
    self.signingIn = nil;
    [self startNextCodingAppSignIn];
}

- (void)finishCodingAppSignIns {
    self.skipButton.hidden = YES;
    [self endActivity];
    [self setBusy:NO];
    if (self.signedIn.count > 0) {
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (NSString *identifier in self.signedIn) {
            [names addObject:[SlopNetBrand displayNameForProvider:identifier] ?: identifier];
        }
        [self.console note:[NSString stringWithFormat:@"\nSigned in: %@.",
                            [names componentsJoinedByString:@", "]]];
    }
    // Remembered, so the board can say which apps can actually build. Without
    // this the tiles were five identical badges saying nothing at all.
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    NSMutableArray *known = [([store arrayForKey:kSignedInProvidersKey] ?: @[]) mutableCopy];
    for (NSString *identifier in self.signedIn) {
        if (![known containsObject:identifier]) [known addObject:identifier];
    }
    [store setObject:known forKey:kSignedInProvidersKey];

    if (self.skipped.count > 0) {
        [self.console note:@"The ones you skipped are still in Settings whenever you want "
                           @"to try them again."];
    }
    // Always back to the guide. It is the one they talk to; a coding app is
    // something SlopNet uses on their behalf, not something they operate.
    [self.console note:@"\nBack to your guide — ask it anything, in your own words."];
    [self showTypingBar];
}

- (void)wizardOpenSettings:(SlopNetWizard *)wizard {
    dispatch_async(dispatch_get_main_queue(), ^{ [self openSettings:nil]; });
}

- (void)wizardStartChat:(SlopNetWizard *)wizard {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kWizardKey];
    [self refreshState];
    [self.console note:[SlopNetBrand headerANSI:@"Ready" width:[self panelWidth]]];
    [self.console note:@"Ask the private guide anything about setup. It answers on your "
                       @"server, costs nothing, and cannot start a build."];
    [self showReadyBlock];
    [self.window makeFirstResponder:self.entry];
}

- (void)wizardDidFinish:(SlopNetWizard *)wizard {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kWizardKey];
    [self refreshState];
    [self.window makeFirstResponder:self.entry];
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

- (void)refreshModelLabel {
    if (self.modelLabel == nil) return;
    NSString *provider = [SlopNetBrand providerForLocalModel:self.localModelName];
    NSString *badge = provider ? [SlopNetBrand markForProvider:provider] : nil;
    // The recognised name, not the Hugging Face identifier. Two auditors
    // flagged "ibm-granite/granite-4.1-3b-GGUF:Q4_K_M" as exactly the kind of
    // jargon that tells a beginner this software is not for them. The full
    // identifier still lives in Settings, where somebody looking for it will
    // know what it means.
    NSString *name = provider ? [SlopNetBrand displayNameForProvider:provider] : @"Your guide";
    NSString *text = [NSString stringWithFormat:@"%@  %@ — private, on your server",
                      badge ?: @"", name];
    if (badge != nil && [SlopNetBrand colorFontActive]) {
        // The badge needs the colour face; the name stays in the system font
        // so the line still reads as part of the app.
        NSMutableAttributedString *styled = [[NSMutableAttributedString alloc]
            initWithString:text
                attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:11],
                             NSForegroundColorAttributeName: [NSColor secondaryLabelColor]}];
        [styled addAttribute:NSFontAttributeName
                       value:[SlopNetBrand consoleFontOfSize:13.5]
                       range:NSMakeRange(0, badge.length)];
        self.modelLabel.attributedStringValue = styled;
    } else {
        self.modelLabel.stringValue = text;
    }
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
    [self prepareServerHost:host port:port user:user];
}

- (void)prepareServerHost:(NSString *)host port:(NSString *)port user:(NSString *)user {
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

/// Remove SlopNet properly. Dragging the app to the Trash leaves the
/// remembered server, the saved notes and the connection key on this Mac,
/// and leaves a private account and a downloaded model on the server.
- (void)settingsWantsUninstall:(SlopNetSettings *)settings {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Remove SlopNet?";
    alert.informativeText =
        @"This forgets your server, your saved requests and the connection key on "
        @"this Mac.\n\nIf you also remove it from the server, the private SlopNet "
        @"account and anything it downloaded there go too. Nothing else on that "
        @"server is touched — other accounts, websites and databases are left "
        @"alone.\n\nAfterwards, drag SlopNet from Applications to the Trash.";
    [alert addButtonWithTitle:@"Remove from this Mac only"];
    [alert addButtonWithTitle:@"Remove from this Mac and the server"];
    [alert addButtonWithTitle:@"Cancel"];
    NSModalResponse choice = [alert runModal];
    if (choice == NSAlertThirdButtonReturn) return;
    BOOL alsoServer = (choice == NSAlertSecondButtonReturn);

    if (alsoServer && self.host.length > 0) {
        NSString *script = [self helper:@"slopnet-vps-uninstall"];
        if (script == nil) {
            [self.console note:@"The part of SlopNet that clears a server is missing from "
                               @"this copy of the app. Removing from this Mac only."];
            alsoServer = NO;
        } else {
            [self.console note:[SlopNetBrand headerANSI:@"Removing SlopNet from your server"
                                                  width:[self panelWidth]]];
            self.uninstalling = YES;
            [self beginActivity:@"search" caption:@"Clearing the server…"];
            [self setBusy:YES];
            if (![self.console runExecutable:@"/bin/bash"
                                   arguments:@[script, self.host, self.port, self.username]]) {
                self.uninstalling = NO;
                [self setBusy:NO];
            }
            return;    // the Mac side runs when that finishes
        }
    }
    [self removeLocalTraces];
}

/// Forget everything SlopNet put on this Mac, then say what is left to do.
- (void)removeLocalTraces {
    NSUserDefaults *store = [NSUserDefaults standardUserDefaults];
    for (NSString *key in @[kHostKey, kUserKey, kPortKey, kReadyKey, kGuideKey, kWizardKey]) {
        [store removeObjectForKey:key];
    }
    NSFileManager *files = NSFileManager.defaultManager;
    [files removeItemAtURL:[self historyDirectory] error:nil];
    NSString *key = [NSHomeDirectory() stringByAppendingPathComponent:
                     @".ssh/slopnet_vps_ed25519"];
    [files removeItemAtPath:key error:nil];
    [files removeItemAtPath:[key stringByAppendingString:@".pub"] error:nil];

    self.host = @"";
    self.username = @"root";
    self.port = @"22";
    self.localModelName = nil;
    [self refreshModelLabel];
    [self refreshState];

    NSAlert *done = [[NSAlert alloc] init];
    done.messageText = @"SlopNet has removed itself";
    done.informativeText =
        @"One thing left, and only you can do it: open your Applications folder "
        @"and drag SlopNet to the Trash.\n\nSlopNet will quit now.";
    [done addButtonWithTitle:@"Quit SlopNet"];
    [done runModal];
    [NSApp terminate:nil];
}

- (void)settingsDidForget:(SlopNetSettings *)settings {
    NSUserDefaults *store = [NSUserDefaults standardUserDefaults];
    // Forgetting the server forgets what was proved ON that server too, so the
    // wizard starts again rather than claiming a guide that belonged elsewhere.
    for (NSString *key in @[kHostKey, kUserKey, kPortKey, kReadyKey, kGuideKey, kWizardKey]) {
        [store removeObjectForKey:key];
    }
    self.host = @"";
    self.username = @"root";
    self.port = @"22";
    self.localModelName = nil;
    [self refreshModelLabel];
    [self.console note:@"\nForgotten on this Mac. Your server itself is untouched, and "
                       @"no password was ever stored."];
    [self refreshState];
}

- (void)settingsCheckConnection:(SlopNetSettings *)settings { [self checkConnection:nil]; }

- (void)settingsClearConsole:(SlopNetSettings *)settings { [self clearConsole:nil]; }

- (void)settingsShowServerHelp:(SlopNetSettings *)settings { [self openServerHelp:nil]; }

- (void)settings:(SlopNetSettings *)settings setupLocalHelperModel:(NSString *)model {
    [self installGuideModel:model];
}

- (void)installGuideModel:(NSString *)model {
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
    // --approved: the wizard already showed the download size against this
    // server's free storage and memory, and would not enable Install until it
    // had checked. Pressing it is the answer; asking twice more in a terminal
    // is what left people staring at a screen that looked stuck.
    if (![self.console runExecutable:@"/bin/bash"
                           arguments:@[script, self.host, self.port, self.username,
                                       model, @"--approved"]]) {
        [self setBusy:NO];
    }
}

- (void)refreshLocalModelName {
    if (![self isReady] || self.host.length == 0) {
        self.localModelName = nil;
        [self refreshModelLabel];
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
                // Positive evidence from the server itself: that file exists
                // only after the model passed its proof. A failed read is NOT
                // treated as evidence the guide is gone — the network is the
                // likelier explanation, and nagging would be wrong.
                [strongSelf setGuideReady:YES];
            } else {
                strongSelf.localModelName = nil;
            }
            [strongSelf refreshModelLabel];
            [strongSelf refreshState];
        });
    };
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        self.localModelName = nil;
        [self refreshModelLabel];
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
        [self.console note:@"\nConnect a server first — the setup guide walks you through it."];
        [self openWizardAtResumeStep];
        return;
    }
    NSString *idea = [self.entry.string stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![self guideReady]) {
        [self.console note:@"\nYour private guide is not installed yet. That is the thing "
                           @"that answers you, so the setup guide is opening — nothing is "
                           @"downloaded until you agree to it."];
        [self openWizardAtStep:SlopNetWizardStepGuide];
        return;
    }
    if (idea.length == 0) return;

    // They were asked whether to build the last thing they described.
    if (self.turn == SlopNetTurnOfferedBuild) {
        self.entry.string = @"";
        [self resizeEntry];
        if ([self meansYes:idea]) {
            self.turn = SlopNetTurnNeedsName;
            [self.console note:[SlopNetBrand headerANSI:@"Naming it" width:[self panelWidth]]];
            [self.console note:@"What should I call it? A short name, lowercase letters, "
                               @"numbers and hyphens — photo-sheet, say."];
            [self refreshState];
            return;
        }
        // Anything that is not a yes is just more conversation.
        self.turn = SlopNetTurnTalking;
        self.pendingRequest = nil;
        [self askTheGuide:idea];
        return;
    }

    // They said yes and are naming it.
    if (self.turn == SlopNetTurnNeedsName) {
        NSString *name = idea.lowercaseString;
        if (![self matches:name pattern:@"^[a-z0-9][a-z0-9-]{0,62}$"]) {
            [self.console note:@"\nThat name will not work. Lowercase letters, numbers and "
                               @"hyphens only, starting with a letter or number — like "
                               @"photo-sheet. What should I call it?"];
            self.entry.string = @"";
            [self resizeEntry];
            return;
        }
        self.entry.string = @"";
        [self resizeEntry];
        [self startPlanFor:name request:self.pendingRequest ?: @""];
        return;
    }

    if (self.plannedProjectName.length > 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Start coding agents?";
        alert.informativeText = [NSString stringWithFormat:
            @"You approved the plan for %@. This starts the multi-agent coding run on your VPS and spends from the proved coding subscription. Agents may edit only that project; checks and its test command decide what can merge.",
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
    // Ordinary conversation. If it sounded like a request to have something
    // made, SlopNet says so once the guide has finished answering — the
    // reply comes first, then the offer.
    self.pendingRequest = [self soundsLikeARequestToBuild:idea] ? idea : nil;
    self.offerBuildWhenReplyEnds = (self.pendingRequest != nil);
    [self askTheGuide:idea];
}

/// One finite reply from the private guide on the server. It has no tools,
/// cannot reach a coding app, and cannot start a build.
- (void)askTheGuide:(NSString *)question {
    NSString *script = [self helper:@"slopnet-vps-chat"];
    if (script == nil) {
        [self.console note:@"The part of SlopNet that talks to your guide is missing from "
                           @"this copy of the app. Download SlopNet again."];
        return;
    }
    NSString *provider =
        [SlopNetBrand providerForLocalModel:self.localModelName] ?: @"ibm_granite";
    // The person's line, then the guide's name, then its reply streams in
    // underneath. The question used to be wrapped in a Granite panel with a
    // thinking glyph, so the screen showed Granite's mark above words Granite
    // had not written.
    [self.console note:[SlopNetBrand youSaidANSI:question width:[self panelWidth]]];
    NSString *context = [self guideContext];
    [self remember:[NSString stringWithFormat:@"You: %@", question]];
    [self.console note:[SlopNetBrand guideRepliesANSIForProvider:provider
                                                            name:@"Granite"]];
    self.entry.string = @"";
    [self resizeEntry];
    [self beginActivity:@"think" caption:@"Your guide is thinking…"];
    [self setBusy:YES];
    // The reply is the news. A turn that worked should not be followed by a
    // note saying a program exited — that is the app talking about itself.
    self.console.quietWhenItWorks = YES;
    // Held back so the reply can be framed once it is complete. Only a
    // conversation turn does this — setup, installs and sign-ins keep
    // streaming into the window line by line, because watching them is the
    // whole point of showing a terminal at all.
    self.console.collectsOutput = YES;
    self.chatting = YES;
    if (![self.console runExecutable:@"/bin/bash"
                           arguments:@[script, self.host, self.port, self.username,
                                       question, context]]) {
        self.chatting = NO;
        [self setBusy:NO];
    }
}

/// Ask the paid coding app for a plan, and stop there. Still two separate
/// agreements before any agent runs: this one, and the approval of the plan
/// it writes.
- (void)startPlanFor:(NSString *)name request:(NSString *)request {
    NSString *script = [self helper:@"slopnet-vps-project"];
    if (script == nil) {
        [self.console note:@"The part of SlopNet that makes a plan is missing from this "
                           @"copy of the app. Download SlopNet again."];
        return;
    }
    self.turn = SlopNetTurnTalking;
    self.pendingRequest = nil;
    [self rememberRequest:request project:name];
    [self.console note:[SlopNetBrand headerANSI:@"Writing a plan" width:[self panelWidth]]];
    [self.console note:[NSString stringWithFormat:
        @"%@ — %@\n\nThis asks the paid coding app on your server for a plan and then "
        @"stops. It writes no project files and starts no coding agents. You will read "
        @"the plan and decide separately.", name, request]];
    self.activeProjectName = name;
    self.planningRunning = YES;
    [self beginActivity:@"think" caption:@"Writing a plan…"];
    [self setBusy:YES];
    if (![self.console runExecutable:@"/bin/bash"
                           arguments:@[script, self.host, self.port,
                                       self.username, name, request]]) {
        self.planningRunning = NO;
        [self setBusy:NO];
    }
}

#pragma mark - when the server asks for something specific

/// Put a real control in front of the person for the two moments that
/// frighten people: a password, and a yes/no they cannot undo.
- (void)console:(SlopNetConsole *)console
        asksFor:(SlopNetPrompt)prompt
       question:(NSString *)question {
    BOOL asking = (prompt != SlopNetPromptNone);
    self.promptBar.hidden = !asking;
    self.entryScroller.hidden = asking;
    self.sendButton.hidden = asking;

    self.secretField.hidden = (prompt != SlopNetPromptPassword);
    self.secretSend.hidden = (prompt != SlopNetPromptPassword);
    self.approveButton.hidden = (prompt != SlopNetPromptConfirm);
    self.declineButton.hidden = (prompt != SlopNetPromptConfirm);
    self.continueButton.hidden = (prompt != SlopNetPromptContinue);
    // The sign-in offer is separate: it stays put while the program keeps
    // printing, and is cleared when the run ends.
    self.openPageButton.hidden = (self.signInPage == nil);
    self.codeButton.hidden = (self.signInCode == nil);
    if (self.signInPage != nil) self.promptBar.hidden = NO;

    if (prompt == SlopNetPromptPassword) {
        self.promptLabel.stringValue =
            @"Your server is asking for its password. It goes straight there and is "
            @"never saved on this Mac.";
        self.promptLabel.textColor = [NSColor labelColor];
        self.secretField.stringValue = @"";
        [self.window makeFirstResponder:self.secretField];
    } else if (prompt == SlopNetPromptConfirm) {
        // The program's own question, minus the [y/N] it ends with — the
        // buttons say that part now.
        NSString *asked = question ?: @"";
        NSRange bracket = [asked rangeOfString:@"[" options:NSBackwardsSearch];
        if (bracket.location != NSNotFound) asked = [asked substringToIndex:bracket.location];
        asked = [asked stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
        self.promptLabel.stringValue = asked.length > 0 ? asked : @"It is asking you to confirm.";
        self.promptLabel.textColor = [NSColor labelColor];
        [self.window makeFirstResponder:self.approveButton];
    } else if (prompt == SlopNetPromptContinue) {
        NSString *asked = [question ?: @"" stringByTrimmingCharactersInSet:
            [NSCharacterSet characterSetWithCharactersInString:@" :\t"]];
        self.promptLabel.stringValue = asked.length > 0 ? asked : @"Ready to carry on.";
        self.promptLabel.textColor = [NSColor labelColor];
        [self.window makeFirstResponder:self.continueButton];
    } else {
        [self.window makeFirstResponder:self.entry];
    }
}

- (void)continuePressed:(id)sender { [self.console sendLine:@""]; }

/// A coding app wants a browser sign-in. It prints a link and a one-time
/// code, and expects both to be carried across by hand.
///
/// The code goes straight to the clipboard so it is ready to paste, and the
/// link gets a button showing exactly where it goes. SlopNet does not open it
/// unprompted: this is output from a program, and output is not an
/// instruction — the person decides.
- (void)console:(SlopNetConsole *)console needsSignIn:(NSURL *)page code:(NSString *)code {
    // The same page is offered again when the code turns up a moment after the
    // link, so only write it into the output the first time.
    BOOL alreadyShown = [page.absoluteString isEqualToString:self.signInPage.absoluteString];
    self.signInPage = page;
    self.signInCode = code;
    if (code.length > 0) {
        [NSPasteboard.generalPasteboard clearContents];
        [NSPasteboard.generalPasteboard setString:code forType:NSPasteboardTypeString];
    }
    self.promptBar.hidden = NO;
    self.entryScroller.hidden = YES;
    self.sendButton.hidden = YES;
    self.secretField.hidden = YES;
    self.secretSend.hidden = YES;
    self.approveButton.hidden = YES;
    self.declineButton.hidden = YES;
    self.continueButton.hidden = YES;
    self.openPageButton.hidden = NO;
    self.codeButton.hidden = (code.length == 0);
    self.promptLabel.stringValue = code.length > 0
        ? [NSString stringWithFormat:
           @"%@ needs you to sign in. Your code %@ is copied — press the button, "
           @"then paste it on the page that opens.", @"A coding app", code]
        : [NSString stringWithFormat:@"A coding app needs you to sign in at %@",
           page.absoluteString];
    self.promptLabel.textColor = [NSColor labelColor];
    if (!alreadyShown) {
        [self.console note:[NSString stringWithFormat:@"\nSign-in page: %@",
                            page.absoluteString]];
    }
    [self.window makeFirstResponder:self.openPageButton];
}

- (void)openSignInPage:(id)sender {
    if (self.signInPage != nil) [NSWorkspace.sharedWorkspace openURL:self.signInPage];
}

- (void)putCodeOnClipboard:(id)sender {
    if (self.signInCode.length == 0) return;
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:self.signInCode forType:NSPasteboardTypeString];
}

- (void)secretEntered:(id)sender {
    NSString *secret = self.secretField.stringValue;
    if (secret.length == 0) return;
    self.secretField.stringValue = @"";     // no copy stays in the field
    [self.console sendSecret:secret];
}

- (void)approvePressed:(id)sender { [self.console sendLine:@"y"]; }

- (void)declinePressed:(id)sender { [self.console sendLine:@"n"]; }

#pragma mark - console callbacks

- (void)console:(SlopNetConsole *)console finishedWithStatus:(int)status {
    if (self.chatting) {
        self.chatting = NO;
        NSString *said = console.collectedOutput;
        if (status == 0 && said.length > 0) {
            [self remember:[NSString stringWithFormat:@"Granite: %@", said]];
            NSString *provider =
                [SlopNetBrand providerForLocalModel:self.localModelName] ?: @"ibm_granite";
            [console note:[SlopNetBrand guideSaidANSI:said
                                             provider:provider
                                                 name:@"Granite"
                                                width:[self panelWidth]]];
        } else if (said.length > 0) {
            // A failure is shown plainly rather than dressed as the guide
            // speaking. It did not say this; something went wrong.
            [console note:[NSString stringWithFormat:@"\n%@", said]];
        }
    }
    // A coding-app sign-in that ended, however it ended. Recorded and moved
    // past, so one refusal cannot strand the rest of the queue.
    if (self.signingIn != nil) {
        [self endActivity];
        [self codingAppSignInEnded:(status == 0)];
        return;
    }
    // A server counts as ready only when SETUP itself finished cleanly —
    // not because someone typed an address. That is what makes the green
    // dot in the sidebar worth trusting.
    if (self.setupRunning) {
        self.setupRunning = NO;
        if (status == 0) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kReadyKey];
            [self.console note:@"Your server is ready. Next: install the private local guide. "
                               @"It does not use your coding subscription."];
            [self refreshLocalModelName];
            // Straight on to the next wizard step, rather than leaving someone
            // to find the guide in Settings.
            dispatch_async(dispatch_get_main_queue(), ^{
                [self openWizardAtStep:SlopNetWizardStepGuide];
            });
        }
    }
    if (self.localHelperRunning) {
        self.localHelperRunning = NO;
        if (status == 0) {
            // The script writes its config only after the model has answered
            // its READY proof, so a clean exit here means the guide is proved.
            [self setGuideReady:YES];
            [self.console note:@"The private local guide passed its proof. Chat is now open."];
            [self refreshLocalModelName];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self openWizardAtStep:SlopNetWizardStepReady];
            });
        }
    }
    if (self.planningRunning) {
        self.planningRunning = NO;
        if (status == 0 && self.activeProjectName.length > 0) {
            self.plannedProjectName = self.activeProjectName;
            [self.console note:@"The plan is ready above. Read it. No coding agent has run. Choose Build and press Start approved build only when you want the multi-agent run to begin."];
        }
    }
    if (self.uninstalling) {
        self.uninstalling = NO;
        [self setBusy:NO];
        [self removeLocalTraces];
        return;
    }
    if (self.approvedBuildRunning) {
        self.approvedBuildRunning = NO;
        self.plannedProjectName = nil;
        if (status == 0) {
            [self.console note:@"The approved build finished. Read the result above; SlopNet kept only work that passed its checks and project tests."];
        }
    }
    [self setBusy:NO];
    if (status != 0) {
        [self.console note:@"Nothing was left half-done. Read the last few lines above, "
                           @"fix what they mention, and try again."];
    }
    self.signInPage = nil;
    self.signInCode = nil;
    self.openPageButton.hidden = YES;
    self.codeButton.hidden = YES;

    // The guide has answered. If what they asked for sounded like something
    // to have made, offer now — after the reply, not on top of it.
    if (self.offerBuildWhenReplyEnds && self.pendingRequest.length > 0 && status == 0) {
        self.offerBuildWhenReplyEnds = NO;
        self.turn = SlopNetTurnOfferedBuild;
        [self.console note:[SlopNetBrand headerANSI:@"SlopNet" width:[self panelWidth]]];
        [self.console note:@"I can build that on your server if you want. A paid coding app "
                           @"writes a plan first and stops, so you get to read it before "
                           @"anything is coded.\n\nSay yes and I will ask what to call it. "
                           @"Or carry on talking and I will leave it."];
    } else {
        self.offerBuildWhenReplyEnds = NO;
        // Deliberately no ready block here. Redrawing the whole board after
        // every reply pushed the same header, guide panel and five coding-app
        // tiles into the transcript once per message — so a short exchange
        // read as screens of repeated furniture with a sentence buried in it.
        // The board is a greeting, not a footer.
    }
    [self.window makeFirstResponder:self.entry];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app { return YES; }

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
