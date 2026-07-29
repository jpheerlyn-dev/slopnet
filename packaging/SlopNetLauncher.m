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
// have already done. Once a VPS is set up, its form goes away into
// Settings and the window offers the next real step instead.

#import <Cocoa/Cocoa.h>
#import "SlopNetConsole.h"

static NSString *const kHostKey     = @"SlopNetVPSHost";
static NSString *const kUserKey     = @"SlopNetVPSUser";
static NSString *const kPortKey     = @"SlopNetVPSPort";
static NSString *const kReadyKey    = @"SlopNetVPSReady";   // setup finished cleanly
static NSString *const kProjectsKey = @"SlopNetProjects";   // names we have built

@interface SlopNetAppDelegate : NSObject <NSApplicationDelegate, SlopNetConsoleDelegate>
@property(nonatomic, strong) NSWindow *window;

// sidebar
@property(nonatomic, strong) NSTextField *statusDot;
@property(nonatomic, strong) NSTextField *statusText;
@property(nonatomic, strong) NSStackView *historyStack;
@property(nonatomic, strong) NSButton *settingsToggle;

// the VPS form: hidden once connected
@property(nonatomic, strong) NSBox *settingsBox;
@property(nonatomic, strong) NSTextField *host;
@property(nonatomic, strong) NSTextField *username;
@property(nonatomic, strong) NSTextField *port;

// main
@property(nonatomic, strong) SlopNetConsole *console;
@property(nonatomic, strong) NSTextField *projectName;
@property(nonatomic, strong) NSTextField *entry;
@property(nonatomic, strong) NSButton *sendButton;

@property(nonatomic, assign) BOOL settingsOpen;
@property(nonatomic, assign) BOOL busy;
@property(nonatomic, assign) BOOL setupRunning;
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

- (NSButton *)sidebarButton:(NSString *)title action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
    button.title = title;
    button.target = self;
    button.action = action;
    button.bezelStyle = NSBezelStyleInline;
    button.alignment = NSTextAlignmentLeft;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.heightAnchor constraintEqualToConstant:26].active = YES;
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
    [line.widthAnchor constraintEqualToConstant:200].active = YES;
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

    self.settingsToggle = [self sidebarButton:@"⚙   VPS settings"
                                       action:@selector(toggleSettings:)];
    NSButton *checkButton = [self sidebarButton:@"⇄   Check connection"
                                         action:@selector(checkConnection:)];
    NSButton *clearButton = [self sidebarButton:@"⌫   Clear screen"
                                         action:@selector(clearConsole:)];

    NSTextField *historyTitle = [self label:@"PROJECTS" size:10 grey:YES];
    self.historyStack = [NSStackView stackViewWithViews:@[]];
    self.historyStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.historyStack.alignment = NSLayoutAttributeLeading;
    self.historyStack.spacing = 1;

    NSStackView *sidebar = [NSStackView stackViewWithViews:@[
        title, status,
        [self separator],
        self.settingsToggle, checkButton, clearButton,
        [self separator],
        historyTitle, self.historyStack,
        [self label:[NSString stringWithFormat:@"v%@", version] size:10 grey:YES]]];
    sidebar.orientation = NSUserInterfaceLayoutOrientationVertical;
    sidebar.alignment = NSLayoutAttributeLeading;
    sidebar.spacing = 8;
    sidebar.edgeInsets = NSEdgeInsetsMake(18, 14, 14, 14);
    [sidebar setHuggingPriority:NSLayoutPriorityDefaultLow
                 forOrientation:NSLayoutConstraintOrientationVertical];
    return sidebar;
}

