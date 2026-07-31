#import "SlopNetWizard.h"

// The capacity floors for the default guide. These are the same numbers the
// server-side script enforces in slopnet-vps-local-helper.sh — shown here so a
// person learns their server is too small BEFORE approving a download, not
// half way through one. If the script's floors change, change these with them.
static const NSInteger kGuideDiskFloorMiB = 5000;
static const NSInteger kGuideMemoryFloorMiB = 6000;

// The bounded path the product already chose and proved: Granite 4.1 3B at
// Q4_K_M, about a 2.1 GB download. Not the 8B, which was OOM-killed on a
// 23 GiB host before its context was bounded and then ran at ~0.6 tokens/sec.
static NSString *const kDefaultGuideModel = @"ibm-granite/granite-4.1-3b-GGUF:Q4_K_M";

/// A clip view that starts at the top. Without this, a screen whose content is
/// shorter than the window sits at the BOTTOM of it — AppKit's clip view is
/// unflipped, so a short document view falls to the origin at bottom-left.
@interface SlopNetTopClipView : NSClipView
@end

@implementation SlopNetTopClipView
- (BOOL)isFlipped { return YES; }
@end

@interface SlopNetWizard ()
@property(nonatomic, assign) SlopNetWizardStep step;
@property(nonatomic, copy) NSString *host;
@property(nonatomic, copy) NSString *port;
@property(nonatomic, copy) NSString *user;
@property(nonatomic, assign) BOOL serverReady;
@property(nonatomic, assign) BOOL guideReady;

@property(nonatomic, strong) NSStackView *page;
@property(nonatomic, strong) NSScrollView *scroller;

// Server step
@property(nonatomic, strong) NSTextField *hostField;
@property(nonatomic, strong) NSTextField *nameField;
@property(nonatomic, strong) NSTextField *userField;
@property(nonatomic, strong) NSTextField *portField;
@property(nonatomic, strong) NSTextField *serverNote;

// Guide step
@property(nonatomic, strong) NSTextField *modelField;
@property(nonatomic, strong) NSTextField *capacityNote;
@property(nonatomic, strong) NSButton *installButton;
@property(nonatomic, strong) NSProgressIndicator *capacitySpinner;
@property(nonatomic, copy) NSString *provedModel;

/// The coding apps ticked on the sign-in screen, in the order they were
/// ticked, so they are signed in to in the order the person chose.
@property(nonatomic, strong) NSMutableArray<NSString *> *chosenProviders;
@property(nonatomic, strong) NSButton *continueToSignIn;
@property(nonatomic, strong) NSTextField *chosenSummary;
@end

@implementation SlopNetWizard

- (instancetype)initWithHost:(NSString *)host
                        port:(NSString *)port
                        user:(NSString *)user
                 serverReady:(BOOL)serverReady
                  guideReady:(BOOL)guideReady {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 620, 500)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = @"Set up SlopNet";
    window.minSize = NSMakeSize(520, 380);
    self = [super initWithWindow:window];
    if (!self) return nil;
    _host = [host copy] ?: @"";
    _port = port.length ? [port copy] : @"22";
    _user = user.length ? [user copy] : @"root";
    _serverReady = serverReady;
    _guideReady = guideReady;
    _step = [SlopNetWizard resumeStepForServerReady:serverReady guideReady:guideReady];
    [self buildFrame];
    [self showStep:_step];
    return self;
}

- (void)updateServerReady:(BOOL)serverReady guideReady:(BOOL)guideReady {
    if (serverReady == self.serverReady && guideReady == self.guideReady) return;
    self.serverReady = serverReady;
    self.guideReady = guideReady;
    [self showStep:self.step];      // redraw with what is true now
}

+ (SlopNetWizardStep)resumeStepForServerReady:(BOOL)serverReady
                                   guideReady:(BOOL)guideReady {
    // Never make someone redo a step that already passed. A prepared server
    // resumes at the guide; a proved guide resumes at the last screen.
    if (!serverReady) return SlopNetWizardStepWelcome;
    if (!guideReady) return SlopNetWizardStepGuide;
    return SlopNetWizardStepReady;
}

#pragma mark - small builders

- (NSTextField *)title:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont boldSystemFontOfSize:17];
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.maximumNumberOfLines = 3;
    return label;
}

- (NSTextField *)body:(NSString *)text {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:12.5];
    label.selectable = NO;
    label.textColor = [NSColor labelColor];
    return label;
}

- (NSTextField *)quiet:(NSString *)text {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:11.5];
    label.selectable = NO;
    label.textColor = [NSColor secondaryLabelColor];
    return label;
}

- (NSButton *)button:(NSString *)title action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
    button.title = title;
    button.bezelStyle = NSBezelStyleRounded;
    button.target = self;
    button.action = action;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

