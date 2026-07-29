#import "SlopNetSettings.h"

@interface SlopNetSettings ()
@property(nonatomic, strong) NSTextField *host;
@property(nonatomic, strong) NSTextField *port;
@property(nonatomic, strong) NSTextField *user;
@property(nonatomic, strong) NSTextField *connectionNote;
@property(nonatomic, strong) NSStackView *toolStack;
@property(nonatomic, strong) NSArray<NSDictionary *> *tools;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSTextField *> *toolStatus;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSButton *> *toolButton;
@property(nonatomic, assign) BOOL connected;
@end

@implementation SlopNetSettings

- (instancetype)initWithHost:(NSString *)host
                        port:(NSString *)port
                        user:(NSString *)user
                   connected:(BOOL)connected {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 620, 560)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = @"Settings";
    self = [super initWithWindow:window];
    if (!self) return nil;
    _connected = connected;
    _toolStatus = [NSMutableDictionary dictionary];
    _toolButton = [NSMutableDictionary dictionary];
    _tools = [self loadTools];
    [self buildWithHost:host port:port user:user];
    return self;
}

#pragma mark - tool list

- (NSArray<NSDictionary *> *)loadTools {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"tools" ofType:@"json"];
    if (path == nil) return @[];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data == nil) return @[];
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [root isKindOfClass:NSDictionary.class] ? (root[@"tools"] ?: @[]) : @[];
}

#pragma mark - little builders

- (NSTextField *)label:(NSString *)text size:(CGFloat)size grey:(BOOL)grey bold:(BOOL)bold {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size];
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.maximumNumberOfLines = 4;
    if (grey) label.textColor = [NSColor secondaryLabelColor];
    return label;
}

- (NSTextField *)field:(NSString *)value placeholder:(NSString *)placeholder width:(CGFloat)width {
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    field.stringValue = value ?: @"";
    field.placeholderString = placeholder;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field.widthAnchor constraintEqualToConstant:width].active = YES;
    [field.heightAnchor constraintEqualToConstant:24].active = YES;
    return field;
}

- (NSButton *)button:(NSString *)title action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
    button.title = title;
    button.bezelStyle = NSBezelStyleRounded;
    button.target = self;
    button.action = action;
    return button;
}

- (NSStackView *)row:(NSArray<NSView *> *)views spacing:(CGFloat)spacing {
    NSStackView *row = [NSStackView stackViewWithViews:views];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = spacing;
    return row;
}

#pragma mark - layout

