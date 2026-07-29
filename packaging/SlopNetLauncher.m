#import <Cocoa/Cocoa.h>

@interface SlopNetAppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSButton *hasVPS;
@property(nonatomic, strong) NSTextField *host;
@property(nonatomic, strong) NSTextField *username;
@property(nonatomic, strong) NSTextField *port;
@property(nonatomic, strong) NSTextField *projectName;
@property(nonatomic, strong) NSTextField *projectIdea;
@property(nonatomic, strong) NSArray<NSView *> *connectionViews;
@property(nonatomic, strong) NSArray<NSView *> *projectViews;
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
    NSRect frame = NSMakeRect(0, 0, 680, 690);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                               styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
    self.window.title = @"SlopNet";
    [self.window center];
    NSView *content = self.window.contentView;

    NSTextField *title = [self label:@"SlopNet" frame:NSMakeRect(30, 631, 230, 39) size:30];
    title.font = [NSFont boldSystemFontOfSize:30];
    [content addSubview:title];
    NSTextField *subtitle = [self label:@"Set up your private build computer, safely." frame:NSMakeRect(32, 606, 430, 20) size:14];
    subtitle.textColor = NSColor.secondaryLabelColor;
    [content addSubview:subtitle];

    self.hasVPS = [self button:@"I already have a VPS" frame:NSMakeRect(30, 565, 220, 24) action:@selector(changeVPSChoice:)];
    self.hasVPS.buttonType = NSButtonTypeSwitch;
    self.hasVPS.state = NSControlStateValueOn;
    [content addSubview:self.hasVPS];

    NSTextField *hostLabel = [self label:@"VPS address" frame:NSMakeRect(42, 520, 145, 22) size:13];
    self.host = [[NSTextField alloc] initWithFrame:NSMakeRect(190, 516, 410, 25)];
    self.host.placeholderString = @"the IP address from your VPS welcome email";
    NSTextField *userLabel = [self label:@"VPS login name" frame:NSMakeRect(42, 477, 145, 22) size:13];
    self.username = [[NSTextField alloc] initWithFrame:NSMakeRect(190, 473, 250, 25)];
    self.username.stringValue = @"root";
    NSTextField *portLabel = [self label:@"Connection port" frame:NSMakeRect(42, 434, 145, 22) size:13];
    self.port = [[NSTextField alloc] initWithFrame:NSMakeRect(190, 430, 90, 25)];
    self.port.stringValue = @"22";
    [content addSubview:hostLabel];
    [content addSubview:self.host];
    [content addSubview:userLabel];
    [content addSubview:self.username];
    [content addSubview:portLabel];
    [content addSubview:self.port];
    self.connectionViews = @[hostLabel, self.host, userLabel, self.username, portLabel, self.port];

    NSTextField *security = [self label:@"Look in your VPS provider's welcome email for these three details. The port is almost always 22. Your VPS password is never entered here or saved by SlopNet." frame:NSMakeRect(42, 365, 570, 49) size:12];
    security.textColor = NSColor.secondaryLabelColor;
    [content addSubview:security];

    NSButton *start = [self button:@"Set up my VPS" frame:NSMakeRect(42, 315, 286, 34) action:@selector(beginSetup:)];
    start.bezelStyle = NSBezelStyleRounded;
    start.keyEquivalent = @"\r";
    [content addSubview:start];
    NSButton *test = [self button:@"Test Terminal access" frame:NSMakeRect(342, 315, 175, 34) action:@selector(testTerminal:)];
    test.bezelStyle = NSBezelStyleRounded;
    [content addSubview:test];

    NSTextField *projectTitle = [self label:@"After VPS setup succeeds" frame:NSMakeRect(42, 260, 250, 22) size:16];
    projectTitle.font = [NSFont boldSystemFontOfSize:16];
    NSTextField *projectHelp = [self label:@"Codex is now your approved coding app. Name a project and describe what you want. SlopNet will make a plan on the VPS and wait for your approval before any code runs." frame:NSMakeRect(42, 224, 570, 34) size:12];
    projectHelp.textColor = NSColor.secondaryLabelColor;
    NSTextField *projectNameLabel = [self label:@"Project folder name" frame:NSMakeRect(42, 182, 145, 22) size:13];
    self.projectName = [[NSTextField alloc] initWithFrame:NSMakeRect(190, 178, 250, 25)];
    self.projectName.placeholderString = @"a name you choose, like photo-sheet";
    NSTextField *projectIdeaLabel = [self label:@"What do you want made?" frame:NSMakeRect(42, 139, 145, 22) size:13];
    self.projectIdea = [[NSTextField alloc] initWithFrame:NSMakeRect(190, 135, 410, 25)];
    self.projectIdea.placeholderString = @"a sentence in your own words";
    NSButton *projectStart = [self button:@"Make my project plan" frame:NSMakeRect(42, 88, 286, 34) action:@selector(beginProject:)];
    projectStart.bezelStyle = NSBezelStyleRounded;
    [content addSubview:projectTitle];
    [content addSubview:projectHelp];
    [content addSubview:projectNameLabel];
    [content addSubview:self.projectName];
    [content addSubview:projectIdeaLabel];
    [content addSubview:self.projectIdea];
    [content addSubview:projectStart];
    self.projectViews = @[projectTitle, projectHelp, projectNameLabel, self.projectName, projectIdeaLabel, self.projectIdea, projectStart];

    NSTextField *provider = [self label:@"Need a VPS first? Choose a Linux VPS from one of these providers:" frame:NSMakeRect(42, 57, 480, 20) size:13];
    provider.textColor = NSColor.secondaryLabelColor;
    [content addSubview:provider];
    [content addSubview:[self button:@"Hetzner" frame:NSMakeRect(42, 22, 100, 28) action:@selector(openHetzner:)]];
    [content addSubview:[self button:@"Contabo" frame:NSMakeRect(150, 22, 100, 28) action:@selector(openContabo:)]];
    [content addSubview:[self button:@"Hostinger" frame:NSMakeRect(258, 22, 100, 28) action:@selector(openHostinger:)]];
    NSTextField *footnote = [self label:@"Choose an Ubuntu LTS VPS that permits rootless user namespaces. SlopNet checks this before it lets an agent edit files." frame:NSMakeRect(370, 16, 260, 38) size:10];
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
    for (NSView *view in self.projectViews) {
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
        [self show:@"Copy the VPS address and login name from your provider's welcome email. Leave the connection port as 22 unless your provider gave you a different one."];
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

- (void)beginProject:(id)sender {
    if (self.hasVPS.state != NSControlStateValueOn) {
        [self show:@"Choose a VPS provider above, then come back with its IP address, SSH username, and password."];
        return;
    }
    NSString *host = self.host.stringValue;
    NSString *username = self.username.stringValue;
    NSString *port = self.port.stringValue;
    NSString *projectName = self.projectName.stringValue;
    NSString *idea = self.projectIdea.stringValue;
    if (![self matches:host pattern:@"^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$"] ||
        ![self matches:username pattern:@"^[A-Za-z_][A-Za-z0-9_-]{0,31}$"] ||
        port.integerValue < 1 || port.integerValue > 65535 ||
        ![self matches:port pattern:@"^[0-9]{1,5}$"]) {
        [self show:@"Enter the VPS address, login name, and port from your provider's welcome email before starting a project."];
        return;
    }
    if (![self matches:projectName pattern:@"^[a-z0-9][a-z0-9-]{0,62}$"]) {
        [self show:@"Choose a project folder name using lowercase letters, numbers, and hyphens only. SlopNet will not guess a name for you."];
        return;
    }
    if ([[idea stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0) {
        [self show:@"Describe what you want made in one sentence before asking SlopNet for a plan."];
        return;
    }
    NSString *script = [[NSBundle mainBundle] pathForResource:@"slopnet-vps-project" ofType:@"sh"];
    if (script == nil) {
        [self show:@"The project-plan helper is missing from this SlopNet app bundle. Rebuild the application."];
        return;
    }
    NSString *(^quote)(NSString *) = ^NSString *(NSString *value) {
        return [NSString stringWithFormat:@"'%@'", [value stringByReplacingOccurrencesOfString:@"'" withString:@"'\\\"'\\\"'"]];
    };
    NSString *command = [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", quote(script), quote(host), quote(port), quote(username), quote(projectName), quote(idea)];
    if ([self openTerminalForCommand:command]) {
        [self show:@"Terminal will create only the project folder you named, make a plan using the already-proven Codex app on your VPS, and wait for your approval before any code runs."];
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