/// The saved name, or nothing on a first run.
- (NSString *)savedName {
    return [NSUserDefaults.standardUserDefaults stringForKey:@"SlopNetServerName"] ?: @"";
}

/// Like -field:placeholder: but the characters are dots.
- (NSTextField *)secureField:(NSString *)value placeholder:(NSString *)placeholder {
    NSSecureTextField *field = [[NSSecureTextField alloc] initWithFrame:NSZeroRect];
    field.stringValue = value ?: @"";
    field.placeholderString = placeholder;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field.heightAnchor constraintEqualToConstant:24].active = YES;
    return field;
}

- (NSTextField *)field:(NSString *)value placeholder:(NSString *)placeholder {
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    field.stringValue = value ?: @"";
    field.placeholderString = placeholder;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field.heightAnchor constraintEqualToConstant:24].active = YES;
    return field;
}

- (NSBox *)separator {
    NSBox *line = [[NSBox alloc] initWithFrame:NSZeroRect];
    line.boxType = NSBoxSeparator;
    line.translatesAutoresizingMaskIntoConstraints = NO;
    [line.heightAnchor constraintEqualToConstant:1].active = YES;
    return line;
}

/// Every screen ends the same way: where you are, a way back where that is
/// safe, and one clear thing to press.
- (NSView *)footerWithBack:(BOOL)allowBack
                   primary:(NSString *)primaryTitle
                    action:(SEL)primaryAction {
    NSTextField *where = [self quiet:[self stepCaption]];
    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSMutableArray<NSView *> *row = [NSMutableArray arrayWithObjects:where, spacer, nil];
    // Every screen can be left. Setup that fails with no way out traps the
    // whole app behind a sheet, which is what happened on 2026-07-30.
    [row addObject:[self button:@"Close" action:@selector(closePressed:)]];
    if (allowBack) [row addObject:[self button:@"Back" action:@selector(backPressed:)]];
    if (primaryTitle.length > 0) {
        NSButton *primary = [self button:primaryTitle action:primaryAction];
        primary.keyEquivalent = @"\r";
        [primary.widthAnchor constraintGreaterThanOrEqualToConstant:120].active = YES;
        [row addObject:primary];
    }
    NSStackView *footer = [NSStackView stackViewWithViews:row];
    footer.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    footer.alignment = NSLayoutAttributeCenterY;
    footer.spacing = 10;
    return footer;
}

- (NSString *)stepCaption {
    switch (self.step) {
        case SlopNetWizardStepWelcome:      return @"Step 1 of 5 — welcome";
        case SlopNetWizardStepServer:       return @"Step 2 of 5 — your server";
        case SlopNetWizardStepServerSetup:  return @"Step 3 of 5 — prepare the server";
        case SlopNetWizardStepGuide:        return @"Step 4 of 5 — private local guide";
        case SlopNetWizardStepCodingApp:    return @"Step 5 of 5 — coding app";
        case SlopNetWizardStepReady:        return @"Finished";
    }
    return @"";
}

#pragma mark - frame

