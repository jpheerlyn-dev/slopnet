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
@property(nonatomic, strong) NSView *installedPage;
@property(nonatomic, strong) NSView *libraryPage;
@property(nonatomic, strong) NSButton *installedTab;
@property(nonatomic, strong) NSButton *libraryTab;
@end

@implementation SlopNetTools

- (instancetype)initWithHost:(NSString *)host
                        port:(NSString *)port
                        user:(NSString *)user
                   connected:(BOOL)connected {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 820, 560)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = @"Tools";
    window.minSize = NSMakeSize(480, 320);
    [SlopNetBrand applyPanelChromeToWindow:window];
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
    label.font = [NSFont monospacedSystemFontOfSize:size
                                             weight:bold ? NSFontWeightBold
                                                         : NSFontWeightRegular];
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    if (grey) [SlopNetBrand stylePanelHelp:label];
    else [SlopNetBrand stylePanelLabel:label size:size];
    if (bold) label.font = [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightBold];
    return label;
}

- (NSTextField *)helpText:(NSString *)text {
    NSTextField *label = [self label:text size:11 grey:YES bold:NO];
    label.maximumNumberOfLines = 0;
    label.preferredMaxLayoutWidth = 560;
    return label;
}

/// A column heading over the tool rows: crimson, letterspaced, upper case.
- (NSTextField *)columnHeading:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [SlopNetBrand stylePanelColumnHeading:label];
    return label;
}

