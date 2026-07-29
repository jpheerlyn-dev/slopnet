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
#import "SlopNetConsole.h"
#import "SlopNetSettings.h"

static NSString *const kHostKey     = @"SlopNetVPSHost";
static NSString *const kUserKey     = @"SlopNetVPSUser";
static NSString *const kPortKey     = @"SlopNetVPSPort";
static NSString *const kReadyKey    = @"SlopNetVPSReady";   // setup finished cleanly
static NSString *const kProjectsKey = @"SlopNetProjects";   // names we have built

@interface SlopNetAppDelegate : NSObject <NSApplicationDelegate, SlopNetConsoleDelegate, SlopNetSettingsDelegate>
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
@property(nonatomic, strong) NSTextField *entry;
@property(nonatomic, strong) NSButton *sendButton;

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

    NSButton *checkButton = [self sidebarButton:@"⇄   Check connection"
                                         action:@selector(checkConnection:)];
    NSButton *clearButton = [self sidebarButton:@"⌫   Clear screen"
                                         action:@selector(clearConsole:)];
    NSButton *helpButton = [self sidebarButton:@"?   Getting a server"
                                        action:@selector(openServerHelp:)];

    NSTextField *historyTitle = [self label:@"PROJECTS" size:10 grey:YES];
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

    NSStackView *sidebar = [NSStackView stackViewWithViews:@[
        title, status,
        [self separator],
        checkButton, clearButton, helpButton,
        [self separator],
        historyTitle, self.historyStack,
        spacer,
        [self separator],
        self.settingsToggle,
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

    NSStackView *main = [NSStackView stackViewWithViews:@[self.console, chatBar]];
    main.orientation = NSUserInterfaceLayoutOrientationVertical;
    main.alignment = NSLayoutAttributeLeading;
    main.spacing = 10;
    main.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
    [main setHuggingPriority:NSLayoutPriorityDefaultLow
              forOrientation:NSLayoutConstraintOrientationVertical];
    [NSLayoutConstraint activateConstraints:@[
        [self.console.widthAnchor constraintEqualToAnchor:main.widthAnchor constant:-32],
        [chatBar.widthAnchor constraintEqualToAnchor:main.widthAnchor constant:-32],
        [self.console.heightAnchor constraintGreaterThanOrEqualToConstant:280],
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
    if (ready) {
        self.statusDot.textColor = [NSColor systemGreenColor];
        self.statusText.stringValue = [NSString stringWithFormat:@"Ready — %@", self.host];
    } else {
        self.statusDot.textColor = [NSColor systemGrayColor];
        self.statusText.stringValue = @"No server yet";
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
        self.entry.placeholderString = @"Open Settings to connect a server first";
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
    NSString *name = [sender.title stringByReplacingOccurrencesOfString:@"•  " withString:@""];
    self.projectName.stringValue = name;
    [self.console note:[NSString stringWithFormat:
        @"\nUsing project “%@”. Say what you want done to it and press Return.", name]];
    [self.window makeFirstResponder:self.entry];
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
            @"Name your project in the small box below, say what you want built, "
            @"and press Return.", self.host]];
    } else {
        [self.console note:@"Welcome. Press Settings at the bottom left to connect "
                           @"your server.\nEverything that happens appears here, and "
                           @"you can answer any question in the box below."];
    }
}

#pragma mark - actions

- (void)openSettings:(id)sender {
    self.settings = [[SlopNetSettings alloc] initWithHost:self.host
                                                     port:self.port
                                                     user:self.username
                                                connected:[self isReady]];
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

- (void)clearConsole:(id)sender { [self.console clear]; }

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
    [self.console note:@"\n=== Preparing your server ==="];
    self.setupRunning = YES;
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
    [self.console note:[NSString stringWithFormat:@"\n=== %@ ===", title]];
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

- (void)checkConnection:(id)sender {
    if (self.busy || ![self connectionValid]) return;
    [self.console note:@"\n=== Checking the connection ==="];
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

/// The chat box. Running → the text answers the question. Idle → the text
/// is the thing you want built.
- (void)sendPressed:(id)sender {
    if (self.busy) {
        [self.console sendLine:self.entry.stringValue];
        self.entry.stringValue = @"";
        return;
    }
    if (![self isReady]) {
        [self.console note:@"\nConnect a server first — press Settings, bottom left."];
        [self openSettings:nil];
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
                           arguments:@[script, self.host, self.port,
                                       self.username, name, idea]]) {
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
    // A server counts as ready only when SETUP itself finished cleanly —
    // not because someone typed an address. That is what makes the green
    // dot in the sidebar worth trusting.
    if (self.setupRunning) {
        self.setupRunning = NO;
        if (status == 0) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kReadyKey];
            [self.console note:@"Your server is ready. Name a project below and say what "
                               @"you want built — you will not be asked to set it up again."];
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