- (void)buildFrame {
    self.page = [NSStackView stackViewWithViews:@[]];
    self.page.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.page.alignment = NSLayoutAttributeLeading;
    self.page.spacing = 12;
    self.page.edgeInsets = NSEdgeInsetsMake(24, 26, 22, 26);
    self.page.translatesAutoresizingMaskIntoConstraints = NO;

    // The scroll view is what makes a resize harmless: shrink the window and
    // the content stays reachable rather than being clipped.
    self.scroller = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.scroller.hasVerticalScroller = YES;
    self.scroller.hasHorizontalScroller = NO;
    self.scroller.autohidesScrollers = YES;
    self.scroller.drawsBackground = NO;
    self.scroller.borderType = NSNoBorder;
    self.scroller.translatesAutoresizingMaskIntoConstraints = NO;
    self.scroller.contentView = [[SlopNetTopClipView alloc] initWithFrame:NSZeroRect];
    self.scroller.documentView = self.page;

    NSView *content = self.window.contentView;
    [content addSubview:self.scroller];
    [NSLayoutConstraint activateConstraints:@[
        [self.scroller.topAnchor constraintEqualToAnchor:content.topAnchor],
        [self.scroller.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.scroller.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [self.scroller.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [self.page.widthAnchor constraintEqualToAnchor:self.scroller.contentView.widthAnchor],
        [self.page.topAnchor constraintEqualToAnchor:self.scroller.contentView.topAnchor],
        [self.page.leadingAnchor constraintEqualToAnchor:self.scroller.contentView.leadingAnchor],
    ]];
}

- (void)presentFrom:(NSWindow *)parent {
    if (self.window.sheetParent != nil) return;
    [parent beginSheet:self.window completionHandler:nil];
}

- (void)close {
    if (self.window.sheetParent != nil) {
        [self.window.sheetParent endSheet:self.window];
    }
}

#pragma mark - steps

- (void)showStep:(SlopNetWizardStep)step {
    self.step = step;
    for (NSView *view in [self.page.arrangedSubviews copy]) {
        [self.page removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    NSArray<NSView *> *views = @[];
    switch (step) {
        case SlopNetWizardStepWelcome:     views = [self welcomeViews]; break;
        case SlopNetWizardStepServer:      views = [self serverViews]; break;
        case SlopNetWizardStepServerSetup: views = [self serverSetupViews]; break;
        case SlopNetWizardStepGuide:       views = [self guideViews]; break;
        case SlopNetWizardStepCodingApp:   views = [self codingAppViews]; break;
        case SlopNetWizardStepReady:       views = [self readyViews]; break;
    }
    for (NSView *view in views) {
        [self.page addArrangedSubview:view];
        // Rows fill the width, so wrapped paragraphs measure against the
        // window instead of running off the edge.
        [view.widthAnchor constraintEqualToAnchor:self.page.widthAnchor
                                         constant:-52].active = YES;
    }
    if (step == SlopNetWizardStepGuide) [self checkCapacity:nil];
}

- (NSArray<NSView *> *)welcomeViews {
    return @[
        [self title:@"SlopNet builds software on your own server"],
        [self body:@"You describe what you want. The work happens on a server you own, "
                   @"not on this Mac, and you watch every step in the window behind this one."],
        [self body:@"Two things make that possible:"],
        [self body:@"  •  A server you can reach — a rented server, a machine you already pay "
                   @"for, or a small computer at home.\n"
                   @"  •  Later, one coding subscription you already have. SlopNet never "
                   @"asks for a card and never stores a password on this Mac."],
        [self quiet:@"This takes about ten minutes, most of it waiting. You can close this "
                    @"and come back — SlopNet remembers what already passed."],
        [self separator],
        [self footerWithBack:NO primary:@"Start" action:@selector(nextPressed:)],
    ];
}

- (NSArray<NSView *> *)serverViews {
    // A name the person chooses, and the address hidden as it is typed.
    //
    // The address is the one thing on this screen that identifies a machine
    // somebody owns, and it was sitting in plain view — on this screen, in the
    // sidebar, and in every screenshot taken of either. It is masked like a
    // password now, and the name is what the app shows from here on.
    self.nameField = [self field:[self savedName] placeholder:@"what you want to call it"];
    self.hostField = [self secureField:self.host placeholder:@"address of your server"];
    self.userField = [self field:self.user placeholder:@"root"];
    self.portField = [self field:self.port placeholder:@"22"];
    [self.userField.widthAnchor constraintEqualToConstant:170].active = YES;
    [self.portField.widthAnchor constraintEqualToConstant:70].active = YES;

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[[self body:@"Name"], self.nameField],
        @[[self body:@"Address"], self.hostField],
        @[[self body:@"Login name"], self.userField],
        @[[self body:@"Port"], self.portField],
    ]];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    grid.rowSpacing = 8;
    grid.columnSpacing = 10;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:1].xPlacement = NSGridCellPlacementLeading;

    self.serverNote = [self quiet:self.serverReady
        ? @"●  This server is already set up."
        : @"These three details come from your server provider's welcome email."];
    if (self.serverReady) self.serverNote.textColor = [NSColor systemGreenColor];

    NSButton *check = [self button:@"Check it answers" action:@selector(checkPressed:)];
    NSStackView *checkRow = [NSStackView stackViewWithViews:@[check]];
    checkRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    checkRow.spacing = 10;

    return @[
        [self title:@"Which server should SlopNet use?"],
        [self body:@"Any computer you can reach over SSH. SlopNet does not care who sold "
                   @"it to you, and it changes nothing until the next screen."],
        grid,
        checkRow,
        self.serverNote,
        [self quiet:@"Your password is never saved. When the server asks for it, you type "
                    @"it into the window behind this one and it goes straight to the server."],
        [self separator],
        [self footerWithBack:YES primary:@"Continue" action:@selector(nextPressed:)],
    ];
}

- (NSArray<NSView *> *)serverSetupViews {
    if (self.serverReady) {
        return @[
            [self title:@"Your server is ready"],
            [self body:@"SlopNet has already prepared this server: it has a private "
                       @"account that agent work runs as, and it kept your existing SSH "
                       @"and firewall settings."],
            [self quiet:@"You can run it again from Settings if something changed on the "
                        @"server, but there is no need to now."],
            [self separator],
            [self footerWithBack:YES primary:@"Continue" action:@selector(nextPressed:)],
        ];
    }
    return @[
        [self title:@"Prepare the server"],
        [self body:@"This is the one step that changes your server. SlopNet will:"],
        [self body:@"  •  create a private account for agent work, so nothing runs as the "
                   @"administrator\n"
                   @"  •  check what is already installed and ask before installing anything\n"
                   @"  •  leave your SSH, password and firewall settings exactly as they are"],
        [self body:@"It runs in the window behind this one so you can read every line. "
                   @"When the server asks for your password, type it in the box at the "
                   @"bottom of that window and press Return."],
        [self quiet:@"Nothing is sent anywhere else, and no coding subscription is used."],
        [self separator],
        [self footerWithBack:YES primary:@"Prepare my server"
                      action:@selector(prepareServerPressed:)],
    ];
}

- (NSArray<NSView *> *)guideViews {
    NSMutableArray<NSView *> *views = [NSMutableArray array];
    [views addObject:[self title:@"Install the private local guide"]];

    if (self.guideReady) {
        NSTextField *good = [self body:self.provedModel.length > 0
            ? [NSString stringWithFormat:@"●  Installed and proved: %@", self.provedModel]
            : @"●  Installed and proved on your server."];
        good.textColor = [NSColor systemGreenColor];
        [views addObjectsFromArray:@[
            good,
            [self body:@"This small IBM Granite model answers ordinary setup questions on "
                       @"your server. It does not write your project, cannot start coding "
                       @"agents, and never spends from a coding subscription."],
            [self quiet:@"It runs only when you ask it something, with no open network "
                        @"port, and stops when it has answered."],
            [self separator],
            [self footerWithBack:YES primary:@"Continue" action:@selector(nextPressed:)],
        ]];
        return views;
    }

    self.modelField = [self field:kDefaultGuideModel placeholder:@"owner/model:quant"];
    NSGridView *modelRow = [NSGridView gridViewWithViews:@[
        @[[self body:@"Model"], self.modelField],
    ]];
    modelRow.translatesAutoresizingMaskIntoConstraints = NO;
    modelRow.columnSpacing = 10;
    [modelRow columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [modelRow columnAtIndex:1].xPlacement = NSGridCellPlacementLeading;

    self.capacityNote = [self quiet:@"Checking what your server has room for…"];
    self.capacitySpinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    self.capacitySpinner.style = NSProgressIndicatorStyleSpinning;
    self.capacitySpinner.controlSize = NSControlSizeSmall;
    self.capacitySpinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.capacitySpinner startAnimation:nil];

    NSButton *recheck = [self button:@"Check again" action:@selector(checkCapacity:)];
    self.installButton = [self button:@"Install the guide" action:@selector(installGuidePressed:)];
    // Deliberately off until the server has answered. There is no path to a
    // download that skips the capacity check.
    self.installButton.enabled = NO;
    NSStackView *buttons = [NSStackView stackViewWithViews:@[self.capacitySpinner, recheck,
                                                            self.installButton]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.spacing = 10;
    buttons.alignment = NSLayoutAttributeCenterY;

    [views addObjectsFromArray:@[
        [self body:@"SlopNet installs one small model on your server so it can answer "
                   @"ordinary questions — what a setting means, how to phrase a request — "
                   @"without touching a paid coding subscription."],
        [self body:@"What it is allowed to do is narrow on purpose:"],
        [self body:@"  •  ordinary chat only — it cannot write your project or start agents\n"
                   @"  •  no API key, and no network port left open\n"
                   @"  •  a small memory limit, so a long answer cannot take over the server\n"
                   @"  •  it downloads nothing until you say yes on the next screen"],
        modelRow,
        [self quiet:[NSString stringWithFormat:
            @"The default is IBM Granite 4.1 3B — about a 2.1 GB download, and the version "
            @"SlopNet has actually proved on a server. It needs %ld MiB free storage and "
            @"%ld MiB free memory.", (long)kGuideDiskFloorMiB, (long)kGuideMemoryFloorMiB]],
        buttons,
        self.capacityNote,
        [self quiet:@"Installing opens the window behind this one. It shows your server's "
                    @"real free space, asks you to approve the download, then makes the "
                    @"model answer one word to prove it works."],
        [self separator],
        [self footerWithBack:YES primary:nil action:NULL],
    ]];
    return views;
}

/// The four coding apps a person can sign in to with a subscription they
/// already pay for. All four have a command-line tool that signs in through a
/// browser, so none of them needs an API key typed into anything.
///
/// Moonshot and Z.ai are deliberately absent: they work from a pasted API key,
/// which is a different job and a different screen.
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)signInProviders {
    return @[
        @{@"id": @"anthropic", @"name": @"Claude",        @"note": @"Claude Pro or Max"},
        @{@"id": @"openai",    @"name": @"ChatGPT",       @"note": @"ChatGPT Plus, Pro or Team"},
        @{@"id": @"google",    @"name": @"Google Antigravity", @"note": @"a Google account"},
        @{@"id": @"xai",       @"name": @"Grok",          @"note": @"X Premium or an xAI plan"},
    ];
}

/// One tappable card per coding app. A button rather than a checkbox on
/// purpose: the whole row is the target, there is nothing to type, and nothing
/// can be mistyped.
- (NSButton *)providerToggle:(NSDictionary<NSString *, NSString *> *)provider {
    NSButton *toggle = [NSButton buttonWithTitle:@"" target:self
                                          action:@selector(providerToggled:)];
    toggle.buttonType = NSButtonTypeSwitch;
    toggle.identifier = provider[@"id"];
    NSMutableAttributedString *label = [[NSMutableAttributedString alloc]
        initWithString:provider[@"name"]
            attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:13
                                                                weight:NSFontWeightMedium],
                         NSForegroundColorAttributeName: NSColor.labelColor}];
    [label appendAttributedString:[[NSAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"   %@", provider[@"note"]]
            attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:12],
                         NSForegroundColorAttributeName: NSColor.secondaryLabelColor}]];
    toggle.attributedTitle = label;
    toggle.state = [self.chosenProviders containsObject:provider[@"id"]]
        ? NSControlStateValueOn : NSControlStateValueOff;
    return toggle;
}

