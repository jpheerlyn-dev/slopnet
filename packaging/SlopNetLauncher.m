// SlopNet — the Mac control window.
//
// Everything runs INSIDE this window now (see SlopNetConsole): no
// Terminal, no AppleScript, no macOS Automation permission. You see the
// same output an expert would see in a terminal, and you can answer its
// questions in the box underneath.

#import <Cocoa/Cocoa.h>
#import "SlopNetConsole.h"

@interface SlopNetAppDelegate : NSObject <NSApplicationDelegate, SlopNetConsoleDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSButton *hasVPS;
@property(nonatomic, strong) NSTextField *host;
@property(nonatomic, strong) NSTextField *username;
@property(nonatomic, strong) NSTextField *port;
@property(nonatomic, strong) NSTextField *projectName;
@property(nonatomic, strong) NSTextField *projectIdea;
@property(nonatomic, strong) SlopNetConsole *console;
@property(nonatomic, strong) NSButton *setupButton;
@property(nonatomic, strong) NSButton *projectButton;
@end

@implementation SlopNetAppDelegate

#pragma mark - small builders

- (NSTextField *)label:(NSString *)text size:(CGFloat)size grey:(BOOL)grey {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:size];
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.maximumNumberOfLines = 4;
    if (grey) label.textColor = [NSColor secondaryLabelColor];
    return label;
}

- (NSButton *)button:(NSString *)title action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
    button.title = title;
    button.target = self;
    button.action = action;
    button.bezelStyle = NSBezelStyleRounded;
    return button;
}

- (NSTextField *)field:(NSString *)placeholder value:(NSString *)value width:(CGFloat)width {
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    field.placeholderString = placeholder;
    if (value) field.stringValue = value;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field.widthAnchor constraintEqualToConstant:width].active = YES;
    [field.heightAnchor constraintEqualToConstant:24].active = YES;
    return field;
}

/// One labelled row, so the layout never needs pixel arithmetic.
- (NSStackView *)row:(NSString *)labelText control:(NSView *)control {
    NSTextField *label = [self label:labelText size:13 grey:NO];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label.widthAnchor constraintEqualToConstant:150].active = YES;
    NSStackView *row = [NSStackView stackViewWithViews:@[label, control]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 8;
    return row;
}