- (NSView *)buildMain {
    self.host = [self field:@"the IP address from your VPS welcome email" value:nil];
    self.username = [self field:@"root" value:@"root"];
    self.port = [self field:@"22" value:@"22"];

    NSButton *setupButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    setupButton.title = @"Set up this VPS";
    setupButton.bezelStyle = NSBezelStyleRounded;
    setupButton.target = self;
    setupButton.action = @selector(beginSetup:);
    NSButton *forgetButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    forgetButton.title = @"Forget";
    forgetButton.bezelStyle = NSBezelStyleRounded;
    forgetButton.target = self;
    forgetButton.action = @selector(forgetConnection:);
    NSStackView *setupButtons = [NSStackView stackViewWithViews:@[setupButton, forgetButton]];
    setupButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    setupButtons.spacing = 8;

    NSStackView *settingsStack = [NSStackView stackViewWithViews:@[
        [self label:@"Your VPS password is never typed or stored here. The first "
                    @"connection asks for it below, and it goes straight to your VPS."
               size:11 grey:YES],
        [self row:@"VPS address" control:self.host width:300],
        [self row:@"Login name" control:self.username width:180],
        [self row:@"Port" control:self.port width:80],
        setupButtons]];
    settingsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    settingsStack.alignment = NSLayoutAttributeLeading;
    settingsStack.spacing = 7;
    settingsStack.edgeInsets = NSEdgeInsetsMake(10, 12, 12, 12);

    self.settingsBox = [[NSBox alloc] initWithFrame:NSZeroRect];
    self.settingsBox.title = @"VPS settings";
    self.settingsBox.contentView = settingsStack;
    self.settingsBox.translatesAutoresizingMaskIntoConstraints = NO;

    self.console = [[SlopNetConsole alloc] initWithFrame:NSZeroRect];
    self.console.delegate = self;
    self.console.translatesAutoresizingMaskIntoConstraints = NO;

    // The chat bar. What it does depends on what is happening: answer the
    // running program's question, or describe the thing you want built.
    self.projectName = [self field:@"project name" value:nil];
    [self.projectName.widthAnchor constraintEqualToConstant:150].active = YES;
    self.entry = [self field:@"Describe what you want built, then press Return" value:nil];
    self.entry.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.entry.target = self;
    self.entry.action = @selector(sendPressed:);
    [self.entry setContentHuggingPriority:NSLayoutPriorityDefaultLow
                           forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.sendButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    self.sendButton.title = @"Build it";
    self.sendButton.bezelStyle = NSBezelStyleRounded;
    self.sendButton.keyEquivalent = @"\r";
    self.sendButton.target = self;
    self.sendButton.action = @selector(sendPressed:);

    NSStackView *chatBar = [NSStackView stackViewWithViews:@[
        self.projectName, self.entry, self.sendButton]];
    chatBar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    chatBar.alignment = NSLayoutAttributeCenterY;
    chatBar.spacing = 8;
    chatBar.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *main = [NSStackView stackViewWithViews:@[
        self.settingsBox, self.console, chatBar]];
    main.orientation = NSUserInterfaceLayoutOrientationVertical;
    main.alignment = NSLayoutAttributeLeading;
    main.spacing = 10;
    main.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
    [main setHuggingPriority:NSLayoutPriorityDefaultLow
              forOrientation:NSLayoutConstraintOrientationVertical];
    [NSLayoutConstraint activateConstraints:@[
        [self.settingsBox.widthAnchor constraintEqualToAnchor:main.widthAnchor constant:-32],
        [self.console.widthAnchor constraintEqualToAnchor:main.widthAnchor constant:-32],
        [chatBar.widthAnchor constraintEqualToAnchor:main.widthAnchor constant:-32],
        [self.console.heightAnchor constraintGreaterThanOrEqualToConstant:240],
    ]];
    return main;
}

#pragma mark - one place decides what the window shows

- (BOOL)isReady {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kReadyKey] &&
           self.host.stringValue.length > 0;
}

- (void)refreshState {
    BOOL ready = [self isReady];
    BOOL showSettings = self.settingsOpen || !ready;

    self.settingsBox.hidden = !showSettings;
    self.settingsToggle.title = showSettings ? @"⚙   Hide VPS settings"
                                             : @"⚙   VPS settings";

    if (ready) {
        self.statusDot.textColor = [NSColor systemGreenColor];
        self.statusText.stringValue = [NSString stringWithFormat:@"Ready — %@",
                                       self.host.stringValue];
    } else {
        self.statusDot.textColor = [NSColor systemGrayColor];
        self.statusText.stringValue = @"No VPS yet";
    }

    self.projectName.hidden = !ready;
    if (self.busy) {
        self.entry.placeholderString =
            @"Type your answer here and press Return (for example: y)";
        self.sendButton.title = @"Answer";
    } else if (ready) {
        self.entry.placeholderString = @"Describe what you want built, then press Return";
        self.sendButton.title = @"Build it";
    } else {
        self.entry.placeholderString = @"Set up a VPS first — the form is above";
        self.sendButton.title = @"Build it";
    }
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
    NSArray<NSString *> *projects =
        [[NSUserDefaults standardUserDefaults] arrayForKey:kProjectsKey];
    if (projects.count == 0) {
        [self.historyStack addArrangedSubview:[self label:@"nothing yet" size:11 grey:YES]];
        return;
    }
    for (NSString *name in [projects reverseObjectEnumerator]) {
        [self.historyStack addArrangedSubview:
            [self sidebarButton:[@"•  " stringByAppendingString:name]
                         action:@selector(reuseProject:)]];
    }
}

