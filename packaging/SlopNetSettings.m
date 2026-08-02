#import "SlopNetSettings.h"
#import "SlopNetBrand.h"

@interface SlopNetSettings ()
@property(nonatomic, strong) NSTextField *host;      // shown when revealed
@property(nonatomic, strong) NSSecureTextField *hiddenHost;
@property(nonatomic, strong) NSButton *revealHost;
@property(nonatomic, strong) NSTextField *port;
@property(nonatomic, strong) NSTextField *user;
@property(nonatomic, strong) NSTextField *connectionNote;
@property(nonatomic, strong) NSTextField *localModel;
@property(nonatomic, strong) NSTextField *localHelperNote;
@property(nonatomic, strong) NSButton *localHelperButton;
@property(nonatomic, assign) BOOL connected;
@end

@implementation SlopNetSettings

- (instancetype)initWithHost:(NSString *)host
                        port:(NSString *)port
                        user:(NSString *)user
                   connected:(BOOL)connected {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 660, 480)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = @"Settings";
    window.minSize = NSMakeSize(520, 360);
    window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    self = [super initWithWindow:window];
    if (!self) return nil;
    _connected = connected;
    [self buildWithHost:host port:port user:user];
    return self;
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

/// Wrapping help text must be told how wide it may be, or it stretches into
/// one long line and drags the window wider. This is why the page used to
/// fall apart when resized.
- (NSTextField *)helpText:(NSString *)text {
    NSTextField *label = [self label:text size:11 grey:YES bold:NO];
    label.maximumNumberOfLines = 0;
    label.preferredMaxLayoutWidth = 540;
    return label;
}

- (NSTextField *)field:(NSString *)value placeholder:(NSString *)placeholder {
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    field.stringValue = value ?: @"";
    field.placeholderString = placeholder;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field.heightAnchor constraintEqualToConstant:24].active = YES;
    return field;
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

/// A real hairline. Plain [NSBox new] draws an empty bordered frame, which
/// is what made the page look broken.
- (NSBox *)separator {
    NSBox *line = [[NSBox alloc] initWithFrame:NSZeroRect];
    line.boxType = NSBoxSeparator;
    line.translatesAutoresizingMaskIntoConstraints = NO;
    [line.heightAnchor constraintEqualToConstant:1].active = YES;
    return line;
}

#pragma mark - layout

