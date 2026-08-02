#import "SlopNetTools.h"
#import "SlopNetBrand.h"

@interface SlopNetTools ()
@property(nonatomic, copy) NSString *host;
@property(nonatomic, copy) NSString *port;
@property(nonatomic, copy) NSString *user;
@property(nonatomic, assign) BOOL connected;
@property(nonatomic, strong) NSArray<NSDictionary *> *tools;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *present;
@property(nonatomic, strong) NSGridView *libraryGrid;
@property(nonatomic, strong) NSGridView *installedGrid;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSTextField *> *libraryStatus;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSButton *> *libraryAction;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSTextField *> *installedStatus;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSButton *> *installedOpen;
@end

@implementation SlopNetTools

- (instancetype)initWithHost:(NSString *)host
                        port:(NSString *)port
                        user:(NSString *)user
                   connected:(BOOL)connected {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 640, 520)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = @"Tools";
    window.minSize = NSMakeSize(480, 320);
    [SlopNetBrand applyTerminalChromeToWindow:window];
    // Sheets keep a visible title; the main window hides it under glass.
    window.titleVisibility = NSWindowTitleVisible;
    self = [super initWithWindow:window];
    if (!self) return nil;
    _host = [host copy] ?: @"";
    _port = port.length ? [port copy] : @"22";
    _user = user.length ? [user copy] : @"root";
    _connected = connected;
    _tools = [self loadTools];
    _present = [NSMutableDictionary dictionary];
    _libraryStatus = [NSMutableDictionary dictionary];
    _libraryAction = [NSMutableDictionary dictionary];
    _installedStatus = [NSMutableDictionary dictionary];
    _installedOpen = [NSMutableDictionary dictionary];
    [self build];
    return self;
}

#pragma mark - tools.json

- (NSArray<NSDictionary *> *)loadTools {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"tools" ofType:@"json"];
    if (path == nil) return @[];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data == nil) return @[];
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [root isKindOfClass:NSDictionary.class] ? (root[@"tools"] ?: @[]) : @[];
}

/// Antigravity ships with the server and has no install command of its own.
/// Saying "No command yet" reads as unfinished work; it is already there.
- (BOOL)isPreinstalled:(NSDictionary *)tool {
    return [tool[@"id"] isEqualToString:@"antigravity"];
}

#pragma mark - little builders

- (NSTextField *)label:(NSString *)text size:(CGFloat)size grey:(BOOL)grey bold:(BOOL)bold {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size];
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    if (grey) label.textColor = [NSColor secondaryLabelColor];
    return label;
}