- (void)providerToggled:(NSButton *)sender {
    NSString *identifier = sender.identifier;
    if (identifier == nil) return;
    if (sender.state == NSControlStateValueOn) {
        if (![self.chosenProviders containsObject:identifier]) {
            [self.chosenProviders addObject:identifier];   // keeps their order
        }
    } else {
        [self.chosenProviders removeObject:identifier];
    }
    self.continueToSignIn.enabled = self.chosenProviders.count > 0;
    self.chosenSummary.stringValue = [self chosenSummaryText];
}

- (NSString *)chosenSummaryText {
    if (self.chosenProviders.count == 0) {
        return @"Nothing picked yet. You can skip this and come back later.";
    }
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSDictionary *provider in [self.class signInProviders]) {
        if ([self.chosenProviders containsObject:provider[@"id"]]) {
            [names addObject:provider[@"name"]];
        }
    }
    return [NSString stringWithFormat:@"Signing in to %@, one at a time. Any one "
                                      @"that will not go through can be skipped.",
                                      [names componentsJoinedByString:@", "]];
}

- (NSArray<NSView *> *)codingAppViews {
    if (self.chosenProviders == nil) self.chosenProviders = [NSMutableArray array];

    NSMutableArray<NSView *> *toggles = [NSMutableArray array];
    for (NSDictionary<NSString *, NSString *> *provider in [self.class signInProviders]) {
        [toggles addObject:[self providerToggle:provider]];
    }
    NSStackView *choices = [NSStackView stackViewWithViews:toggles];
    choices.orientation = NSUserInterfaceLayoutOrientationVertical;
    choices.alignment = NSLayoutAttributeLeading;
    choices.spacing = 10;
    choices.edgeInsets = NSEdgeInsetsMake(4, 6, 4, 6);

    self.chosenSummary = [self quiet:[self chosenSummaryText]];

    self.continueToSignIn = [self button:@"Sign in to these"
                                  action:@selector(signInPressed:)];
    self.continueToSignIn.keyEquivalent = @"\r";
    self.continueToSignIn.enabled = self.chosenProviders.count > 0;

    NSButton *later = [self button:@"Skip for now" action:@selector(nextPressed:)];
    NSStackView *actions = [NSStackView stackViewWithViews:@[self.continueToSignIn, later]];
    actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actions.spacing = 10;

    return @[
        [self title:@"Which coding apps do you pay for?"],
        [self body:@"Tick the ones you already have a subscription to. SlopNet signs in "
                   @"to them on your server using your own account — it never buys one "
                   @"for you, and never asks you to type a key."],
        choices,
        self.chosenSummary,
        [self body:@"Each one opens a page in your browser and shows you a code to paste "
                   @"into it. If one will not go through, you can skip that one and carry "
                   @"on — nothing gets stuck waiting."],
        [self quiet:@"Proved end to end on a real server: ChatGPT. The other three use the "
                    @"same browser sign-in their own tool ships with, and SlopNet says so "
                    @"plainly rather than pretending it has tested them."],
        [self separator],
        actions,
        [self quiet:@"Whatever you pick, you come back to your private guide first. "
                    @"It is the one you talk to."],
    ];
}