- (void)buildWithHost:(NSString *)host port:(NSString *)port user:(NSString *)user {
    self.host = [self field:host placeholder:@"address or name of your server" width:260];
    self.port = [self field:port.length ? port : @"22" placeholder:@"22" width:70];
    self.user = [self field:user.length ? user : @"root" placeholder:@"root" width:150];

    self.connectionNote = [self label:@"" size:11 grey:YES bold:NO];
    [self updateConnectionNote];

    NSStackView *connectionRows = [NSStackView stackViewWithViews:@[
        [self row:@[[self label:@"Address" size:12 grey:NO bold:NO], self.host] spacing:8],
        [self row:@[[self label:@"Login name" size:12 grey:NO bold:NO], self.user,
                    [self label:@"Port" size:12 grey:NO bold:NO], self.port] spacing:8],
        [self row:@[[self button:@"Connect and prepare this server"
                          action:@selector(connectPressed:)],
                    [self button:@"Forget" action:@selector(forgetPressed:)]] spacing:8],
        self.connectionNote,
    ]];
    connectionRows.orientation = NSUserInterfaceLayoutOrientationVertical;
    connectionRows.alignment = NSLayoutAttributeLeading;
    connectionRows.spacing = 8;

    self.toolStack = [NSStackView stackViewWithViews:@[]];
    self.toolStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.toolStack.alignment = NSLayoutAttributeLeading;
    self.toolStack.spacing = 6;
    [self buildToolRows];

    NSButton *recheck = [self button:@"Check what is installed" action:@selector(refreshPressed:)];
    NSButton *close = [self button:@"Done" action:@selector(closePressed:)];
    close.keyEquivalent = @"\r";

    NSStackView *page = [NSStackView stackViewWithViews:@[
        [self label:@"Your server" size:15 grey:NO bold:YES],
        [self label:@"Any computer you can reach over SSH: a rented server, a "
                    @"dedicated machine, a home server or a Raspberry Pi. Your "
                    @"password is never stored — it goes straight from the "
                    @"console to your server." size:11 grey:YES bold:NO],
        connectionRows,
        [NSBox new],
        [self label:@"Coding tools on your server" size:15 grey:NO bold:YES],
        [self label:@"SlopNet asks your server which of these it already has. "
                    @"Installing runs in the main window so you can watch it." size:11 grey:YES bold:NO],
        recheck,
        self.toolStack,
        close,
    ]];
    page.orientation = NSUserInterfaceLayoutOrientationVertical;
    page.alignment = NSLayoutAttributeLeading;
    page.spacing = 12;
    page.edgeInsets = NSEdgeInsetsMake(20, 24, 20, 24);
    page.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *content = self.window.contentView;
    [content addSubview:page];
    // Constrain the page to the window. Skipping this is exactly the bug
    // that made the previous settings form unclickable: an auto-layout view
    // with no constraints collapses to nothing.
    [NSLayoutConstraint activateConstraints:@[
        [page.topAnchor constraintEqualToAnchor:content.topAnchor],
        [page.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [page.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [page.bottomAnchor constraintGreaterThanOrEqualToAnchor:content.bottomAnchor
                                                       constant:-20],
    ]];
}

- (void)buildToolRows {
    for (NSView *view in [self.toolStack.arrangedSubviews copy]) {
        [self.toolStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    [self.toolStatus removeAllObjects];
    [self.toolButton removeAllObjects];

    if (self.tools.count == 0) {
        [self.toolStack addArrangedSubview:
            [self label:@"No tools list found in this app." size:12 grey:YES bold:NO]];
        return;
    }

    for (NSDictionary *tool in self.tools) {
        NSString *toolID = tool[@"id"] ?: @"";
        NSTextField *name = [self label:tool[@"name"] ?: toolID size:12 grey:NO bold:NO];
        name.translatesAutoresizingMaskIntoConstraints = NO;
        [name.widthAnchor constraintEqualToConstant:150].active = YES;

        NSTextField *status = [self label:@"unknown" size:11 grey:YES bold:NO];
        status.translatesAutoresizingMaskIntoConstraints = NO;
        [status.widthAnchor constraintEqualToConstant:170].active = YES;
        self.toolStatus[toolID] = status;

        NSString *install = tool[@"install"] ?: @"";
        NSButton *action = [self button:install.length ? @"Install" : @"No command yet"
                                 action:@selector(installPressed:)];
        action.identifier = toolID;
        action.enabled = install.length > 0 && self.connected;
        self.toolButton[toolID] = action;

        NSTextField *subscription = [self label:tool[@"subscription"] ?: @""
                                           size:10 grey:YES bold:NO];
        subscription.translatesAutoresizingMaskIntoConstraints = NO;
        [subscription.widthAnchor constraintEqualToConstant:210].active = YES;

        [self.toolStack addArrangedSubview:
            [self row:@[name, status, action, subscription] spacing:10]];
    }
}

- (void)updateConnectionNote {
    self.connectionNote.stringValue = self.connected
        ? @"This server is set up and ready."
        : @"Not set up yet. Fill in the details and press Connect.";
}

- (void)presentFrom:(NSWindow *)parent {
    [parent beginSheet:self.window completionHandler:nil];
    if (self.connected) [self refreshToolStatus];
}

#pragma mark - actions

- (void)closePressed:(id)sender {
    [self.window.sheetParent endSheet:self.window];
}

- (void)connectPressed:(id)sender {
    if (self.host.stringValue.length == 0) {
        self.connectionNote.stringValue = @"Type your server's address first.";
        return;
    }
    [self.delegate settings:self
              connectToHost:self.host.stringValue
                       port:self.port.stringValue
                       user:self.user.stringValue];
    [self closePressed:nil];
}

- (void)forgetPressed:(id)sender {
    [self.delegate settingsDidForget:self];
    self.connected = NO;
    [self updateConnectionNote];
    [self buildToolRows];
}

- (void)installPressed:(NSButton *)sender {
    NSString *toolID = sender.identifier;
    for (NSDictionary *tool in self.tools) {
        if (![tool[@"id"] isEqualToString:toolID]) continue;
        NSString *install = tool[@"install"] ?: @"";
        if (install.length == 0) return;
        [self.delegate settings:self runOnServer:install
                          title:[NSString stringWithFormat:@"Installing %@",
                                 tool[@"name"] ?: toolID]];
        [self closePressed:nil];
        return;
    }
}

- (void)refreshPressed:(id)sender { [self refreshToolStatus]; }

#pragma mark - asking the server what it has

- (void)refreshToolStatus {
    if (!self.connected || self.host.stringValue.length == 0) {
        for (NSTextField *status in self.toolStatus.allValues) {
            status.stringValue = @"connect first";
        }
        return;
    }
    for (NSTextField *status in self.toolStatus.allValues) status.stringValue = @"checking…";

    // One quiet, non-interactive SSH call. It only asks where commands are;
    // it changes nothing. Interactive work belongs in the main console.
    NSMutableString *probe = [NSMutableString string];
    for (NSDictionary *tool in self.tools) {
        NSString *check = tool[@"check"] ?: @"";
        if (check.length == 0) continue;
        [probe appendFormat:
            @"if command -v %@ >/dev/null 2>&1; then echo '%@ yes'; else echo '%@ no'; fi; ",
            check, tool[@"id"], tool[@"id"]];
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ssh"];
    task.arguments = @[@"-p", self.port.stringValue,
                       @"-o", @"BatchMode=yes",
                       @"-o", @"ConnectTimeout=10",
                       @"-o", @"StrictHostKeyChecking=accept-new",
                       [NSString stringWithFormat:@"%@@%@",
                        self.user.stringValue, self.host.stringValue],
                       probe];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSPipe pipe];

    __weak typeof(self) weakSelf = self;
    task.terminationHandler = ^(NSTask *finished) {
        NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (strongSelf == nil) return;
            if (finished.terminationStatus != 0 && text.length == 0) {
                for (NSTextField *status in strongSelf.toolStatus.allValues) {
                    status.stringValue = @"could not ask the server";
                }
                return;
            }
            for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
                NSArray *parts = [line componentsSeparatedByString:@" "];
                if (parts.count < 2) continue;
                NSTextField *status = strongSelf.toolStatus[parts[0]];
                NSButton *action = strongSelf.toolButton[parts[0]];
                if (status == nil) continue;
                BOOL present = [parts[1] isEqualToString:@"yes"];
                status.stringValue = present ? @"installed" : @"not installed";
                status.textColor = present ? [NSColor systemGreenColor]
                                           : [NSColor secondaryLabelColor];
                if (action && present) {
                    action.title = @"Reinstall";
                }
            }
        });
    };
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        for (NSTextField *status in self.toolStatus.allValues) {
            status.stringValue = @"could not run ssh";
        }
    }
}

@end