- (NSTextField *)helpText:(NSString *)text {
    NSTextField *label = [self label:text size:11 grey:YES bold:NO];
    label.maximumNumberOfLines = 0;
    label.preferredMaxLayoutWidth = 560;
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

#pragma mark - layout

- (void)build {
    self.libraryGrid = [NSGridView gridViewWithNumberOfColumns:4 rows:0];
    self.libraryGrid.translatesAutoresizingMaskIntoConstraints = NO;
    self.libraryGrid.rowSpacing = 8;
    self.libraryGrid.columnSpacing = 14;

    self.installedGrid = [NSGridView gridViewWithNumberOfColumns:3 rows:0];
    self.installedGrid.translatesAutoresizingMaskIntoConstraints = NO;
    self.installedGrid.rowSpacing = 8;
    self.installedGrid.columnSpacing = 14;

    [self rebuildLibrary];
    [self rebuildInstalled];

    NSButton *recheck = [self button:@"Check what is installed"
                             action:@selector(refreshPressed:)];
    recheck.enabled = self.connected;

    NSStackView *libraryPage = [NSStackView stackViewWithViews:@[
        [self helpText:@"Tools SlopNet can put on your server. Installing runs in "
                       @"the main window so you can watch exactly what happens."],
        recheck,
        self.libraryGrid,
    ]];
    libraryPage.orientation = NSUserInterfaceLayoutOrientationVertical;
    libraryPage.alignment = NSLayoutAttributeLeading;
    libraryPage.spacing = 12;
    libraryPage.edgeInsets = NSEdgeInsetsMake(14, 16, 14, 16);
    libraryPage.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *installedPage = [NSStackView stackViewWithViews:@[
        [self helpText:@"Open a tool in its own terminal tab. Granite stays one "
                       @"click away."],
        self.installedGrid,
    ]];
    installedPage.orientation = NSUserInterfaceLayoutOrientationVertical;
    installedPage.alignment = NSLayoutAttributeLeading;
    installedPage.spacing = 12;
    installedPage.edgeInsets = NSEdgeInsetsMake(14, 16, 14, 16);
    installedPage.translatesAutoresizingMaskIntoConstraints = NO;

    // Installed first: open what you already have. Library is for adding more.
    NSTabViewItem *installedItem = [[NSTabViewItem alloc] initWithIdentifier:@"installed"];
    installedItem.label = @"Installed";
    installedItem.view = installedPage;

    NSTabViewItem *libraryItem = [[NSTabViewItem alloc] initWithIdentifier:@"library"];
    libraryItem.label = @"Library";
    libraryItem.view = libraryPage;

    NSTabView *tabs = [[NSTabView alloc] initWithFrame:NSZeroRect];
    tabs.translatesAutoresizingMaskIntoConstraints = NO;
    [tabs addTabViewItem:installedItem];
    [tabs addTabViewItem:libraryItem];

    NSButton *done = [self button:@"Done" action:@selector(closePressed:)];
    done.keyEquivalent = @"\r";
    [done.widthAnchor constraintGreaterThanOrEqualToConstant:90].active = YES;

    NSStackView *page = [NSStackView stackViewWithViews:@[tabs, done]];
    page.orientation = NSUserInterfaceLayoutOrientationVertical;
    page.alignment = NSLayoutAttributeLeading;
    page.spacing = 12;
    page.edgeInsets = NSEdgeInsetsMake(16, 18, 16, 18);
    page.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *content = self.window.contentView;
    [content addSubview:page];
    [NSLayoutConstraint activateConstraints:@[
        [page.topAnchor constraintEqualToAnchor:content.topAnchor],
        [page.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [page.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [page.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [tabs.widthAnchor constraintEqualToAnchor:page.widthAnchor constant:-36],
        [tabs.heightAnchor constraintGreaterThanOrEqualToConstant:360],
    ]];
}

- (void)rebuildLibrary {
    while (self.libraryGrid.numberOfRows > 0) {
        [self.libraryGrid removeRowAtIndex:0];
    }
    [self.libraryStatus removeAllObjects];
    [self.libraryAction removeAllObjects];

    if (self.tools.count == 0) {
        [self.libraryGrid addRowWithViews:@[
            [self label:@"No tools list found in this app." size:12 grey:YES bold:NO]]];
        return;
    }

    NSGridRow *header = [self.libraryGrid addRowWithViews:@[
        [self label:@"TOOL" size:10 grey:YES bold:NO],
        [self label:@"ON YOUR SERVER" size:10 grey:YES bold:NO],
        [self label:@"" size:10 grey:YES bold:NO],
        [self label:@"SUBSCRIPTION" size:10 grey:YES bold:NO]]];
    header.bottomPadding = 3;

    for (NSDictionary *tool in self.tools) {
        NSString *toolID = tool[@"id"] ?: @"";
        NSTextField *name = [self label:tool[@"name"] ?: toolID size:12 grey:NO bold:NO];

        NSTextField *status = [self label:self.connected ? @"unknown" : @"connect first"
                                     size:11 grey:YES bold:NO];
        self.libraryStatus[toolID] = status;

        NSString *install = tool[@"install"] ?: @"";
        NSString *provider = [SlopNetBrand providerForTool:toolID];
        BOOL signsIn = [SlopNetTools signInSupportedForProvider:provider];
        BOOL preinstalled = [self isPreinstalled:tool];
        BOOL canPrepare = install.length > 0 || signsIn;
        NSString *actionTitle;
        if (signsIn) {
            actionTitle = @"Set up";
        } else if (install.length > 0) {
            actionTitle = @"Install";
        } else if (preinstalled) {
            actionTitle = @"Already installed";
        } else {
            actionTitle = @"No command yet";
        }
        NSButton *action = [self button:actionTitle action:@selector(installPressed:)];
        action.identifier = toolID;
        action.enabled = canPrepare && self.connected;
        if (preinstalled && !canPrepare) {
            action.toolTip = @"This tool is already on the server after setup. "
                             @"There is nothing further to install.";
        } else if (!canPrepare) {
            action.toolTip = @"Nobody has verified this tool's install command yet, so "
                             @"SlopNet will not guess one. Add it to tools.json.";
        }
        self.libraryAction[toolID] = action;

        NSTextField *subscription = [self label:tool[@"subscription"] ?: @""
                                           size:10 grey:YES bold:NO];
        [self.libraryGrid addRowWithViews:@[name, status, action, subscription]];
    }
}

- (void)rebuildInstalled {
    while (self.installedGrid.numberOfRows > 0) {
        [self.installedGrid removeRowAtIndex:0];
    }
    [self.installedStatus removeAllObjects];
    [self.installedOpen removeAllObjects];

    NSMutableArray<NSDictionary *> *launchable = [NSMutableArray array];
    for (NSDictionary *tool in self.tools) {
        NSString *runs = tool[@"run"] ?: @"";
        if (runs.length > 0) [launchable addObject:tool];
    }

    if (launchable.count == 0) {
        [self.installedGrid addRowWithViews:@[
            [self label:@"No tools in this app have a safe standalone launch."
                   size:12 grey:YES bold:NO]]];
        return;
    }

    NSGridRow *header = [self.installedGrid addRowWithViews:@[
        [self label:@"TOOL" size:10 grey:YES bold:NO],
        [self label:@"ON YOUR SERVER" size:10 grey:YES bold:NO],
        [self label:@"" size:10 grey:YES bold:NO]]];
    header.bottomPadding = 3;

    for (NSDictionary *tool in launchable) {
        NSString *toolID = tool[@"id"] ?: @"";
        NSTextField *name = [self label:tool[@"name"] ?: toolID size:12 grey:NO bold:NO];
        NSTextField *status = [self label:self.connected ? @"unknown" : @"connect first"
                                     size:11 grey:YES bold:NO];
        self.installedStatus[toolID] = status;

        NSButton *open = [self button:@"Open" action:@selector(openPressed:)];
        open.identifier = toolID;
        open.enabled = self.connected;
        self.installedOpen[toolID] = open;

        [self.installedGrid addRowWithViews:@[name, status, open]];
    }
}

- (void)presentFrom:(NSWindow *)parent {
    [parent beginSheet:self.window completionHandler:nil];
    if (self.connected) [self refreshToolStatus];
}

#pragma mark - actions

- (void)closePressed:(id)sender {
    [self.window.sheetParent endSheet:self.window];
}

- (void)refreshPressed:(id)sender { [self refreshToolStatus]; }

+ (BOOL)signInSupportedForProvider:(NSString *)provider {
    static NSSet *supported;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        supported = [NSSet setWithArray:@[@"openai", @"anthropic", @"xai"]];
    });
    return provider != nil && [supported containsObject:provider];
}

- (void)installPressed:(NSButton *)sender {
    NSString *toolID = sender.identifier;
    for (NSDictionary *tool in self.tools) {
        if (![tool[@"id"] isEqualToString:toolID]) continue;
        NSString *provider = [SlopNetBrand providerForTool:toolID];
        if ([SlopNetTools signInSupportedForProvider:provider]) {
            [self.delegate tools:self signInToProvider:provider];
            [self closePressed:nil];
            return;
        }
        NSString *install = tool[@"install"] ?: @"";
        if (install.length == 0) return;
        [self.delegate tools:self runOnServer:install
                       title:[NSString stringWithFormat:@"Installing %@",
                              tool[@"name"] ?: toolID]];
        [self closePressed:nil];
        return;
    }
}

- (void)openPressed:(NSButton *)sender {
    NSString *toolID = sender.identifier ?: @"";
    for (NSDictionary *tool in self.tools) {
        if (![tool[@"id"] isEqualToString:toolID]) continue;
        NSString *runs = tool[@"run"] ?: @"";
        if (runs.length == 0) return;
        if ([self.delegate tools:self openOnServer:runs
                           title:tool[@"name"] ?: toolID]) {
            [self closePressed:nil];
        }
        return;
    }
}

#pragma mark - asking the server what it has

- (void)applyStatus:(NSString *)toolID present:(BOOL)present {
    NSString *text = present ? @"●  installed" : @"not installed";
    NSColor *colour = present ? [NSColor systemGreenColor]
                              : [NSColor secondaryLabelColor];
    NSTextField *library = self.libraryStatus[toolID];
    if (library) {
        library.stringValue = text;
        library.textColor = colour;
    }
    NSTextField *installed = self.installedStatus[toolID];
    if (installed) {
        installed.stringValue = text;
        installed.textColor = colour;
    }
    NSButton *action = self.libraryAction[toolID];
    if (action && present && action.enabled &&
        ([action.title isEqualToString:@"Install"] ||
         [action.title isEqualToString:@"Reinstall"])) {
        action.title = @"Reinstall";
    }
    self.present[toolID] = @(present);
}

- (void)refreshToolStatus {
    if (!self.connected || self.host.length == 0) {
        for (NSTextField *status in self.libraryStatus.allValues) {
            status.stringValue = @"connect first";
        }
        for (NSTextField *status in self.installedStatus.allValues) {
            status.stringValue = @"connect first";
        }
        return;
    }
    for (NSTextField *status in self.libraryStatus.allValues) {
        status.stringValue = @"checking…";
    }
    for (NSTextField *status in self.installedStatus.allValues) {
        status.stringValue = @"checking…";
    }

    // One quiet, non-interactive SSH call. It only asks where commands are;
    // it changes nothing. Interactive work belongs in the main console.
    NSMutableString *probe = [NSMutableString stringWithString:
        @"PATH=/usr/sbin:/usr/bin:/sbin:/bin; export PATH; "];
    for (NSDictionary *tool in self.tools) {
        NSString *check = tool[@"check"] ?: @"";
        if (check.length == 0) continue;
        // Looked for on the runtime account's PATH, because that is where the
        // installs go. Checking root's PATH found only the one tool whose
        // installer had symlinked itself machine-wide, so the list said "not
        // installed" for things that were.
        [probe appendFormat:
            @"if /usr/sbin/runuser -u slopnet -- /usr/bin/env HOME=/home/slopnet "
            @"PATH=/home/slopnet/.local/bin:/home/slopnet/.kimi-code/bin:"
            @"/home/slopnet/.local/node_modules/.bin:"
            @"/usr/local/bin:/usr/bin:/bin "
            @"/bin/sh -c 'command -v %@' >/dev/null 2>&1; then echo '%@ yes'; "
            @"else echo '%@ no'; fi; ",
            check, tool[@"id"], tool[@"id"]];
    }
    if (![self.user isEqualToString:@"root"]) {
        NSString *encoded = [[[probe copy] dataUsingEncoding:NSUTF8StringEncoding]
            base64EncodedStringWithOptions:0];
        probe = [[NSString stringWithFormat:
            @"/usr/bin/printf %%s '%@' | /usr/bin/base64 -d | "
             "/usr/bin/sudo -n /bin/sh", encoded] mutableCopy];
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ssh"];
    NSString *identity = [NSHomeDirectory() stringByAppendingPathComponent:
                          @".ssh/slopnet_vps_ed25519"];
    NSString *knownHosts = [NSHomeDirectory() stringByAppendingPathComponent:
                            @".ssh/slopnet_vps_known_hosts"];
    task.arguments = @[@"-i", identity,
                       @"-o", @"IdentitiesOnly=yes",
                       @"-o", [@"UserKnownHostsFile=" stringByAppendingString:knownHosts],
                       @"-p", self.port,
                       @"-o", @"BatchMode=yes",
                       @"-o", @"ConnectTimeout=10",
                       @"-o", @"StrictHostKeyChecking=accept-new",
                       [NSString stringWithFormat:@"%@@%@", self.user, self.host],
                       probe];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSPipe pipe];

    __weak typeof(self) weakSelf = self;
    task.terminationHandler = ^(NSTask *finished) {
        NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
        NSString *text = [[NSString alloc] initWithData:data
                                              encoding:NSUTF8StringEncoding] ?: @"";
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (strongSelf == nil) return;
            if (finished.terminationStatus != 0 && text.length == 0) {
                for (NSTextField *status in strongSelf.libraryStatus.allValues) {
                    status.stringValue = @"could not ask the server";
                }
                for (NSTextField *status in strongSelf.installedStatus.allValues) {
                    status.stringValue = @"could not ask the server";
                }
                return;
            }
            for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
                NSArray *parts = [line componentsSeparatedByString:@" "];
                if (parts.count < 2) continue;
                [strongSelf applyStatus:parts[0]
                                present:[parts[1] isEqualToString:@"yes"]];
            }
        });
    };
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        for (NSTextField *status in self.libraryStatus.allValues) {
            status.stringValue = @"could not run ssh";
        }
        for (NSTextField *status in self.installedStatus.allValues) {
            status.stringValue = @"could not run ssh";
        }
    }
}

@end