- (NSArray<NSView *> *)readyViews {
    NSTextField *chatLine = [self body:@"Chat asks the private guide on your server. It is "
                                      @"free to use, answers one question at a time, and "
                                      @"cannot start a build."];
    NSTextField *buildLine = [self body:@"Build asks a paid coding app to write a plan, and "
                                       @"stops. Nothing is coded until you read that plan "
                                       @"and approve it separately."];
    NSMutableArray<NSView *> *views = [NSMutableArray arrayWithArray:@[
        [self title:@"You're ready"],
        [self body:@"Two ways to use SlopNet, and they stay separate:"],
        chatLine,
        buildLine,
        [self quiet:@"Honest limit: the approved build still refuses to start coding agents "
                    @"until a project runner has passed a real test on a server. SlopNet "
                    @"will say so plainly rather than pretend to work."],
    ]];
    if (!self.guideReady) {
        NSTextField *warn = [self body:@"The private guide is not installed yet, so Chat has "
                                      @"nothing to answer with. You can go back and install it."];
        warn.textColor = [NSColor systemOrangeColor];
        [views addObject:warn];
    }
    [views addObject:[self separator]];
    [views addObject:[self footerWithBack:YES
                                  primary:self.guideReady ? @"Start chatting" : @"Close"
                                   action:self.guideReady ? @selector(startChatPressed:)
                                                          : @selector(finishPressed:)]];
    return views;
}