/// A tool's name with its provider's colour badge in front of it, so the list
/// reads the way the console does rather than as a plain table of strings.
///
/// The badge column is always the same width, badge or no badge — otherwise
/// the tools nobody has a logo for start their names further left and the
/// column stops being a column.
- (NSView *)toolName:(NSString *)name provider:(NSString *)provider {
    NSTextField *label = [self label:name size:12 grey:NO bold:NO];
    // A long parenthetical must not be allowed to drag the whole window wider
    // than the screen; it gives way before the layout does.
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                    forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSAttributedString *mark = [SlopNetBrand markAttributedForProvider:provider size:13];

    NSTextField *badge = mark ? [NSTextField labelWithAttributedString:mark]
                              : [NSTextField labelWithString:@""];
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    [badge.widthAnchor constraintEqualToConstant:22].active = YES;
    [badge setContentHuggingPriority:NSLayoutPriorityRequired
                      forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *row = [NSStackView stackViewWithViews:@[badge, label]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 7;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    return row;
}

- (NSButton *)button:(NSString *)title action:(SEL)action {
    return [self button:title action:action role:SlopNetButtonRoleNormal];
}

- (NSButton *)button:(NSString *)title action:(SEL)action role:(SlopNetButtonRole)role {
    return [SlopNetBrand panelButtonWithTitle:title role:role target:self action:action];
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

    NSView *libraryHeader = [SlopNetBrand sectionHeaderWithTitle:@"Library"];
    NSStackView *libraryPage = [NSStackView stackViewWithViews:@[
        libraryHeader,
        [self helpText:@"Tools SlopNet can put on your server. Installing runs in "
                       @"the main window so you can watch exactly what happens."],
        recheck,
        self.libraryGrid,
    ]];
    libraryPage.orientation = NSUserInterfaceLayoutOrientationVertical;
    libraryPage.alignment = NSLayoutAttributeLeading;
    libraryPage.spacing = 12;
    libraryPage.edgeInsets = NSEdgeInsetsMake(18, 18, 16, 18);
    libraryPage.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *installedHeader = [SlopNetBrand sectionHeaderWithTitle:@"Installed"];
    NSStackView *installedPage = [NSStackView stackViewWithViews:@[
        installedHeader,
        [self helpText:@"Open a tool in its own terminal tab. Granite stays one "
                       @"click away."],
        self.installedGrid,
    ]];
    installedPage.orientation = NSUserInterfaceLayoutOrientationVertical;
    installedPage.alignment = NSLayoutAttributeLeading;
    installedPage.spacing = 12;
    installedPage.edgeInsets = NSEdgeInsetsMake(18, 18, 16, 18);
    installedPage.translatesAutoresizingMaskIntoConstraints = NO;

    // The section rules run the full width of their page; the rows do not.
    for (NSView *header in @[libraryHeader, installedHeader]) {
        NSStackView *page = (header == libraryHeader) ? libraryPage : installedPage;
        [header.widthAnchor constraintEqualToAnchor:page.widthAnchor
                                           constant:-(page.edgeInsets.left +
                                                      page.edgeInsets.right)].active = YES;
    }

    // Installed first: open what you already have. Library is for adding more.
    //
    // The two pages are switched by a pair of terminal buttons rather than an
    // NSTabView. The stock tab strip draws a bright system-blue pill, which is
    // the one thing on this panel that still looked like a preferences window.
    self.installedPage = installedPage;
    self.libraryPage = libraryPage;

    NSView *pages = [[NSView alloc] initWithFrame:NSZeroRect];
    pages.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSView *one in @[installedPage, libraryPage]) {
        [pages addSubview:one];
        [NSLayoutConstraint activateConstraints:@[
            [one.topAnchor constraintEqualToAnchor:pages.topAnchor],
            [one.leadingAnchor constraintEqualToAnchor:pages.leadingAnchor],
            [one.trailingAnchor constraintEqualToAnchor:pages.trailingAnchor],
            [one.bottomAnchor constraintLessThanOrEqualToAnchor:pages.bottomAnchor],
        ]];
    }

    self.installedTab = [self button:@"Installed" action:@selector(showInstalled:)];
    self.libraryTab = [self button:@"Library" action:@selector(showLibrary:)];
    [self.installedTab.widthAnchor constraintEqualToConstant:110].active = YES;
    [self.libraryTab.widthAnchor constraintEqualToConstant:110].active = YES;
    NSStackView *tabBar = [NSStackView stackViewWithViews:@[self.installedTab, self.libraryTab]];
    tabBar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    tabBar.spacing = 8;
    tabBar.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *tabs = [NSStackView stackViewWithViews:@[tabBar, pages]];
    tabs.orientation = NSUserInterfaceLayoutOrientationVertical;
    tabs.alignment = NSLayoutAttributeLeading;
    tabs.spacing = 10;
    tabs.translatesAutoresizingMaskIntoConstraints = NO;
    [pages.widthAnchor constraintEqualToAnchor:tabs.widthAnchor].active = YES;
    [self selectTab:@"installed"];

    NSButton *done = [self button:@"Done" action:@selector(closePressed:)];
    done.keyEquivalent = @"\r";
    [done.widthAnchor constraintGreaterThanOrEqualToConstant:110].active = YES;

    NSStackView *page = [NSStackView stackViewWithViews:@[tabs, done]];
    page.orientation = NSUserInterfaceLayoutOrientationVertical;
    page.alignment = NSLayoutAttributeLeading;
    page.spacing = 12;
    page.edgeInsets = NSEdgeInsetsMake(30, 20, 20, 20);
    page.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *content = self.window.contentView;
    // The void field goes behind everything, as in Settings.
    NSView *backdrop = [SlopNetBrand panelBackdrop];
    [content addSubview:backdrop];
    [NSLayoutConstraint activateConstraints:@[
        [backdrop.topAnchor constraintEqualToAnchor:content.topAnchor],
        [backdrop.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [backdrop.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [backdrop.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];
    [content addSubview:page];
    [NSLayoutConstraint activateConstraints:@[
        [page.topAnchor constraintEqualToAnchor:content.topAnchor],
        [page.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [page.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [page.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [tabs.widthAnchor constraintEqualToAnchor:page.widthAnchor constant:-40],
        [tabs.heightAnchor constraintGreaterThanOrEqualToConstant:360],
        // Without an upper bound the widest row decides how wide the window
        // opens, and the tool list has some long names in it.
        [page.widthAnchor constraintLessThanOrEqualToConstant:820],
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
        [self columnHeading:@"Tool"],
        [self columnHeading:@"On your server"],
        [self columnHeading:@""],
        [self columnHeading:@"Subscription"]]];
    header.bottomPadding = 6;

    for (NSDictionary *tool in self.tools) {
        NSString *toolID = tool[@"id"] ?: @"";
        NSString *provider = [SlopNetBrand providerForTool:toolID];
        NSView *name = [self toolName:tool[@"name"] ?: toolID provider:provider];

        NSTextField *status = [self label:self.connected ? @"unknown" : @"connect first"
                                     size:11 grey:YES bold:NO];
        self.libraryStatus[toolID] = status;

        NSString *install = tool[@"install"] ?: @"";
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
        NSButton *action = [self button:actionTitle
                                 action:@selector(installPressed:)
                                   role:canPrepare ? SlopNetButtonRolePrimary
                                                   : SlopNetButtonRoleNormal];
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
        subscription.lineBreakMode = NSLineBreakByTruncatingTail;
        [subscription setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                               forOrientation:NSLayoutConstraintOrientationHorizontal];
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
        [self columnHeading:@"Tool"],
        [self columnHeading:@"On your server"],
        [self columnHeading:@""]]];
    header.bottomPadding = 6;

    for (NSDictionary *tool in launchable) {
        NSString *toolID = tool[@"id"] ?: @"";
        NSView *name = [self toolName:tool[@"name"] ?: toolID
                             provider:[SlopNetBrand providerForTool:toolID]];
        NSTextField *status = [self label:self.connected ? @"unknown" : @"connect first"
                                     size:11 grey:YES bold:NO];
        self.installedStatus[toolID] = status;

        NSButton *open = [self button:@"Open"
                               action:@selector(openPressed:)
                                 role:SlopNetButtonRolePrimary];
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

- (void)refreshPressed:(id)sender { (void)sender; [self refreshToolStatus]; }

#pragma mark - the two pages

/// The chosen page is shown and its button carries the primary role, so which
/// one you are looking at is legible without a system-blue pill.
- (void)selectTab:(NSString *)which {
    BOOL installed = [which isEqualToString:@"installed"];
    self.installedPage.hidden = !installed;
    self.libraryPage.hidden = installed;
    [SlopNetBrand setPanelButton:self.installedTab
                            role:installed ? SlopNetButtonRolePrimary
                                           : SlopNetButtonRoleNormal];
    [SlopNetBrand setPanelButton:self.libraryTab
                            role:installed ? SlopNetButtonRoleNormal
                                           : SlopNetButtonRolePrimary];
}

- (void)showInstalled:(id)sender { (void)sender; [self selectTab:@"installed"]; }
- (void)showLibrary:(id)sender { (void)sender; [self selectTab:@"library"]; }

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
    NSColor *colour = present ? [SlopNetBrand okColor] : [SlopNetBrand quietColor];
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