#pragma mark - window

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 860, 720)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    self.window.title = @"SlopNet";
    self.window.minSize = NSMakeSize(760, 560);
    [self.window center];

    NSTextField *title = [self label:@"SlopNet" size:28 grey:NO];
    title.font = [NSFont boldSystemFontOfSize:28];
    NSTextField *subtitle = [self label:
        @"Describe what you want built. Everything runs on your own VPS, and "
        @"you can watch every step below." size:13 grey:YES];

    self.hasVPS = [[NSButton alloc] initWithFrame:NSZeroRect];
    self.hasVPS.title = @"I already have a VPS";
    self.hasVPS.buttonType = NSButtonTypeSwitch;
    self.hasVPS.state = NSControlStateValueOn;
    self.hasVPS.target = self;
    self.hasVPS.action = @selector(changeVPSChoice:);

    self.host = [self field:@"the IP address from your VPS welcome email" value:nil width:330];
    self.username = [self field:@"root" value:@"root" width:200];
    self.port = [self field:@"22" value:@"22" width:80];
    self.projectName = [self field:@"a name you choose, like photo-sheet" value:nil width:240];
    self.projectIdea = [self field:@"a sentence in your own words" value:nil width:400];

    self.setupButton = [self button:@"Set up my VPS" action:@selector(beginSetup:)];
    self.setupButton.keyEquivalent = @"\r";
    self.projectButton = [self button:@"Make my project plan" action:@selector(beginProject:)];
    NSButton *clearButton = [self button:@"Clear output" action:@selector(clearConsole:)];

    NSStackView *buttons = [NSStackView stackViewWithViews:@[
        self.setupButton, self.projectButton, clearButton]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.spacing = 10;

    NSStackView *providers = [NSStackView stackViewWithViews:@[
        [self label:@"No VPS yet?" size:12 grey:YES],
        [self button:@"Hetzner" action:@selector(openHetzner:)],
        [self button:@"Contabo" action:@selector(openContabo:)],
        [self button:@"Hostinger" action:@selector(openHostinger:)]]];
    providers.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    providers.spacing = 8;

    self.console = [[SlopNetConsole alloc] initWithFrame:NSZeroRect];
    self.console.delegate = self;
    self.console.translatesAutoresizingMaskIntoConstraints = NO;
    [self.console.heightAnchor constraintGreaterThanOrEqualToConstant:260].active = YES;

    NSStackView *form = [NSStackView stackViewWithViews:@[
        title, subtitle, self.hasVPS,
        [self row:@"VPS address" control:self.host],
        [self row:@"VPS login name" control:self.username],
        [self row:@"Connection port" control:self.port],
        [self label:@"Your VPS password is never typed here or saved by SlopNet. "
                    @"The first connection asks for it in the window below, and it "
                    @"goes straight to your VPS." size:12 grey:YES],
        [self row:@"Project folder name" control:self.projectName],
        [self row:@"What do you want made?" control:self.projectIdea],
        buttons, providers, self.console]];
    form.orientation = NSUserInterfaceLayoutOrientationVertical;
    form.alignment = NSLayoutAttributeLeading;
    form.spacing = 10;
    form.edgeInsets = NSEdgeInsetsMake(20, 24, 20, 24);
    form.translatesAutoresizingMaskIntoConstraints = NO;
    [form setHuggingPriority:NSLayoutPriorityDefaultLow
              forOrientation:NSLayoutConstraintOrientationVertical];

    NSView *content = self.window.contentView;
    [content addSubview:form];
    [NSLayoutConstraint activateConstraints:@[
        [form.topAnchor constraintEqualToAnchor:content.topAnchor],
        [form.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [form.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [form.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [self.console.widthAnchor constraintEqualToAnchor:form.widthAnchor constant:-48],
    ]];

    [self.console note:@"Ready. Fill in your VPS details above and press "
                       @"“Set up my VPS”.\n"
                       @"Everything that happens will appear here. When a question "
                       @"appears, type your answer in the box below and press Return."];

    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

#pragma mark - actions

- (void)changeVPSChoice:(id)sender {
    BOOL have = self.hasVPS.state == NSControlStateValueOn;
    self.setupButton.enabled = have;
    self.projectButton.enabled = have;
    if (!have) {
        [self.console note:@"\nPick a VPS provider below, then come back with the "
                           @"address, login name and password from their email."];
    }
}

- (BOOL)matches:(NSString *)value pattern:(NSString *)pattern {
    NSRange range = NSMakeRange(0, value.length);
    NSRegularExpression *expression =
        [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    return [expression firstMatchInString:value options:0 range:range] != nil;
}

- (BOOL)connectionDetailsValid {
    if (![self matches:self.host.stringValue pattern:@"^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$"] ||
        ![self matches:self.username.stringValue pattern:@"^[A-Za-z_][A-Za-z0-9_-]{0,31}$"] ||
        self.port.integerValue < 1 || self.port.integerValue > 65535 ||
        ![self matches:self.port.stringValue pattern:@"^[0-9]{1,5}$"]) {
        [self.console note:@"\nCheck the VPS address and login name against your "
                           @"provider's welcome email. The port is almost always 22."];
        return NO;
    }
    return YES;
}

- (NSString *)helper:(NSString *)name {
    return [[NSBundle mainBundle] pathForResource:name ofType:@"sh"];
}

- (void)beginSetup:(id)sender {
    if (self.hasVPS.state != NSControlStateValueOn) { [self changeVPSChoice:nil]; return; }
    if (![self connectionDetailsValid]) return;
    NSString *script = [self helper:@"slopnet-vps-onboard"];
    if (script == nil) {
        [self.console note:@"The VPS setup helper is missing from this app. Build it again."];
        return;
    }
    [self.console note:@"\n=== Setting up your VPS ==="];
    [self.console runExecutable:@"/bin/bash"
                      arguments:@[script, self.host.stringValue,
                                  self.port.stringValue, self.username.stringValue]];
}

- (void)beginProject:(id)sender {
    if (self.hasVPS.state != NSControlStateValueOn) { [self changeVPSChoice:nil]; return; }
    if (![self connectionDetailsValid]) return;
    if (![self matches:self.projectName.stringValue pattern:@"^[a-z0-9][a-z0-9-]{0,62}$"]) {
        [self.console note:@"\nChoose a project folder name using lowercase letters, "
                           @"numbers and hyphens only. SlopNet will not pick a name for you."];
        return;
    }
    NSString *idea = [self.projectIdea.stringValue stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (idea.length == 0) {
        [self.console note:@"\nWrite one sentence about what you want made."];
        return;
    }
    NSString *script = [self helper:@"slopnet-vps-project"];
    if (script == nil) {
        [self.console note:@"The project helper is missing from this app. Build it again."];
        return;
    }
    [self.console note:@"\n=== Making your project plan ==="];
    [self.console runExecutable:@"/bin/bash"
                      arguments:@[script, self.host.stringValue, self.port.stringValue,
                                  self.username.stringValue, self.projectName.stringValue, idea]];
}

- (void)clearConsole:(id)sender { [self.console clear]; }

- (void)console:(SlopNetConsole *)console finishedWithStatus:(int)status {
    if (status == 0) {
        [self.console note:@"You can start the next step above."];
    } else {
        [self.console note:@"Nothing was left half-done. Read the last few lines "
                           @"above, fix what they mention, and press the button again."];
    }
}

- (void)open:(NSString *)address {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:address]];
}
- (void)openHetzner:(id)sender { [self open:@"https://www.hetzner.com/cloud/"]; }
- (void)openContabo:(id)sender { [self open:@"https://contabo.com/en/vps/"]; }
- (void)openHostinger:(id)sender { [self open:@"https://www.hostinger.com/vps-hosting"]; }

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
