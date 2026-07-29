#import <Cocoa/Cocoa.h>

@interface SlopNetAppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSButton *hasVPS;
@property(nonatomic, strong) NSTextField *host;
@property(nonatomic, strong) NSTextField *username;
@property(nonatomic, strong) NSTextField *port;
@property(nonatomic, strong) NSArray<NSView *> *connectionViews;
@end

@implementation SlopNetAppDelegate

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame size:(CGFloat)size {
    NSTextField *label = [NSTextField labelWithString:text];
    label.frame = frame;
    label.font = [NSFont systemFontOfSize:size];
    label.lineBreakMode = NSLineBreakByWordWrapping;
    return label;
}

- (NSButton *)button:(NSString *)title frame:(NSRect)frame action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.title = title;
    button.target = self;
    button.action = action;
    return button;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSRect frame = NSMakeRect(0, 0, 680, 535);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                               styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
    self.window.title = @"SlopNet";
    [self.window center];
    NSView *content = self.window.contentView;

    NSTextField *title = [self label:@"SlopNet" frame:NSMakeRect(30, 476, 230, 39) size:30];
    title.font = [NSFont boldSystemFontOfSize:30];
    [content addSubview:title];
    NSTextField *subtitle = [self label:@"Build on a private VPS, not on your laptop." frame:NSMakeRect(32, 451, 430, 20) size:14];
    subtitle.textColor = NSColor.secondaryLabelColor;
    [content addSubview:subtitle];

    self.hasVPS = [self button:@"I already have a VPS" frame:NSMakeRect(30, 410, 220, 24) action:@selector(changeVPSChoice:)];
    self.hasVPS.buttonType = NSButtonTypeSwitch;
    self.hasVPS.state = NSControlStateValueOn;
    [content addSubview:self.hasVPS];

    NSTextField *hostLabel = [self label:@"IP address or host" frame:NSMakeRect(42, 365, 145, 22) size:13];
    self.host = [[NSTextField alloc] initWithFrame:NSMakeRect(190, 361, 410, 25)];
    self.host.placeholderString = @"for example 203.0.113.10";
    NSTextField *userLabel = [self label:@"SSH username" frame:NSMakeRect(42, 322, 145, 22) size:13];
    self.username = [[NSTextField alloc] initWithFrame:NSMakeRect(190, 318, 250, 25)];
    self.username.stringValue = @"root";
    NSTextField *portLabel = [self label:@"SSH port" frame:NSMakeRect(42, 279, 145, 22) size:13];
    self.port = [[NSTextField alloc] initWithFrame:NSMakeRect(190, 275, 90, 25)];
    self.port.stringValue = @"22";
    [content addSubview:hostLabel];
    [content addSubview:self.host];
    [content addSubview:userLabel];
    [content addSubview:self.username];
    [content addSubview:portLabel];
    [content addSubview:self.port];
    self.connectionViews = @[hostLabel, self.host, userLabel, self.username, portLabel, self.port];

    NSTextField *security = [self label:@"Your VPS password is never entered here or saved by SlopNet. Terminal will ask for it directly through SSH once, then SlopNet uses a dedicated SSH key for this VPS." frame:NSMakeRect(42, 211, 570, 49) size:12];
    security.textColor = NSColor.secondaryLabelColor;
    [content addSubview:security];

    NSButton *start = [self button:@"Connect and begin guided VPS setup" frame:NSMakeRect(42, 158, 286, 34) action:@selector(beginSetup:)];
    start.bezelStyle = NSBezelStyleRounded;
    start.keyEquivalent = @"\r";
    [content addSubview:start];
    NSButton *test = [self button:@"Test Terminal access" frame:NSMakeRect(342, 158, 175, 34) action:@selector(testTerminal:)];
    test.bezelStyle = NSBezelStyleRounded;
    [content addSubview:test];

    NSTextField *provider = [self label:@"Need a VPS first? Choose a Linux VPS from one of these providers:" frame:NSMakeRect(42, 112, 480, 20) size:13];
    provider.textColor = NSColor.secondaryLabelColor;
    [content addSubview:provider];
    [content addSubview:[self button:@"Hetzner" frame:NSMakeRect(42, 76, 100, 28) action:@selector(openHetzner:)]];
    [content addSubview:[self button:@"Contabo" frame:NSMakeRect(150, 76, 100, 28) action:@selector(openContabo:)]];
    [content addSubview:[self button:@"Hostinger" frame:NSMakeRect(258, 76, 100, 28) action:@selector(openHostinger:)]];
    NSTextField *footnote = [self label:@"Choose an Ubuntu LTS VPS that permits rootless user namespaces. SlopNet checks this before it lets an agent edit files." frame:NSMakeRect(42, 38, 580, 30) size:11];
    footnote.textColor = NSColor.secondaryLabelColor;
    [content addSubview:footnote];

    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)changeVPSChoice:(id)sender {
    BOOL visible = self.hasVPS.state == NSControlStateValueOn;
    for (NSView *view in self.connectionViews) {
        view.hidden = !visible;
    }
}