- (void)reuseProject:(NSButton *)sender {
    NSString *name = [sender.title stringByReplacingOccurrencesOfString:@"•  "
                                                             withString:@""];
    self.projectName.stringValue = name;
    [self.console note:[NSString stringWithFormat:
        @"\nUsing project “%@”. Say what you want done to it and press Return.", name]];
    [self.window makeFirstResponder:self.entry];
}

#pragma mark - remembering (never a password, never inside the repo)

// Only the three details from a provider's welcome email are kept, in
// macOS's own preferences for this app. A password is NEVER stored: it goes
// from the console straight to your VPS. The SSH key that setup creates
// stays in the macOS Keychain. Nothing is written into the SlopNet folder,
// so none of it can be committed or uploaded by accident.
- (void)remember {
    NSUserDefaults *store = [NSUserDefaults standardUserDefaults];
    [store setObject:self.host.stringValue forKey:kHostKey];
    [store setObject:self.username.stringValue forKey:kUserKey];
    [store setObject:self.port.stringValue forKey:kPortKey];
}

- (void)recall {
    NSUserDefaults *store = [NSUserDefaults standardUserDefaults];
    NSString *savedHost = [store stringForKey:kHostKey];
    NSString *savedUser = [store stringForKey:kUserKey];
    NSString *savedPort = [store stringForKey:kPortKey];
    if (savedHost.length) self.host.stringValue = savedHost;
    if (savedUser.length) self.username.stringValue = savedUser;
    if (savedPort.length) self.port.stringValue = savedPort;

    if ([self isReady]) {
        [self.console note:[NSString stringWithFormat:
            @"Your VPS (%@) is set up and ready.\n"
            @"Name your project in the small box below, say what you want built, "
            @"and press Return.", savedHost]];
    } else {
        [self.console note:@"Welcome. Fill in your VPS details above and press "
                           @"“Set up this VPS”.\nEverything that happens appears here, "
                           @"and you can answer any question in the box below."];
    }
}

- (void)forgetConnection:(id)sender {
    if (self.busy) return;
    NSUserDefaults *store = [NSUserDefaults standardUserDefaults];
    for (NSString *key in @[kHostKey, kUserKey, kPortKey, kReadyKey]) {
        [store removeObjectForKey:key];
    }
    self.host.stringValue = @"";
    self.username.stringValue = @"root";
    self.port.stringValue = @"22";
    self.settingsOpen = YES;
    [self.console note:@"\nForgotten on this Mac. Your VPS itself is untouched, and "
                       @"no password was ever stored."];
    [self refreshState];
}

#pragma mark - actions

- (void)toggleSettings:(id)sender {
    self.settingsOpen = !self.settingsOpen;
    [self refreshState];
}

- (void)clearConsole:(id)sender { [self.console clear]; }