- (void)buildWithHost:(NSString *)host port:(NSString *)port user:(NSString *)user {
    // The address is masked by default, with a button to look at it.
    //
    // Two fields rather than one that changes mode: AppKit draws bullets from
    // the cell, and swapping a live field's cell loses the selection and the
    // undo stack. Whichever is visible carries the value, and the other is
    // kept in step, so either can be typed into.
    self.host = [self field:host placeholder:@"address or name of your server"];
    self.hiddenHost = [[NSSecureTextField alloc] initWithFrame:NSZeroRect];
    self.hiddenHost.stringValue = host ?: @"";
    self.hiddenHost.placeholderString = @"address or name of your server";
    self.hiddenHost.translatesAutoresizingMaskIntoConstraints = NO;
    [self.hiddenHost.heightAnchor constraintEqualToConstant:24].active = YES;
    [self.hiddenHost.widthAnchor constraintGreaterThanOrEqualToConstant:240].active = YES;
    self.host.hidden = YES;

    self.revealHost = [NSButton buttonWithTitle:@"Show"
                                          target:self
                                          action:@selector(toggleHostVisible:)];
    self.revealHost.bezelStyle = NSBezelStyleRounded;
    self.revealHost.translatesAutoresizingMaskIntoConstraints = NO;
    [self.revealHost.widthAnchor constraintEqualToConstant:60].active = YES;

    NSStackView *addressRow = [NSStackView stackViewWithViews:
        @[self.hiddenHost, self.host, self.revealHost]];
    addressRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    addressRow.spacing = 6;
    addressRow.translatesAutoresizingMaskIntoConstraints = NO;
    self.user = [self field:user.length ? user : @"root" placeholder:@"root"];
    self.port = [self field:port.length ? port : @"22" placeholder:@"22"];
    [self.host.widthAnchor constraintGreaterThanOrEqualToConstant:240].active = YES;
    [self.user.widthAnchor constraintEqualToConstant:170].active = YES;
    [self.port.widthAnchor constraintEqualToConstant:70].active = YES;

    self.connectionNote = [self label:@"" size:11 grey:YES bold:NO];
    [self updateConnectionNote];

    // A grid keeps labels and fields aligned at any window size — hand-built
    // rows of fixed widths never manage that.
    NSGridView *connection = [NSGridView gridViewWithViews:@[
        @[[self label:@"Address" size:12 grey:NO bold:NO], addressRow],
        @[[self label:@"Login name" size:12 grey:NO bold:NO], self.user],
        @[[self label:@"Port" size:12 grey:NO bold:NO], self.port],
    ]];
    connection.translatesAutoresizingMaskIntoConstraints = NO;
    connection.rowSpacing = 8;
    connection.columnSpacing = 10;
    [connection columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [connection columnAtIndex:1].xPlacement = NSGridCellPlacementLeading;

    NSButton *connect = [self button:@"Connect and prepare this server"
                             action:@selector(connectPressed:)];
    NSButton *forget = [self button:@"Forget this server" action:@selector(forgetPressed:)];
    // Dragging the app to the Trash leaves the remembered server, the saved
    // notes and the connection key behind, and leaves the private account on
    // the server running. This removes them.
    NSButton *uninstall = [self button:@"Uninstall SlopNet…" action:@selector(uninstallPressed:)];
    NSStackView *connectionButtons = [NSStackView stackViewWithViews:@[connect, forget, uninstall]];
    connectionButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    connectionButtons.spacing = 10;
    connectionButtons.translatesAutoresizingMaskIntoConstraints = NO;

    // These are useful, but not part of the project conversation. Keeping
    // them here leaves the left-hand rail for navigation rather than a row
    // of maintenance controls.
    NSButton *checkConnection = [self button:@"Check connection"
                                      action:@selector(checkConnectionPressed:)];
    checkConnection.enabled = self.connected;
    NSButton *clearConsole = [self button:@"Clear screen"
                                   action:@selector(clearConsolePressed:)];
    NSButton *gettingServer = [self button:@"Getting a server"
                                    action:@selector(serverHelpPressed:)];
    NSStackView *utilityButtons =
        [NSStackView stackViewWithViews:@[checkConnection, clearConsole, gettingServer]];
    utilityButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    utilityButtons.spacing = 10;
    utilityButtons.translatesAutoresizingMaskIntoConstraints = NO;

    self.localModel = [self field:@"ibm-granite/granite-4.1-3b-GGUF:Q4_K_M"
                       placeholder:@"owner/model:quant"];
    [self.localModel.widthAnchor constraintGreaterThanOrEqualToConstant:360].active = YES;
    NSGridView *localModelRow = [NSGridView gridViewWithViews:@[
        @[[self label:@"Hugging Face GGUF" size:12 grey:NO bold:NO], self.localModel],
    ]];
    localModelRow.translatesAutoresizingMaskIntoConstraints = NO;
    localModelRow.columnSpacing = 10;
    [localModelRow columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [localModelRow columnAtIndex:1].xPlacement = NSGridCellPlacementLeading;

    self.localHelperNote = [self helpText:@"Checking your server…"];
    self.localHelperButton = [self button:@"Install and test this model"
                                      action:@selector(localHelperPressed:)];
    self.localHelperButton.enabled = self.connected;
    NSButton *checkLocal = [self button:@"Check local models"
                                   action:@selector(refreshLocalPressed:)];
    checkLocal.enabled = self.connected;
    NSStackView *localButtons =
        [NSStackView stackViewWithViews:@[checkLocal, self.localHelperButton]];
    localButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    localButtons.spacing = 10;
    localButtons.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *done = [self button:@"Done" action:@selector(closePressed:)];
    done.keyEquivalent = @"\r";
    [done.widthAnchor constraintGreaterThanOrEqualToConstant:90].active = YES;

    // The numbered path lives in the setup guide (SlopNetWizard) now, so these
    // headings no longer claim to be steps 1 and 2 of anything — two competing
    // numbering schemes is exactly the confusion the wizard exists to remove.
    // Everything here still works on its own for someone who prefers panels.
    NSString *serverTitle = @"Your server";
    NSString *serverHelp = self.connected
        ? @"SlopNet setup currently supports a Linux server you can reach over SSH. Built-in terminal-tool downloads are proved only on x86-64 Linux; ARM machines are not yet proved. Your password is never stored — it goes straight from the console to your server."
        : @"Enter the address, login name, and port from your server provider. SlopNet will show every change in its own window and never saves the server password. The setup guide in the sidebar walks through this in order.";
    NSString *helperTitle = @"Private local guide";
    NSString *helperHelp = self.connected
        ? @"This small model runs only on your server for ordinary setup chat and request drafting. It cannot start coding, make a decision, or spend from a coding subscription. SlopNet shows capacity, downloads only after you approve, limits it to a small 4K context and a 15-minute test, and never opens a model port."
        : @"After the server passes, install the private local guide here or from the setup guide. It handles ordinary setup chat without using a coding subscription.";

    NSStackView *page = [NSStackView stackViewWithViews:@[
        [self label:serverTitle size:15 grey:NO bold:YES],
        [self helpText:serverHelp],
        connection,
        connectionButtons,
        self.connectionNote,
        utilityButtons,
        [self separator],
        [self label:helperTitle size:15 grey:NO bold:YES],
        [self helpText:helperHelp],
        localModelRow,
        localButtons,
        self.localHelperNote,
        [self separator],
        done,
    ]];
    page.orientation = NSUserInterfaceLayoutOrientationVertical;
    page.alignment = NSLayoutAttributeLeading;
    page.spacing = 12;
    page.edgeInsets = NSEdgeInsetsMake(22, 24, 22, 24);
    page.translatesAutoresizingMaskIntoConstraints = NO;

    // The scroll view is what stops a resize from breaking anything: make the
    // window small and the content stays reachable instead of being clipped.
    NSScrollView *scroller = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroller.hasVerticalScroller = YES;
    scroller.hasHorizontalScroller = NO;
    scroller.autohidesScrollers = YES;
    scroller.drawsBackground = NO;
    scroller.borderType = NSNoBorder;
    scroller.translatesAutoresizingMaskIntoConstraints = NO;
    scroller.documentView = page;

    NSView *content = self.window.contentView;
    [content addSubview:scroller];
    [NSLayoutConstraint activateConstraints:@[
        [scroller.topAnchor constraintEqualToAnchor:content.topAnchor],
        [scroller.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [scroller.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [scroller.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        // Page width follows the visible area, so nothing scrolls sideways;
        // its height is free to grow as tall as the content needs.
        [page.widthAnchor constraintEqualToAnchor:scroller.contentView.widthAnchor],
        [page.topAnchor constraintEqualToAnchor:scroller.contentView.topAnchor],
        [page.leadingAnchor constraintEqualToAnchor:scroller.contentView.leadingAnchor],
    ]];
}

/// Copy the typed value across, so either field can be the one edited.
- (void)syncHostFields {
    if (self.host.hidden) self.host.stringValue = self.hiddenHost.stringValue;
    else self.hiddenHost.stringValue = self.host.stringValue;
}

- (void)toggleHostVisible:(id)sender {
    [self syncHostFields];
    BOOL showing = self.host.hidden;          // about to become visible
    self.host.hidden = !showing;
    self.hiddenHost.hidden = showing;
    self.revealHost.title = showing ? @"Hide" : @"Show";
}

- (void)updateConnectionNote {
    if (self.connected) {
        self.connectionNote.stringValue = @"●  This server is set up and ready.";
        self.connectionNote.textColor = [NSColor systemGreenColor];
    } else {
        self.connectionNote.stringValue =
            @"Not set up yet. Fill in the details above, then press Connect.";
        self.connectionNote.textColor = [NSColor secondaryLabelColor];
    }
}

- (void)presentFrom:(NSWindow *)parent {
    [parent beginSheet:self.window completionHandler:nil];
    if (self.connected) [self refreshLocalHelperStatus];
}

#pragma mark - actions

- (void)closePressed:(id)sender {
    [self.window.sheetParent endSheet:self.window];
}

- (void)connectPressed:(id)sender {
    [self syncHostFields];
    if (self.host.stringValue.length == 0) {
        self.connectionNote.stringValue = @"Type your server's address first.";
        self.connectionNote.textColor = [NSColor systemRedColor];
        return;
    }
    [self.delegate settings:self
              connectToHost:self.host.stringValue
                       port:self.port.stringValue
                       user:self.user.stringValue];
    [self closePressed:nil];
}

- (void)uninstallPressed:(id)sender {
    [self.delegate settingsWantsUninstall:self];
    [self closePressed:nil];
}

- (void)forgetPressed:(id)sender {
    [self.delegate settingsDidForget:self];
    self.connected = NO;
    self.host.stringValue = @"";
    [self updateConnectionNote];
}

- (void)checkConnectionPressed:(id)sender {
    [self.delegate settingsCheckConnection:self];
    [self closePressed:nil];
}

- (void)clearConsolePressed:(id)sender {
    [self.delegate settingsClearConsole:self];
    [self closePressed:nil];
}

- (void)serverHelpPressed:(id)sender {
    [self.delegate settingsShowServerHelp:self];
    [self closePressed:nil];
}

- (BOOL)localModelValid:(NSString *)model {
    NSRegularExpression *expression = [NSRegularExpression
        regularExpressionWithPattern:@"^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*(:[A-Za-z0-9][A-Za-z0-9._-]*)?$"
                         options:0 error:nil];
    return [expression firstMatchInString:model options:0
                                    range:NSMakeRange(0, model.length)] != nil;
}

- (void)localHelperPressed:(id)sender {
    NSString *model = [self.localModel.stringValue
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![self localModelValid:model]) {
        self.localHelperNote.stringValue =
            @"Use public Hugging Face form owner/model:quant — no URLs or tokens.";
        self.localHelperNote.textColor = NSColor.systemRedColor;
        return;
    }
    [self.delegate settings:self setupLocalHelperModel:model];
    [self closePressed:nil];
}

- (void)refreshLocalPressed:(id)sender { [self refreshLocalHelperStatus]; }

#pragma mark - local helper inspection

- (void)refreshLocalHelperStatus {
    if (!self.connected || self.host.stringValue.length == 0) {
        self.localHelperNote.stringValue = @"Connect a server to inspect local models.";
        self.localHelperNote.textColor = NSColor.secondaryLabelColor;
        return;
    }
    self.localHelperNote.stringValue = @"Checking the protected runtime account…";
    self.localHelperNote.textColor = NSColor.secondaryLabelColor;

    // This is deliberately a read-only probe. It never starts a model, opens
    // a port, downloads a file, or reads anything outside SlopNet's own
    // runtime home.
    NSString *probe =
        @"set -eu; PATH=/usr/sbin:/usr/bin:/sbin:/bin; export PATH; "
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
    if (![self.user.stringValue isEqualToString:@"root"]) {
        NSString *encoded = [[probe dataUsingEncoding:NSUTF8StringEncoding]
            base64EncodedStringWithOptions:0];
        probe = [NSString stringWithFormat:
            @"/usr/bin/printf %%s '%@' | /usr/bin/base64 -d | "
             "/usr/bin/sudo -n /bin/sh", encoded];
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
                       @"-p", self.port.stringValue,
                       @"-o", @"BatchMode=yes",
                       @"-o", @"ConnectTimeout=10",
                       @"-o", @"StrictHostKeyChecking=accept-new",
                       [NSString stringWithFormat:@"%@@%@",
                        self.user.stringValue, self.host.stringValue], probe];
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
            if (finished.terminationStatus != 0 || text.length == 0) {
                strongSelf.localHelperNote.stringValue = @"Could not inspect local models.";
                strongSelf.localHelperNote.textColor = NSColor.systemRedColor;
                return;
            }
            NSMutableDictionary<NSString *, NSString *> *values = [NSMutableDictionary dictionary];
            for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
                NSRange split = [line rangeOfString:@" "];
                if (split.location == NSNotFound) continue;
                NSString *key = [line substringToIndex:split.location];
                NSString *value = [line substringFromIndex:NSMaxRange(split)];
                values[key] = value;
            }
            if (![values[@"runtime"] isEqualToString:@"yes"]) {
                strongSelf.localHelperNote.stringValue =
                    @"Run Connect and prepare this server before adding a local model.";
                strongSelf.localHelperNote.textColor = NSColor.secondaryLabelColor;
                return;
            }
            NSString *disk = values[@"disk"] ?: @"unknown storage";
            NSString *memory = values[@"memory"] ?: @"unknown memory";
            NSString *model = values[@"model"];
            if ([values[@"llama"] isEqualToString:@"yes"] && model.length > 0) {
                strongSelf.localHelperNote.stringValue = [NSString stringWithFormat:
                    @"Ready: %@ • %@ MiB free storage • %@ MiB free memory%@.",
                    model, disk, memory,
                    [values[@"cache"] isEqualToString:@"yes"] ? @" • GGUF cache found" : @""];
                strongSelf.localHelperNote.textColor = NSColor.systemGreenColor;
            } else {
                strongSelf.localHelperNote.stringValue = [NSString stringWithFormat:
                    @"No local helper yet • %@ MiB free storage • %@ MiB free memory.",
                    disk, memory];
                strongSelf.localHelperNote.textColor = NSColor.secondaryLabelColor;
            }
        });
    };
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        self.localHelperNote.stringValue = @"Could not run the local-model check.";
        self.localHelperNote.textColor = NSColor.systemRedColor;
    }
}

@end