- (BOOL)matches:(NSString *)value pattern:(NSString *)pattern {
    NSRange range = NSMakeRange(0, value.length);
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    return [expression firstMatchInString:value options:0 range:range] != nil;
}

- (void)beginSetup:(id)sender {
    if (self.hasVPS.state != NSControlStateValueOn) {
        [self show:@"Choose a VPS provider above, then come back with its IP address, SSH username, and password."];
        return;
    }
    NSString *host = self.host.stringValue;
    NSString *username = self.username.stringValue;
    NSString *port = self.port.stringValue;
    if (![self matches:host pattern:@"^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$"] ||
        ![self matches:username pattern:@"^[A-Za-z_][A-Za-z0-9_-]{0,31}$"] ||
        port.integerValue < 1 || port.integerValue > 65535 ||
        ![self matches:port pattern:@"^[0-9]{1,5}$"]) {
        [self show:@"Enter a standard host name or IPv4 address, a normal SSH username, and a port from 1 to 65535."];
        return;
    }
    NSString *script = [[NSBundle mainBundle] pathForResource:@"slopnet-vps-onboard" ofType:@"sh"];
    if (script == nil) {
        [self show:@"The VPS setup helper is missing from this SlopNet app bundle. Rebuild the application."];
        return;
    }
    NSString *(^quote)(NSString *) = ^NSString *(NSString *value) {
        return [NSString stringWithFormat:@"'%@'", [value stringByReplacingOccurrencesOfString:@"'" withString:@"'\\\"'\\\"'"]];
    };
    NSString *command = [NSString stringWithFormat:@"%@ %@ %@ %@", quote(script), quote(host), quote(port), quote(username)];
    if ([self openTerminalForCommand:command]) {
        [self show:@"Terminal is handling the VPS connection. Follow its prompts; this app never receives or saves your password."];
    }
}

- (void)testTerminal:(id)sender {
    NSString *command = @"clear; echo 'SlopNet can open Terminal safely.'; echo 'No VPS connection, password, or SSH key was used for this check.'; read -r -p 'Press Return to close this test: '";
    if ([self openTerminalForCommand:command]) {
        [self show:@"Terminal opened successfully. You can now enter your VPS details and start guided setup."];
    }
}

- (BOOL)openTerminalForCommand:(NSString *)command {
    NSString *escaped = [[command stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    NSString *source = [NSString stringWithFormat:@"tell application \"Terminal\"\nactivate\ndo script \"%@\"\nend tell", escaped];
    NSDictionary *error = nil;
    [[[NSAppleScript alloc] initWithSource:source] executeAndReturnError:&error];
    if (error != nil) {
        NSNumber *number = error[NSAppleScriptErrorNumber];
        NSString *reason = error[NSAppleScriptErrorMessage] ?: @"unknown macOS automation error";
        if (number.integerValue == -1743) {
            [self show:@"macOS needs your permission for SlopNet to open Terminal. Open System Settings, go to Privacy & Security, then Automation, and turn on Terminal for SlopNet. Return here and press the button again."];
        } else {
            [self show:[NSString stringWithFormat:@"Could not open Terminal for VPS setup: %@. Open SlopNet again and try once more.", reason]];
        }
        return NO;
    }
    return YES;
}

- (void)open:(NSString *)address {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:address]];
}

- (void)openHetzner:(id)sender { [self open:@"https://www.hetzner.com/cloud/"]; }
- (void)openContabo:(id)sender { [self open:@"https://contabo.com/en/vps/"]; }
- (void)openHostinger:(id)sender { [self open:@"https://www.hostinger.com/vps-hosting"]; }

- (void)show:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"SlopNet";
    alert.informativeText = message;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}
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