#pragma mark - navigation

- (void)nextPressed:(id)sender {
    switch (self.step) {
        case SlopNetWizardStepWelcome:
            [self showStep:SlopNetWizardStepServer];
            return;
        case SlopNetWizardStepServer: {
            if (![self saveConnection]) return;
            [self showStep:SlopNetWizardStepServerSetup];
            return;
        }
        case SlopNetWizardStepServerSetup:
            [self showStep:SlopNetWizardStepGuide];
            return;
        case SlopNetWizardStepGuide:
            [self showStep:SlopNetWizardStepCodingApp];
            return;
        case SlopNetWizardStepCodingApp:
            [self showStep:SlopNetWizardStepReady];
            return;
        case SlopNetWizardStepReady:
            [self finishPressed:sender];
            return;
    }
}

- (void)backPressed:(id)sender {
    if (self.step == SlopNetWizardStepWelcome) return;
    [self showStep:(SlopNetWizardStep)(self.step - 1)];
}

/// Leave without finishing. Nothing is lost: every step reads what is
/// actually true when the wizard is reopened.
- (void)closePressed:(id)sender {
    [self close];
}

- (void)cancelOperation:(id)sender {   // Esc
    [self close];
}

- (void)finishPressed:(id)sender {
    [self.delegate wizardDidFinish:self];
    [self close];
}

- (void)startChatPressed:(id)sender {
    [self.delegate wizardStartChat:self];
    [self close];
}

/// Sign in to the coding app. The console runs it, because the tool prints
/// a link and a code that need a real browser.
- (void)signInPressed:(id)sender {
    [self.delegate wizard:self signInToCodingApps:[self.chosenProviders copy]];
    [self close];
}

- (void)openSettingsPressed:(id)sender {
    [self.delegate wizardOpenSettings:self];
    [self close];
}

#pragma mark - server step

- (BOOL)validHost:(NSString *)host user:(NSString *)user port:(NSString *)port {
    NSString *hostPattern = @"^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$";
    NSString *userPattern = @"^[A-Za-z_][A-Za-z0-9_-]{0,31}$";
    BOOL hostOK = [[NSRegularExpression regularExpressionWithPattern:hostPattern options:0 error:nil]
        firstMatchInString:host options:0 range:NSMakeRange(0, host.length)] != nil;
    BOOL userOK = [[NSRegularExpression regularExpressionWithPattern:userPattern options:0 error:nil]
        firstMatchInString:user options:0 range:NSMakeRange(0, user.length)] != nil;
    return hostOK && userOK && port.integerValue >= 1 && port.integerValue <= 65535;
}