- (BOOL)matches:(NSString *)value pattern:(NSString *)pattern {
    NSRange range = NSMakeRange(0, value.length);
    NSRegularExpression *expression =
        [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    return [expression firstMatchInString:value options:0 range:range] != nil;
}

- (BOOL)connectionValid {
    if (![self matches:self.host.stringValue pattern:@"^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$"] ||
        ![self matches:self.username.stringValue pattern:@"^[A-Za-z_][A-Za-z0-9_-]{0,31}$"] ||
        self.port.integerValue < 1 || self.port.integerValue > 65535) {
        [self.console note:@"\nCheck the VPS address and login name against your "
                           @"provider's welcome email. The port is almost always 22."];
        self.settingsOpen = YES;
        [self refreshState];
        return NO;
    }
    return YES;
}

- (NSString *)helper:(NSString *)name {
    return [[NSBundle mainBundle] pathForResource:name ofType:@"sh"];
}

- (void)beginSetup:(id)sender {
    if (self.busy || ![self connectionValid]) return;
    NSString *script = [self helper:@"slopnet-vps-onboard"];
    if (script == nil) {
        [self.console note:@"The VPS setup helper is missing from this app. Build it again."];
        return;
    }
    [self remember];
    [self.console note:@"\n=== Setting up your VPS ==="];
    self.setupRunning = YES;
    [self setBusy:YES];
    if (![self.console runExecutable:@"/bin/bash"
                           arguments:@[script, self.host.stringValue,
                                       self.port.stringValue, self.username.stringValue]]) {
        self.setupRunning = NO;
        [self setBusy:NO];
    }
}

- (void)checkConnection:(id)sender {
    if (self.busy || ![self connectionValid]) return;
    [self.console note:@"\n=== Checking the connection ==="];
    [self setBusy:YES];
    NSString *target = [NSString stringWithFormat:@"%@@%@",
                        self.username.stringValue, self.host.stringValue];
    if (![self.console runExecutable:@"/usr/bin/ssh"
                           arguments:@[@"-p", self.port.stringValue,
                                       @"-o", @"BatchMode=yes",
                                       @"-o", @"ConnectTimeout=10",
                                       @"-o", @"StrictHostKeyChecking=accept-new",
                                       target, @"echo SlopNet reached your VPS."]]) {
        [self setBusy:NO];
    }
}

/// The chat box. Running → the text answers the question. Idle → the text
/// is the thing you want built.
- (void)sendPressed:(id)sender {
    if (self.busy) {
        [self.console sendLine:self.entry.stringValue];
        self.entry.stringValue = @"";
        return;
    }
    if (![self isReady]) {
        [self.console note:@"\nSet up a VPS first — press “VPS settings” on the left."];
        self.settingsOpen = YES;
        [self refreshState];
        return;
    }
    NSString *name = [self.projectName.stringValue stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *idea = [self.entry.stringValue stringByTrimmingCharactersInSet:
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
    NSString *script = [self helper:@"slopnet-vps-project"];
    if (script == nil) {
        [self.console note:@"The project helper is missing from this app. Build it again."];
        return;
    }
    [self rememberProject:name];
    [self.console note:[NSString stringWithFormat:@"\n=== %@ — %@ ===", name, idea]];
    self.entry.stringValue = @"";
    [self setBusy:YES];
    if (![self.console runExecutable:@"/bin/bash"
                           arguments:@[script, self.host.stringValue, self.port.stringValue,
                                       self.username.stringValue, name, idea]]) {
        [self setBusy:NO];
    }
}

- (void)rememberProject:(NSString *)name {
    NSUserDefaults *store = [NSUserDefaults standardUserDefaults];
    NSMutableArray *projects = [([store arrayForKey:kProjectsKey] ?: @[]) mutableCopy];
    [projects removeObject:name];
    [projects addObject:name];
    while (projects.count > 12) [projects removeObjectAtIndex:0];
    [store setObject:projects forKey:kProjectsKey];
}

#pragma mark - console callbacks

- (void)console:(SlopNetConsole *)console finishedWithStatus:(int)status {
    // A VPS counts as ready only when SETUP itself finished cleanly — not
    // because someone typed an address. That is what makes the green dot
    // in the sidebar worth trusting.
    if (self.setupRunning) {
        self.setupRunning = NO;
        if (status == 0) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kReadyKey];
            self.settingsOpen = NO;
            [self.console note:@"Your VPS is ready. The setup form is tucked away under "
                               @"“VPS settings” on the left — you will not be asked again."];
        }
    }
    [self setBusy:NO];
    if (status != 0) {
        [self.console note:@"Nothing was left half-done. Read the last few lines above, "
                           @"fix what they mention, and try again."];
    }
    [self.window makeFirstResponder:self.entry];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app { return YES; }

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        SlopNetAppDelegate *delegate = [[SlopNetAppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
    }
    return 0;
}