- (BOOL)saveConnection {
    NSString *host = [self.hostField.stringValue
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *user = self.userField.stringValue.length ? self.userField.stringValue : @"root";
    NSString *port = self.portField.stringValue.length ? self.portField.stringValue : @"22";
    if (![self validHost:host user:user port:port]) {
        self.serverNote.stringValue = @"Check the address and login name. The port is almost "
                                      @"always 22.";
        self.serverNote.textColor = [NSColor systemRedColor];
        return NO;
    }
    self.host = host;
    self.user = user;
    self.port = port;
    // Their own name for it. Falls back to the login name and nothing more —
    // never the address, which is the thing being kept off the screen.
    NSString *name = [self.nameField.stringValue
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (name.length == 0) name = @"My server";
    [NSUserDefaults.standardUserDefaults setObject:name forKey:@"SlopNetServerName"];
    [self.delegate wizard:self rememberHost:host port:port user:user];
    return YES;
}

/// A quiet, read-only "does it answer" check, run right here rather than in
/// the console: it asks nothing of the person and changes nothing on the
/// server, so it does not deserve a whole screen of output.
- (void)checkPressed:(id)sender {
    if (![self saveConnection]) return;
    self.serverNote.stringValue = @"Asking your server…";
    self.serverNote.textColor = [NSColor secondaryLabelColor];

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ssh"];
    task.arguments = @[@"-p", self.port,
                       @"-o", @"BatchMode=yes",
                       @"-o", @"ConnectTimeout=10",
                       @"-o", @"StrictHostKeyChecking=accept-new",
                       [NSString stringWithFormat:@"%@@%@", self.user, self.host],
                       @"echo ok"];
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];
    __weak typeof(self) weakSelf = self;
    task.terminationHandler = ^(NSTask *finished) {
        int status = finished.terminationStatus;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (strongSelf == nil || strongSelf.serverNote == nil) return;
            if (status == 0) {
                strongSelf.serverNote.stringValue = @"●  Your server answered.";
                strongSelf.serverNote.textColor = [NSColor systemGreenColor];
            } else {
                // Not a failure worth stopping on: the next step logs in
                // properly, with a password prompt, in the console.
                strongSelf.serverNote.stringValue =
                    @"No answer without a password yet — that is normal before setup. "
                    @"Continue and SlopNet will log in properly.";
                strongSelf.serverNote.textColor = [NSColor secondaryLabelColor];
            }
        });
    };
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        self.serverNote.stringValue = @"This Mac could not run ssh.";
        self.serverNote.textColor = [NSColor systemRedColor];
    }
}

- (void)prepareServerPressed:(id)sender {
    [self.delegate wizard:self connectToHost:self.host port:self.port user:self.user];
    [self close];
}

#pragma mark - guide step

+ (void)probeGuideOnHost:(NSString *)host
                    port:(NSString *)port
                    user:(NSString *)user
              completion:(void (^)(NSDictionary<NSString *, NSString *> *, NSString *))completion {
    if (host.length == 0) {
        completion(nil, @"No server yet.");
        return;
    }
    // Read-only on purpose: it starts no model, downloads nothing, opens no
    // port, and looks only inside SlopNet's own runtime home.
    NSString *probe =
        @"set -eu; "
         "if ! id -u slopnet >/dev/null 2>&1; then echo 'runtime no'; exit 0; fi; "
         "home=$(getent passwd slopnet | cut -d: -f6); "
         "if [ -z \"$home\" ] || [ ! -d \"$home\" ]; then echo 'runtime no'; exit 0; fi; "
         "echo 'runtime yes'; "
         "if [ -x \"$home/.local/bin/llama\" ]; then echo 'llama yes'; else echo 'llama no'; fi; "
         "config=\"$home/.local/share/slopnet/local-helper.env\"; "
         "if [ -r \"$config\" ]; then sed -n 's/^SLOPNET_LOCAL_HELPER_MODEL=//p' \"$config\" | head -n 1 | sed 's/^/model /'; fi; "
         "df -Pm \"$home\" | awk 'NR==2 {print \"disk \" $4}'; "
         "if command -v free >/dev/null 2>&1; then free -m | awk '/Mem:/ {print \"memory \" $7}'; else echo 'memory unknown'; fi; "
         "if find \"$home/.cache\" -type f -name '*.gguf' -print -quit 2>/dev/null | grep -q .; then echo 'cache yes'; else echo 'cache no'; fi";

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ssh"];
    task.arguments = @[@"-p", port.length ? port : @"22",
                       @"-o", @"BatchMode=yes",
                       @"-o", @"ConnectTimeout=10",
                       @"-o", @"StrictHostKeyChecking=accept-new",
                       [NSString stringWithFormat:@"%@@%@", user.length ? user : @"root", host],
                       probe];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSPipe pipe];
    task.terminationHandler = ^(NSTask *finished) {
        NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        dispatch_async(dispatch_get_main_queue(), ^{
            if (finished.terminationStatus != 0 || text.length == 0) {
                completion(nil, @"Could not ask your server.");
                return;
            }
            NSMutableDictionary<NSString *, NSString *> *values = [NSMutableDictionary dictionary];
            for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
                NSRange split = [line rangeOfString:@" "];
                if (split.location == NSNotFound) continue;
                values[[line substringToIndex:split.location]] =
                    [line substringFromIndex:NSMaxRange(split)];
            }
            completion(values, nil);
        });
    };
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        completion(nil, @"This Mac could not run ssh.");
    }
}

- (void)checkCapacity:(id)sender {
    if (self.capacityNote == nil) return;
    [self.capacitySpinner startAnimation:nil];
    self.capacityNote.stringValue = @"Checking what your server has room for…";
    self.capacityNote.textColor = [NSColor secondaryLabelColor];
    self.installButton.enabled = NO;

    __weak typeof(self) weakSelf = self;
    [SlopNetWizard probeGuideOnHost:self.host port:self.port user:self.user
                         completion:^(NSDictionary<NSString *, NSString *> *values,
                                      NSString *error) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf.capacityNote == nil) return;
        [strongSelf.capacitySpinner stopAnimation:nil];
        [strongSelf applyCapacity:values error:error];
    }];
}

- (void)applyCapacity:(NSDictionary<NSString *, NSString *> *)values error:(NSString *)error {
    if (error != nil) {
        self.capacityNote.stringValue = [error stringByAppendingString:
            @" Check the connection on the previous screen, then try again."];
        self.capacityNote.textColor = [NSColor systemRedColor];
        self.installButton.enabled = NO;
        return;
    }
    if (![values[@"runtime"] isEqualToString:@"yes"]) {
        self.capacityNote.stringValue =
            @"This server has not been prepared yet. Go back one screen and prepare it "
            @"first — the guide needs the private account that step creates.";
        self.capacityNote.textColor = [NSColor systemOrangeColor];
        self.installButton.enabled = NO;
        return;
    }

    NSString *model = values[@"model"];
    if (model.length > 0 && [values[@"llama"] isEqualToString:@"yes"]) {
        // Already proved on this server. Say so and stop asking for a download.
        self.provedModel = model;
        self.guideReady = YES;
        [self showStep:SlopNetWizardStepGuide];
        return;
    }

    NSString *disk = values[@"disk"] ?: @"";
    NSString *memory = values[@"memory"] ?: @"unknown";
    BOOL diskKnown = disk.length > 0;
    BOOL memoryKnown = memory.length > 0 && ![memory isEqualToString:@"unknown"];
    NSString *wanted = [self.modelField.stringValue
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    BOOL isDefault = [wanted isEqualToString:kDefaultGuideModel];

    NSString *found = [NSString stringWithFormat:@"Your server has %@ MiB free storage and "
                       @"%@ MiB free memory.",
                       diskKnown ? disk : @"an unknown amount of",
                       memoryKnown ? memory : @"an unknown amount of"];

    // Only the default model has proved floors. For anything else SlopNet
    // genuinely does not know the download size, so it reports and lets the
    // server-side script make the call — the same position the script takes.
    if (isDefault && diskKnown && disk.integerValue < kGuideDiskFloorMiB) {
        self.capacityNote.stringValue = [NSString stringWithFormat:
            @"%@ That is not enough for IBM Granite 4.1 3B, which needs %ld MiB free so its "
            @"2.1 GB download and cache both fit. Free some space, or choose a smaller "
            @"public model above.", found, (long)kGuideDiskFloorMiB];
        self.capacityNote.textColor = [NSColor systemRedColor];
        self.installButton.enabled = NO;
        return;
    }
    if (isDefault && memoryKnown && memory.integerValue < kGuideMemoryFloorMiB) {
        self.capacityNote.stringValue = [NSString stringWithFormat:
            @"%@ That is not enough memory for IBM Granite 4.1 3B, which needs %ld MiB "
            @"available — its proved run used about 3.9 GiB and SlopNet leaves room for "
            @"the rest of your server. Stop other work on the server, or use a larger one.",
            found, (long)kGuideMemoryFloorMiB];
        self.capacityNote.textColor = [NSColor systemRedColor];
        self.installButton.enabled = NO;
        return;
    }

    NSString *cached = [values[@"cache"] isEqualToString:@"yes"]
        ? @" A model download is already cached there." : @"";
    self.capacityNote.stringValue = isDefault
        ? [NSString stringWithFormat:@"%@ There is room for the default guide.%@", found, cached]
        : [NSString stringWithFormat:@"%@ SlopNet cannot know this model's size in advance, "
                                     @"so your server will show the real figures and ask "
                                     @"again before downloading.%@", found, cached];
    self.capacityNote.textColor = [NSColor secondaryLabelColor];
    self.installButton.enabled = YES;
}

- (BOOL)validModel:(NSString *)model {
    // The same shape the server-side script accepts, so the wizard never lets
    // through something the script will reject a moment later.
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:
        @"^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*(:[A-Za-z0-9][A-Za-z0-9._-]*)?$"
                                                                               options:0 error:nil];
    return [expression firstMatchInString:model options:0
                                    range:NSMakeRange(0, model.length)] != nil;
}

- (void)installGuidePressed:(id)sender {
    NSString *model = [self.modelField.stringValue
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![self validModel:model]) {
        self.capacityNote.stringValue = @"Use a public Hugging Face name in the form "
                                        @"owner/model:quant — not a link, and never a token.";
        self.capacityNote.textColor = [NSColor systemRedColor];
        return;
    }
    [self.delegate wizard:self installGuideModel:model];
    [self close];
}

@end
