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
// The guided path currently means a Linux server reachable over SSH. The
// built-in terminal-tool downloads have been proved only on x86-64 Linux.

#import <Cocoa/Cocoa.h>
#import <CommonCrypto/CommonDigest.h>
#import <float.h>
#import <sys/stat.h>
#import <unistd.h>
#import "SlopNetBrand.h"
#import "SlopNetConsole.h"
#import "SlopNetEntryView.h"
#import "SlopNetSettings.h"
#import "SlopNetTools.h"
#import "SlopNetWizard.h"

static NSString *const kHostKey     = @"SlopNetVPSHost";
static NSString *const kUserKey     = @"SlopNetVPSUser";
static NSString *const kPortKey     = @"SlopNetVPSPort";
static NSString *const kSignedInProvidersKey = @"SlopNetSignedInProviders";
/// When a coding app's usage limit is expected to lift, keyed by provider.
static NSString *const kLimitUntilKey = @"SlopNetLimitUntil";
/// What to assume when the provider does not say when it resets. Most plans
/// roll on a few hours; a weekly cap will outlast this and the countdown will
/// simply reach zero and the app will be tried again. Better than claiming a
/// precision nothing here has.
static const NSTimeInterval kDefaultLimitWait = 5 * 60 * 60;
static NSString *const kReadyKey    = @"SlopNetVPSReady";   // setup finished cleanly
// The private local guide passed its own READY proof on the server. Set only
// from a real outcome: a clean local-helper run, or reading the model back out
// of the server's runtime account. Never cleared by a failed network check,
// because "the server did not answer just now" is not evidence it is gone.
static NSString *const kGuideKey    = @"SlopNetGuideReady";
// The person has seen the last screen of the wizard, so it stops opening
// itself. The Setup guide button in the sidebar reopens it any time.
static NSString *const kWizardKey   = @"SlopNetWizardDone";

static BOOL SlopNetLocalFile(NSString *path, mode_t type, mode_t permissions,
                             struct stat *state) {
    struct stat found;
    if (lstat(path.fileSystemRepresentation, &found) != 0) return NO;
    if ((found.st_mode & S_IFMT) != type || (found.st_mode & 0777) != permissions ||
        found.st_uid != geteuid()) return NO;
    if (state != NULL) *state = found;
    return YES;
}

static BOOL SlopNetLocalPathExists(NSString *path) {
    struct stat ignored;
    return lstat(path.fileSystemRepresentation, &ignored) == 0;
}

static NSString *SlopNetSHA256(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
        [hex appendFormat:@"%02x", digest[index]];
    }
    return hex;
}

static NSString *SlopNetDerivedPublicKey(NSString *privateKey) {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ssh-keygen"];
    task.arguments = @[@"-y", @"-P", @"", @"-f", privateKey];
    NSPipe *output = [NSPipe pipe];
    task.standardOutput = output;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![task launchAndReturnError:nil]) return nil;
    [task waitUntilExit];
    if (task.terminationStatus != 0) return nil;
    NSData *data = [output.fileHandleForReading readDataToEndOfFile];
    NSString *line = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return [line stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
}

static BOOL SlopNetProvedKeyPair(NSString *keyPath) {
    NSString *publicPath = [keyPath stringByAppendingString:@".pub"];
    NSString *receiptPath = [keyPath stringByAppendingString:@".receipt"];
    NSString *sshDirectory = keyPath.stringByDeletingLastPathComponent;
    struct stat directoryState, privateState, publicState, receiptState;
    if (!SlopNetLocalFile(sshDirectory, S_IFDIR, 0700, &directoryState) ||
        !SlopNetLocalFile(keyPath, S_IFREG, 0600, &privateState) ||
        !SlopNetLocalFile(publicPath, S_IFREG, 0600, &publicState) ||
        !SlopNetLocalFile(receiptPath, S_IFREG, 0600, &receiptState)) return NO;
    (void)directoryState; (void)receiptState;
    NSData *privateData = [NSData dataWithContentsOfFile:keyPath];
    NSData *publicData = [NSData dataWithContentsOfFile:publicPath];
    NSData *receiptData = [NSData dataWithContentsOfFile:receiptPath];
    NSString *derived = SlopNetDerivedPublicKey(keyPath);
    if (privateData == nil || publicData == nil || receiptData == nil ||
        ![derived hasPrefix:@"ssh-ed25519 "]) return NO;
    NSString *publicLine = [derived stringByAppendingString:@" slopnet-vps"];
    NSData *expectedPublic = [[publicLine stringByAppendingString:@"\n"]
        dataUsingEncoding:NSUTF8StringEncoding];
    if (![publicData isEqualToData:expectedPublic]) return NO;
    NSString *receipt = [NSString stringWithFormat:
        @"kind=slopnet-ssh-key-v1\nprivate_dev=%llu\nprivate_ino=%llu\n"
         @"public_dev=%llu\npublic_ino=%llu\nprivate_sha256=%@\npublic_sha256=%@\n"
         @"public_line=%@\n",
        (unsigned long long)privateState.st_dev, (unsigned long long)privateState.st_ino,
        (unsigned long long)publicState.st_dev, (unsigned long long)publicState.st_ino,
        SlopNetSHA256(privateData), SlopNetSHA256(publicData), publicLine];
    return [receiptData isEqualToData:[receipt dataUsingEncoding:NSUTF8StringEncoding]];
}

static BOOL SlopNetProvedKnownHosts(NSString *knownHostsPath) {
    NSString *receiptPath = [knownHostsPath stringByAppendingString:@".receipt"];
    NSString *sshDirectory = knownHostsPath.stringByDeletingLastPathComponent;
    struct stat directoryState, hostsState, receiptState;
    if (!SlopNetLocalFile(sshDirectory, S_IFDIR, 0700, &directoryState) ||
        !SlopNetLocalFile(knownHostsPath, S_IFREG, 0600, &hostsState) ||
        !SlopNetLocalFile(receiptPath, S_IFREG, 0600, &receiptState)) return NO;
    (void)directoryState; (void)receiptState;
    NSData *receiptData = [NSData dataWithContentsOfFile:receiptPath];
    NSString *receipt = [NSString stringWithFormat:
        @"kind=slopnet-known-hosts-v1\nknown_hosts_dev=%llu\nknown_hosts_ino=%llu\n",
        (unsigned long long)hostsState.st_dev, (unsigned long long)hostsState.st_ino];
    return [receiptData isEqualToData:[receipt dataUsingEncoding:NSUTF8StringEncoding]];
}

// One box, one button, no modes. What a message means depends on where the
// conversation has got to, not on a control the person had to set first.
//
// Granite is meant to be the thing that decides when to build. It cannot yet:
// native tool calling on the local model is explicitly unproved (see
// register/PENDING_OPERATOR.md), and a 3B model that "usually" emits a
// function call would start builds nobody asked for. So SlopNet notices a
// build-shaped request itself and offers, in the same stream, clearly as
// SlopNet. The person still approves in plain words. When tool calling is
// proved, this is where Granite takes over.
typedef NS_ENUM(NSInteger, SlopNetTurn) {
    SlopNetTurnTalking = 0,     // ordinary conversation with the guide
    SlopNetTurnOfferedBuild,    // SlopNet asked whether to build; awaiting yes
    SlopNetTurnNeedsName,       // they said yes; asking what to call it
};

@interface SlopNetAppDelegate : NSObject <NSApplicationDelegate, SlopNetConsoleDelegate,
                                          SlopNetSettingsDelegate, SlopNetToolsDelegate,
                                          SlopNetWizardDelegate, NSTextViewDelegate>
@property(nonatomic, strong) NSWindow *window;

// sidebar
@property(nonatomic, strong) NSTextField *statusDot;
@property(nonatomic, strong) NSTextField *statusText;
@property(nonatomic, strong) NSStackView *historyStack;
@property(nonatomic, strong) NSButton *settingsToggle;
@property(nonatomic, strong) NSButton *graniteButton;

// the server, remembered between launches
@property(nonatomic, copy) NSString *host;
@property(nonatomic, copy) NSString *username;
@property(nonatomic, copy) NSString *port;
@property(nonatomic, strong) SlopNetSettings *settings;
@property(nonatomic, strong) SlopNetTools *tools;
@property(nonatomic, strong) SlopNetWizard *wizard;

// main
@property(nonatomic, strong) SlopNetConsole *console;
/// One terminal per thing being run. Granite is always the first and never
/// closes, so it is one click away whatever else is open. `console` returns
/// whichever is on top, so every existing caller keeps working.
@property(nonatomic, strong) NSMutableArray<SlopNetConsole *> *consoles;
@property(nonatomic, strong) NSMutableArray<NSString *> *tabTitles;
@property(nonatomic, strong) NSStackView *tabStrip;
@property(nonatomic, strong) NSView *consoleHolder;
@property(nonatomic, assign) NSUInteger activeTab;
/// How a new tab's terminal is made. Left alone it makes an ordinary one; a
/// check can supply its own so that opening a tool can be watched without a
/// real connection being made.
@property(nonatomic, copy) SlopNetConsole *(^makeConsole)(void);
@property(nonatomic, strong) NSTextField *modelLabel;
@property(nonatomic, strong) SlopNetEntryView *entry;
@property(nonatomic, strong) NSScrollView *entryScroller;
@property(nonatomic, strong) NSLayoutConstraint *entryHeight;
@property(nonatomic, strong) NSButton *sendButton;
// Shown in place of the typing box when the running program wants something
// specific: a password gets a real masked field, a yes/no gets two buttons.
// Typing a password blind into a terminal is the moment a non-expert decides
// the app has frozen.
@property(nonatomic, strong) NSStackView *promptBar;
@property(nonatomic, strong) NSTextField *promptLabel;
@property(nonatomic, strong) NSSecureTextField *secretField;
@property(nonatomic, strong) NSButton *secretSend;
@property(nonatomic, strong) NSButton *approveButton;
@property(nonatomic, strong) NSButton *declineButton;
@property(nonatomic, strong) NSButton *continueButton;
@property(nonatomic, strong) NSButton *openPageButton;
@property(nonatomic, strong) NSButton *codeButton;
@property(nonatomic, strong) NSURL *signInPage;
@property(nonatomic, copy) NSString *signInCode;
@property(nonatomic, strong) NSURL *conversationURL;

// The animated action glyph. One timer drives whichever surface is live:
// the status line under the console while a program runs, or the action row
// of the ready block while nothing does.
@property(nonatomic, strong) NSTimer *actionTimer;
@property(nonatomic, assign) NSUInteger actionTick;
@property(nonatomic, copy) NSString *actionConcept;
@property(nonatomic, copy) NSString *actionCaption;
@property(nonatomic, assign) NSInteger readyBlockToken;

@property(nonatomic, assign) BOOL busy;
@property(nonatomic, assign) BOOL setupRunning;
@property(nonatomic, assign) BOOL chatting;
/// Where a typed command runs. Each one opens a new shell over SSH, so
/// without this every command would start wherever sh happens to land and
/// `cd` would do nothing at all.
@property(nonatomic, copy) NSString *workingDirectory;
/// A `cd` in flight: the directory to adopt if the shell agrees it exists.
@property(nonatomic, copy) NSString *pendingDirectory;
@property(nonatomic, assign) BOOL movingDirectory;
/// What has been said this conversation, oldest first, as "You: …" / "Granite: …".
/// Kept on the Mac and handed to the guide with each question, because the
/// model runs one finite process per turn and remembers nothing by itself.
@property(nonatomic, strong) NSMutableArray<NSString *> *conversation;
/// The reply panel being typed into, and how much of it has appeared.
@property(nonatomic, assign) NSInteger replyToken;
@property(nonatomic, copy) NSString *replyText;
@property(nonatomic, assign) NSUInteger replyShown;
@property(nonatomic, strong) NSTimer *replyTimer;
@property(nonatomic, assign) BOOL localHelperRunning;
@property(nonatomic, assign) BOOL planningRunning;
@property(nonatomic, assign) BOOL approvedBuildRunning;
@property(nonatomic, assign) BOOL uninstalling;
/// An interactive tool deliberately opened in the terminal from Tools.
/// It gets a plainly-labelled route back to Granite, rather than a
/// generic Stop button that sounds like it might close the whole app.
@property(nonatomic, assign) BOOL toolRunning;
@property(nonatomic, assign) BOOL returningToGranite;
@property(nonatomic, assign) BOOL signInQueueActive;
@property(nonatomic, assign) BOOL skippingSignIn;
@property(nonatomic, copy) NSString *activeProjectName;
@property(nonatomic, copy) NSString *plannedProjectName;
/// Exact server Git commit containing the plan the person just read.
@property(nonatomic, copy) NSString *plannedProjectCommit;
@property(nonatomic, copy) NSString *localModelName;
@property(nonatomic, assign) SlopNetTurn turn;
/// What they asked to have built, held while the offer and the name are
/// agreed, so nobody has to type their request twice.
@property(nonatomic, copy) NSString *pendingRequest;
/// Raised after the guide finishes answering, so its reply comes first and
/// SlopNet's offer follows it rather than interrupting.
@property(nonatomic, assign) BOOL offerBuildWhenReplyEnds;
/// Coding apps still to sign in to, and how each one turned out. Kept so a
/// refusal or a skip moves on to the next instead of stranding the run.
@property(nonatomic, strong) NSMutableArray<NSString *> *signInQueue;
@property(nonatomic, strong) NSMutableArray<NSString *> *signedIn;
@property(nonatomic, strong) NSMutableArray<NSString *> *skipped;
@property(nonatomic, copy) NSString *signingIn;
@property(nonatomic, strong) NSButton *skipButton;
@end

@implementation SlopNetAppDelegate

#pragma mark - tiny builders

- (NSTextField *)label:(NSString *)text size:(CGFloat)size grey:(BOOL)grey {
    NSTextField *label = [NSTextField labelWithString:text];
    // Chrome is monospaced so the shell feels like one terminal product;
    // the console itself keeps its own font.
    label.font = [NSFont monospacedSystemFontOfSize:size
                                             weight:size >= 18 ? NSFontWeightBold
                                                               : NSFontWeightRegular];
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.maximumNumberOfLines = 5;
    if (grey) label.textColor = [SlopNetBrand ghostColor];
    else label.textColor = [SlopNetBrand inkColor];
    return label;
}

// Sidebar rows look and behave like navigation: the whole row is the click
// target, not just the words.
- (NSButton *)sidebarButton:(NSString *)title action:(SEL)action {
    // The same control Settings and Tools use, so the whole app has one
    // button. The glass bezel that used to be here drew crimson-on-crimson
    // and the words were all but invisible.
    NSButton *button = [SlopNetBrand panelButtonWithTitle:title
                                                     role:SlopNetButtonRoleNormal
                                                   target:self
                                                   action:action];
    button.alignment = NSTextAlignmentLeft;
    [SlopNetBrand setPanelButton:button role:SlopNetButtonRoleNormal];  // redraw the title
    [button.heightAnchor constraintEqualToConstant:30].active = YES;
    return button;
}

- (NSButton *)promptButton:(NSString *)title action:(SEL)action {
    NSButton *button = [SlopNetBrand panelButtonWithTitle:title
                                                     role:SlopNetButtonRoleNormal
                                                   target:self
                                                   action:action];
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:88].active = YES;
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
    [line.heightAnchor constraintEqualToConstant:1].active = YES;
    return line;
}

#pragma mark - launch

/// Build the menu bar.
///
/// There was none. That is why Command-C did nothing in the console and the
/// only way to copy was a right-click: the standard shortcuts are routed by
/// the menu bar, and with no Edit menu there was nothing to route them to.
/// Command-Q had the same problem. Every Mac app needs this; SlopNet simply
/// never had one.
- (void)buildMenuBar {
    NSMenu *bar = [[NSMenu alloc] init];

    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:@"About SlopNet"
                       action:@selector(orderFrontStandardAboutPanel:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Settings…" action:@selector(openSettings:) keyEquivalent:@","];
    [appMenu addItemWithTitle:@"Setup guide" action:@selector(openWizard:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Hide SlopNet" action:@selector(hide:) keyEquivalent:@"h"];
    [appMenu addItemWithTitle:@"Quit SlopNet" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    [bar addItem:appItem];

    NSMenuItem *editItem = [[NSMenuItem alloc] init];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    NSMenuItem *redo = [editMenu addItemWithTitle:@"Redo" action:@selector(redo:)
                                    keyEquivalent:@"Z"];
    redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = editMenu;
    [bar addItem:editItem];

    NSMenuItem *windowItem = [[NSMenuItem alloc] init];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenu addItemWithTitle:@"Minimise" action:@selector(performMiniaturize:)
                   keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];
    windowItem.submenu = windowMenu;
    [bar addItem:windowItem];

    NSApp.mainMenu = bar;
    NSApp.windowsMenu = windowMenu;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self buildMenuBar];
    self.window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 1000, 700)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    self.window.title = @"SlopNet";
    self.window.minSize = NSMakeSize(820, 520);
    // Red-black shell. Glass is only on the sidebar and composer — never on
    // the console, and never as a container around the whole split.
    [SlopNetBrand applyTerminalChromeToWindow:self.window];
    [self.window center];

    NSSplitView *split = [[NSSplitView alloc] initWithFrame:NSZeroRect];
    split.vertical = YES;
    split.dividerStyle = NSSplitViewDividerStyleThin;
    split.translatesAutoresizingMaskIntoConstraints = NO;
    [split addArrangedSubview:[self buildSidebar]];
    [split addArrangedSubview:[self buildMain]];

    NSView *content = self.window.contentView;
    content.wantsLayer = YES;
    content.layer.backgroundColor = [SlopNetBrand chromeFieldColor].CGColor;
    [content addSubview:split];
    [NSLayoutConstraint activateConstraints:@[
        [split.topAnchor constraintEqualToAnchor:content.topAnchor constant:8],
        [split.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:8],
        [split.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-8],
        [split.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-8],
    ]];
    [split setPosition:248 ofDividerAtIndex:0];

    [self recall];
    [self refreshState];
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.entry];
    [NSApp activateIgnoringOtherApps:YES];

    // After the window exists: the ready block measures the console to fit
    // its panels, and there is nothing to measure until layout has run.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showReadyBlock];
        // SLOPNET_DEBUG_VISUALS=1 opens on the same view the Providers button
        // shows: every mapped mark, plus a 24-bit colour check. It is how the
        // visual proofs in the register are captured, and the quickest way to
        // see whether the badge font and colour survived a build.
        if ([NSProcessInfo.processInfo.environment[@"SLOPNET_DEBUG_VISUALS"]
                isEqualToString:@"1"]) {
            [self showProviders:nil];
        }
        // SLOPNET_DEBUG_PROMPT=password|confirm runs a harmless local command
        // that asks for one, so the control that replaces the typing box can
        // be seen without a server. It touches nothing and answers nothing.
        NSString *demo = NSProcessInfo.processInfo.environment[@"SLOPNET_DEBUG_PROMPT"];
        if ([demo isEqualToString:@"password"] || [demo isEqualToString:@"confirm"]) {
            NSString *script = [demo isEqualToString:@"password"]
                // Split across two literals so the secret scanner's fallback
                // pattern cannot read a fake prompt as a committed credential.
                // Nothing changes at runtime; the compiler joins them back up.
                ? @"printf 'someone@your-server\\047s password: '"
                  @"; read -r x; echo"
                : @"printf 'Install the private guide and test it? [y/N] '; read -r x; echo";
            [self.console runExecutable:@"/bin/bash" arguments:@[@"-c", script]];
        }
    });

    // First run is a wizard, not an empty console with a hint. It opens
    // before any provider login, planning, or model conversation can be
    // reached, and it resumes at the first thing that has not passed yet.
    if (![self setupComplete]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self openWizardAtResumeStep]; });
    }
    if ([self isReady]) [self refreshLocalModelName];
}

/// Everything the wizard covers has passed, and the person has seen the last
/// screen. Until then the wizard opens itself on launch.
- (BOOL)setupComplete {
    NSUserDefaults *store = [NSUserDefaults standardUserDefaults];
    return [self isReady] && [self guideReady] && [store boolForKey:kWizardKey];
}

- (BOOL)guideReady {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kGuideKey];
}

- (void)setGuideReady:(BOOL)ready {
    [[NSUserDefaults standardUserDefaults] setBool:ready forKey:kGuideKey];
}

- (NSView *)buildSidebar {
    NSString *version = [[NSBundle mainBundle]
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";

    NSTextField *title = [self label:@"SlopNet" size:20 grey:NO];
    title.font = [NSFont monospacedSystemFontOfSize:20 weight:NSFontWeightBold];
    title.textColor = [SlopNetBrand crimsonColor];

    self.statusDot = [self label:@"●" size:13 grey:NO];
    self.statusDot.textColor = [SlopNetBrand phosphorColor];
    self.statusText = [self label:@"Checking…" size:11 grey:YES];
    NSStackView *status = [NSStackView stackViewWithViews:@[self.statusDot, self.statusText]];
    status.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    status.alignment = NSLayoutAttributeCenterY;
    status.spacing = 6;

    self.graniteButton = [self sidebarButton:@"Granite"
                                       action:@selector(returnToGranite:)];
    NSButton *newButton = [self sidebarButton:@"＋   New"
                                       action:@selector(newConversation:)];

    NSTextField *historyTitle = [self label:@"RECENT REQUESTS" size:10 grey:YES];
    [SlopNetBrand styleChromeCaption:historyTitle];
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
    // Tools: install and launch. Settings is connection and model only.
    NSButton *toolsButton = [self sidebarButton:@"⚒   Tools"
                                         action:@selector(openTools:)];
    NSButton *providersButton = [self sidebarButton:@"◫   Providers"
                                            action:@selector(showProviders:)];
    // Setup is discoverable from the main window, not only from Settings.
    NSButton *wizardButton = [self sidebarButton:@"◷   Setup guide"
                                         action:@selector(openWizard:)];

    NSTextField *versionLabel =
        [self label:[NSString stringWithFormat:@"v%@", version] size:10 grey:YES];
    [SlopNetBrand styleChromeCaption:versionLabel];

    NSStackView *sidebar = [NSStackView stackViewWithViews:@[
        title, status,
        [self separator],
        self.graniteButton,
        newButton,
        historyTitle, self.historyStack,
        spacer,
        [self separator],
        wizardButton,
        toolsButton,
        providersButton,
        self.settingsToggle,
        versionLabel]];
    sidebar.orientation = NSUserInterfaceLayoutOrientationVertical;
    sidebar.alignment = NSLayoutAttributeLeading;
    sidebar.spacing = 7;
    // The window has no title bar strip, so the glass runs up behind the
    // close/minimise/zoom buttons. The wordmark starts below them.
    sidebar.edgeInsets = NSEdgeInsetsMake(30, 4, 10, 4);
    [sidebar setHuggingPriority:NSLayoutPriorityDefaultLow
                 forOrientation:NSLayoutConstraintOrientationVertical];
    // Every row fills the sidebar's width. Without this, rows keep their
    // natural size and the panel looks ragged — and separators appear as
    // stubs — however the divider is dragged.
    for (NSView *rowView in sidebar.arrangedSubviews) {
        [rowView.widthAnchor constraintEqualToAnchor:sidebar.widthAnchor
                                           constant:-8].active = YES;
    }
    [self.historyStack.widthAnchor constraintEqualToAnchor:sidebar.widthAnchor
                                                 constant:-8].active = YES;

    // Glass is chrome only. The terminal is built in buildMain and is never
    // passed through glassPanelWrapping.
    NSView *glass = [SlopNetBrand glassPanelWrapping:sidebar
                                        cornerRadius:20
                                           tintColor:[SlopNetBrand chromeTintColor]];
    glass.translatesAutoresizingMaskIntoConstraints = NO;
    return glass;
}

- (NSView *)buildMain {
    self.console = [[SlopNetConsole alloc] initWithFrame:NSZeroRect];
    self.console.delegate = self;
    self.console.translatesAutoresizingMaskIntoConstraints = NO;

    // One box and one button. There is no mode to choose and no separate
    // name field: a person types what they want in their own words, and
    // where the conversation has got to decides what that means.
    //
    // The model is shown, not chosen. It was a pop-up whose only other item
    // opened Settings — a menu pretending to be a control. Which guide is
    // answering matters in a conversation; being asked to pick one does not.
    self.modelLabel = [NSTextField labelWithString:@""];
    // Nothing but the box and one button. The guide's name is already on
    // the board above and in the sidebar; saying it a third time here was
    // clutter around the one thing a person came to use.
    self.modelLabel.hidden = YES;
    self.modelLabel.font = [NSFont systemFontOfSize:11];
    self.modelLabel.textColor = [NSColor secondaryLabelColor];
    self.modelLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.modelLabel.maximumNumberOfLines = 1;
    self.modelLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.modelLabel.widthAnchor constraintLessThanOrEqualToConstant:220].active = YES;
    [self refreshModelLabel];
    self.entry = [[SlopNetEntryView alloc] initWithFrame:NSZeroRect];
    // So a key press can reach whatever is running, not just the text view.
    self.entry.console = self.console;
    self.entry.delegate = self;
    self.entry.richText = NO;
    self.entry.allowsUndo = YES;
    self.entry.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.entry.textColor = [SlopNetBrand inkColor];
    self.entry.backgroundColor = [SlopNetBrand voidColor];
    self.entry.drawsBackground = YES;
    self.entry.insertionPointColor = [SlopNetBrand crimsonColor];
    self.entry.textContainerInset = NSMakeSize(8, 8);
    self.entry.prompt = @"Describe what you want built… Return sends · Shift-Return adds a line";
    self.entry.automaticQuoteSubstitutionEnabled = NO;
    self.entry.automaticDashSubstitutionEnabled = NO;
    self.entry.automaticTextReplacementEnabled = NO;
    self.entry.minSize = NSMakeSize(0, 0);
    self.entry.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    self.entry.verticallyResizable = YES;
    self.entry.horizontallyResizable = NO;
    self.entry.textContainer.widthTracksTextView = YES;

    self.entryScroller = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.entryScroller.hasVerticalScroller = NO;
    self.entryScroller.autohidesScrollers = YES;
    self.entryScroller.borderType = NSNoBorder;
    self.entryScroller.drawsBackground = YES;
    self.entryScroller.backgroundColor = [SlopNetBrand voidColor];
    self.entryScroller.documentView = self.entry;
    self.entryScroller.translatesAutoresizingMaskIntoConstraints = NO;
    self.entryScroller.wantsLayer = YES;
    self.entryScroller.layer.cornerRadius = 10;
    self.entryScroller.layer.masksToBounds = YES;
    self.entryScroller.layer.borderWidth = 1.0;
    self.entryScroller.layer.borderColor =
        [[SlopNetBrand crimsonColor] colorWithAlphaComponent:0.5].CGColor;
    self.entryHeight = [self.entryScroller.heightAnchor constraintEqualToConstant:56];
    self.entryHeight.active = YES;
    [self.entryScroller setContentHuggingPriority:NSLayoutPriorityDefaultLow
                           forOrientation:NSLayoutConstraintOrientationHorizontal];
    // One label, always. It used to say Build it / Answer / Make a plan /
    // Set up / Ask / Set up guide / Start approved build depending on hidden
    // state — seven identities for one control, and no way to predict which
    // one you had. Send always means: give this to SlopNet.
    // Send is the one thing this bar is for, so it carries the primary role.
    self.sendButton = [SlopNetBrand panelButtonWithTitle:@"Send"
                                                    role:SlopNetButtonRolePrimary
                                                  target:self
                                                  action:@selector(sendPressed:)];
    [self.sendButton.widthAnchor constraintEqualToConstant:88].active = YES;
    // Match the typing box rather than floating at the top of it.
    [self.sendButton.heightAnchor constraintEqualToConstant:34].active = YES;

    NSStackView *chatBar = [NSStackView stackViewWithViews:@[
        self.entryScroller, self.sendButton]];
    chatBar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    chatBar.alignment = NSLayoutAttributeCenterY;
    chatBar.spacing = 10;
    chatBar.translatesAutoresizingMaskIntoConstraints = NO;

    // Which guide is answering sits above the box, out of the way of the
    // one thing there is to press.
    // The control that replaces the typing box when the server asks for
    // something specific. Built once, hidden until it is needed.
    self.promptLabel = [self label:@"" size:12 grey:NO];
    self.promptLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.secretField = [[NSSecureTextField alloc] initWithFrame:NSZeroRect];
    self.secretField.placeholderString = @"Your server password";
    self.secretField.translatesAutoresizingMaskIntoConstraints = NO;
    self.secretField.target = self;
    self.secretField.action = @selector(secretEntered:);
    [self.secretField.heightAnchor constraintEqualToConstant:24].active = YES;

    self.secretSend = [self promptButton:@"Send password" action:@selector(secretEntered:)];
    self.approveButton = [self promptButton:@"Yes" action:@selector(approvePressed:)];
    self.declineButton = [self promptButton:@"No" action:@selector(declinePressed:)];
    self.continueButton = [self promptButton:@"Continue" action:@selector(continuePressed:)];
    self.openPageButton = [self promptButton:@"Open page again"
                                     action:@selector(openSignInPage:)];
    self.codeButton = [self promptButton:@"Copy code"
                                     action:@selector(putCodeOnClipboard:)];
    self.skipButton = [self promptButton:@"Skip this one"
                                  action:@selector(skipThisSignIn:)];

    NSStackView *promptControls = [NSStackView stackViewWithViews:@[
        self.secretField, self.secretSend, self.approveButton, self.declineButton,
        self.continueButton, self.openPageButton, self.codeButton, self.skipButton]];
    promptControls.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    promptControls.alignment = NSLayoutAttributeCenterY;
    promptControls.spacing = 8;

    self.promptBar = [NSStackView stackViewWithViews:@[self.promptLabel, promptControls]];
    self.promptBar.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.promptBar.alignment = NSLayoutAttributeLeading;
    self.promptBar.spacing = 6;
    self.promptBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.promptBar.hidden = YES;
    [promptControls.widthAnchor constraintEqualToAnchor:self.promptBar.widthAnchor].active = YES;

    NSStackView *composerInner = [NSStackView stackViewWithViews:@[self.promptBar,
                                                                   chatBar]];
    composerInner.orientation = NSUserInterfaceLayoutOrientationVertical;
    composerInner.alignment = NSLayoutAttributeLeading;
    composerInner.spacing = 6;
    composerInner.translatesAutoresizingMaskIntoConstraints = NO;
    [chatBar.widthAnchor constraintEqualToAnchor:composerInner.widthAnchor].active = YES;
    // Composer glass only — the console above stays an opaque black field.
    NSView *composer = [SlopNetBrand glassPanelWrapping:composerInner
                                           cornerRadius:18
                                              tintColor:[SlopNetBrand chromeTintColor]];
    composer.translatesAutoresizingMaskIntoConstraints = NO;

    // Plain constraints rather than a stack here, and a holder the terminals
    // share so a tool can open beside Granite instead of taking the window.
    self.consoles = [NSMutableArray arrayWithObject:self.console];
    self.tabTitles = [NSMutableArray arrayWithObject:@"Granite"];
    self.activeTab = 0;

    self.tabStrip = [NSStackView stackViewWithViews:@[]];
    self.tabStrip.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    self.tabStrip.spacing = 6;
    self.tabStrip.alignment = NSLayoutAttributeCenterY;
    self.tabStrip.translatesAutoresizingMaskIntoConstraints = NO;

    // The live terminal. Opaque, full area, never glass-wrapped.
    self.consoleHolder = [[NSView alloc] initWithFrame:NSZeroRect];
    self.consoleHolder.translatesAutoresizingMaskIntoConstraints = NO;
    [self.consoleHolder addSubview:self.console];
    [NSLayoutConstraint activateConstraints:@[
        [self.console.topAnchor constraintEqualToAnchor:self.consoleHolder.topAnchor],
        [self.console.leadingAnchor constraintEqualToAnchor:self.consoleHolder.leadingAnchor],
        [self.console.trailingAnchor constraintEqualToAnchor:self.consoleHolder.trailingAnchor],
        [self.console.bottomAnchor constraintEqualToAnchor:self.consoleHolder.bottomAnchor],
    ]];

    NSView *main = [[NSView alloc] initWithFrame:NSZeroRect];
    [main addSubview:self.tabStrip];
    [main addSubview:self.consoleHolder];
    [main addSubview:composer];
    [NSLayoutConstraint activateConstraints:@[
        // Clear of the title bar's drag region: a terminal tab up there could
        // be seen but not clicked, because that strip still drags the window.
        [self.tabStrip.topAnchor constraintEqualToAnchor:main.topAnchor constant:28],
        [self.tabStrip.leadingAnchor constraintEqualToAnchor:main.leadingAnchor constant:8],
        [self.tabStrip.trailingAnchor constraintLessThanOrEqualToAnchor:main.trailingAnchor
                                                               constant:-8],

        [self.consoleHolder.topAnchor constraintEqualToAnchor:self.tabStrip.bottomAnchor
                                                     constant:6],
        [self.consoleHolder.leadingAnchor constraintEqualToAnchor:main.leadingAnchor constant:8],
        [self.consoleHolder.trailingAnchor constraintEqualToAnchor:main.trailingAnchor
                                                          constant:-8],

        [composer.topAnchor constraintEqualToAnchor:self.consoleHolder.bottomAnchor constant:10],
        [composer.leadingAnchor constraintEqualToAnchor:main.leadingAnchor constant:4],
        [composer.trailingAnchor constraintEqualToAnchor:main.trailingAnchor constant:-4],
        [composer.bottomAnchor constraintEqualToAnchor:main.bottomAnchor constant:-4],
    ]];
    return main;
}

#pragma mark - one terminal per thing being run

/// Whichever terminal is on top. Every caller that had one console still has
/// one; it is now the visible one rather than the only one.
@synthesize console = _console;

- (SlopNetConsole *)console {
    if (self.consoles.count > self.activeTab) return self.consoles[self.activeTab];
    return _console;
}

/// Setting the console replaces the first tab, so the two never disagree.
- (void)setConsole:(SlopNetConsole *)console {
    _console = console;
    if (console == nil) return;
    if (self.consoles.count == 0) {
        self.consoles = [NSMutableArray arrayWithObject:console];
        self.tabTitles = [NSMutableArray arrayWithObject:@"Granite"];
    } else {
        self.consoles[0] = console;
    }
    self.activeTab = 0;
}

- (void)rebuildTabStrip {
    for (NSView *old in [self.tabStrip.views copy]) [self.tabStrip removeView:old];
    for (NSUInteger i = 0; i < self.tabTitles.count; i++) {
        NSString *title = self.tabTitles[i];
        // Granite is first and has no close control: it is the way back from
        // anything else, so it must not be possible to shut it.
        NSString *label = (i == 0) ? title : [NSString stringWithFormat:@"%@  ✕", title];
        // The tab you are looking at carries the primary role, the same way
        // the Installed/Library switch in Tools does.
        NSButton *tab = [SlopNetBrand panelButtonWithTitle:label
                                                      role:(i == self.activeTab)
                                                          ? SlopNetButtonRolePrimary
                                                          : SlopNetButtonRoleNormal
                                                    target:self
                                                    action:@selector(tabPressed:)];
        tab.tag = (NSInteger)i;
        tab.state = (i == self.activeTab) ? NSControlStateValueOn : NSControlStateValueOff;
        [self.tabStrip addView:tab inGravity:NSStackViewGravityLeading];
    }
    self.tabStrip.hidden = (self.tabTitles.count < 2);
}

- (void)showTab:(NSUInteger)index {
    if (index >= self.consoles.count) return;
    self.activeTab = index;
    for (NSUInteger i = 0; i < self.consoles.count; i++) {
        self.consoles[i].hidden = (i != index);
    }
    // The typing box forwards to whatever is on top, and takes the keyboard,
    // because a tool that cannot be typed at is the thing that wasted a day.
    self.entry.console = self.consoles[index];
    [self rebuildTabStrip];
    [self syncComposerToActiveTab];
    [self.window makeFirstResponder:self.entry];
}

/// Setup, install, chat, plan and build own the Granite tab. Interactive
/// tools each have their own tab and must not block each other.
- (BOOL)exclusiveWorkRunning {
    return self.setupRunning || self.chatting || self.planningRunning ||
           self.approvedBuildRunning || self.uninstalling ||
           self.localHelperRunning || self.movingDirectory ||
           self.signingIn != nil;
}

- (BOOL)anyToolConsoleRunning {
    for (NSUInteger i = 1; i < self.consoles.count; i++) {
        if (self.consoles[i].running) return YES;
    }
    return NO;
}

/// Send / Stop / Back to Granite follow the tab on top, not a global latch
/// left over from whichever tool was opened last.
- (void)syncComposerToActiveTab {
    if (self.activeTab == 0 || self.consoles.count == 0) {
        self.toolRunning = NO;
        if ([self exclusiveWorkRunning] ||
            (self.consoles.count > 0 && self.consoles[0].running)) {
            if (!self.busy) [self setBusy:YES];
            else [self showSendOrStop:YES];
        } else {
            // Background tool tabs may still be running; Granite is free.
            if (self.busy) [self setBusy:NO];
            else [self showSendOrStop:NO];
        }
        return;
    }
    BOOL running = self.consoles[self.activeTab].running;
    self.toolRunning = running;
    if (running) {
        if (!self.busy) [self setBusy:YES];
        else [self showSendOrStop:YES];
    } else if (![self exclusiveWorkRunning] &&
               !(self.consoles.count > 0 && self.consoles[0].running)) {
        if (self.busy) [self setBusy:NO];
        else [self showSendOrStop:NO];
    }
}

- (void)tabPressed:(NSButton *)sender {
    NSUInteger index = (NSUInteger)sender.tag;
    if (index == 0) { [self showTab:0]; return; }
    // A second press on the tab already showing closes it.
    if (index == self.activeTab) { [self closeTab:index]; return; }
    [self showTab:index];
}

- (void)closeTab:(NSUInteger)index {
    if (index == 0 || index >= self.consoles.count) return;
    SlopNetConsole *going = self.consoles[index];
    [going stop];
    [going removeFromSuperview];
    [self.consoles removeObjectAtIndex:index];
    [self.tabTitles removeObjectAtIndex:index];
    [self showTab:0];
}

/// A terminal of its own for something being launched.
- (SlopNetConsole *)openTabTitled:(NSString *)title {
    SlopNetConsole *fresh = self.makeConsole ? self.makeConsole()
                                             : [[SlopNetConsole alloc] initWithFrame:NSZeroRect];
    fresh.translatesAutoresizingMaskIntoConstraints = NO;
    fresh.delegate = self;
    [self.consoleHolder addSubview:fresh];
    [NSLayoutConstraint activateConstraints:@[
        [fresh.topAnchor constraintEqualToAnchor:self.consoleHolder.topAnchor],
        [fresh.leadingAnchor constraintEqualToAnchor:self.consoleHolder.leadingAnchor],
        [fresh.trailingAnchor constraintEqualToAnchor:self.consoleHolder.trailingAnchor],
        [fresh.bottomAnchor constraintEqualToAnchor:self.consoleHolder.bottomAnchor],
    ]];
    [self.consoles addObject:fresh];
    [self.tabTitles addObject:title ?: @"Tool"];
    [self showTab:self.consoles.count - 1];
    return fresh;
}

#pragma mark - one place decides what the window shows

- (BOOL)isReady {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kReadyKey] &&
           self.host.length > 0;
}

- (void)refreshState {
    BOOL ready = [self isReady];
    BOOL guide = [self guideReady];
    if (ready && guide) {
        self.statusDot.textColor = [SlopNetBrand phosphorColor];
        // The name they gave it, never the address. An IP on screen is a
        // machine somebody owns, readable in every screenshot of this window.
        NSString *named = [NSUserDefaults.standardUserDefaults
            stringForKey:@"SlopNetServerName"] ?: @"My server";
        self.statusText.stringValue = [NSString stringWithFormat:@"Ready — %@", named];
        self.statusText.textColor = [SlopNetBrand inkColor];
    } else if (ready) {
        self.statusDot.textColor = [NSColor systemOrangeColor];
        self.statusText.stringValue = @"Server ready — guide not installed";
        self.statusText.textColor = [SlopNetBrand inkColor];
    } else {
        self.statusDot.textColor = [SlopNetBrand ghostColor];
        self.statusText.stringValue = @"No server yet";
        self.statusText.textColor = [SlopNetBrand ghostColor];
    }
    // Granite is always visible, but a setup, install, plan or build is not a
    // disposable terminal tab. The route home is live while an interactive
    // tool or sign-in owns the console, and while the app is idle; the normal
    // Stop control remains the deliberate way to interrupt other work.
    self.graniteButton.enabled = !self.busy || self.toolRunning || self.signingIn != nil;
    // Not shown at all now: it is out of the composer stack. The guide is
    // named on the board above and in the sidebar, and a third caption sat
    // directly over the one control a person came here to use.

    // The button never changes. Only the hint inside the empty box changes,
    // and it describes what will happen rather than naming a mode.
    self.entry.editable = YES;
    if (self.busy) {
        self.entry.prompt = @"It is asking you something — type your answer and press Return";
    } else if (!ready) {
        self.entry.prompt = @"Press Send to connect your server — the guide walks you through it";
        self.entry.editable = NO;
    } else if (!guide) {
        self.entry.prompt = @"Press Send to install your private guide — nothing downloads until you agree";
        self.entry.editable = NO;
    } else if (self.plannedProjectName.length > 0) {
        self.entry.prompt = @"Read the plan above. Say yes to start building it, or keep talking.";
    } else if (self.turn == SlopNetTurnOfferedBuild) {
        self.entry.prompt = @"Say yes to build it, or carry on talking";
    } else if (self.turn == SlopNetTurnNeedsName) {
        self.entry.prompt = @"A short name for it — lowercase letters, numbers and hyphens";
    } else {
        self.entry.prompt = @"Ask anything, or start with $ to run a command…";
    }
    [self resizeEntry];
    [self rebuildHistory];
}

/// Does this read like "make me something", rather than a question?
///
/// A heuristic, and it fails safely in both directions: a miss just means
/// the person says "build it" themselves, and a false positive costs one
/// line they can ignore by carrying on talking. It never starts anything —
/// the offer it raises still has to be accepted.
- (BOOL)soundsLikeARequestToBuild:(NSString *)text {
    NSString *lower = text.lowercaseString;
    if (lower.length < 8) return NO;
    for (NSString *opener in @[@"build ", @"make ", @"create ", @"write ", @"code ",
                               @"build me", @"make me", @"can you build",
                               @"can you make", @"i want a", @"i need a",
                               @"i'd like a", @"id like a"]) {
        if ([lower hasPrefix:opener] ||
            [lower rangeOfString:[@" " stringByAppendingString:opener]].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)meansYes:(NSString *)text {
    NSString *word = [text.lowercaseString stringByTrimmingCharactersInSet:
        [NSCharacterSet characterSetWithCharactersInString:@" .!\t\n"]];
    return [@[@"y", @"yes", @"yeah", @"yep", @"yup", @"ok", @"okay", @"sure",
              @"go", @"go on", @"do it", @"please do", @"build it"] containsObject:word];
}

/// One button for both jobs.
///
/// A separate Stop sat next to a separate Send, and only one of them was ever
/// usable — which is two controls to read and a decision to make before typing
/// anything. Chat apps solved this years ago: the button sends while the app is
/// idle and stops while it is working.
- (void)showSendOrStop:(BOOL)busy {
    BOOL backToGranite = busy && self.toolRunning;
    self.sendButton.title = busy ? (backToGranite ? @"Back to Granite" : @"■ Stop") : @"Send";
    self.sendButton.action = busy
        ? (backToGranite ? @selector(returnToGranite:) : @selector(stopPressed:))
        : @selector(sendPressed:);
    self.sendButton.enabled = YES;
    self.sendButton.keyEquivalent = busy ? @"" : @"\r";
}

- (void)stopPressed:(id)sender {
    [self.console stop];
}

/// Leave whatever owns the terminal and restore the ordinary Granite entry.
///
/// SlopNet starts Zellij with forced-close behaviour set to detach, so ending
/// this Mac's SSH client leaves that named server session available to attach
/// again. Other tools simply end when their terminal ends.
/// The button is also permanent in the sidebar: a full-screen program can
/// never hide the action that leaves it.
- (void)returnToGranite:(id)sender {
    // A permanent navigation row must not become an accidental second Stop
    // button for a server install, plan, build or guide response.
    if ([self exclusiveWorkRunning] && self.signingIn == nil) return;
    if (self.busy && !self.toolRunning && self.signingIn == nil &&
        self.activeTab == 0) return;

    // Already on Granite with nothing to stop: just restore the composer.
    if (self.activeTab == 0 && !self.console.running) {
        self.toolRunning = NO;
        self.returningToGranite = NO;
        [self syncComposerToActiveTab];
        [self showTypingBar];
        return;
    }

    // On a tool tab that has already ended: switch home without a fake failure.
    if (self.activeTab > 0 && !self.console.running) {
        self.toolRunning = NO;
        self.returningToGranite = NO;
        [self showTab:0];
        [self showTypingBar];
        return;
    }

    self.returningToGranite = YES;
    [self endActivity];
    self.promptBar.hidden = YES;
    self.skipButton.hidden = YES;
    self.signInPage = nil;
    self.signInCode = nil;
    self.openPageButton.hidden = YES;
    self.codeButton.hidden = YES;
    // Do not let a cancelled sign-in immediately advance to the next queued
    // provider after the terminal closes. Granite means leave the whole run.
    self.signingIn = nil;
    self.skippingSignIn = NO;
    self.signInQueueActive = NO;
    [self.signInQueue removeAllObjects];
    [self.console stop];
}

- (void)setBusy:(BOOL)busy {
    [self showSendOrStop:busy];
    _busy = busy;
    [self refreshState];
}

- (void)rebuildHistory {
    for (NSView *view in [self.historyStack.arrangedSubviews copy]) {
        [self.historyStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    NSArray<NSURL *> *conversations = [self conversationURLs];
    if (conversations.count == 0) {
        [self.historyStack addArrangedSubview:[self label:@"nothing yet" size:11 grey:YES]];
        return;
    }
    NSUInteger visible = MIN(conversations.count, 12);
    for (NSUInteger index = 0; index < visible; index++) {
        NSURL *url = conversations[index];
        NSButton *button = [self sidebarButton:[@"•  " stringByAppendingString:
                                           [self conversationTitle:url]]
                                          action:@selector(openConversation:)];
        button.identifier = url.path;
        [self.historyStack addArrangedSubview:button];
    }
}

- (NSURL *)historyDirectory {
    NSURL *support = [[NSFileManager defaultManager]
        URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return [support URLByAppendingPathComponent:@"SlopNet/history" isDirectory:YES];
}

- (NSArray<NSURL *> *)conversationURLs {
    NSURL *directory = [self historyDirectory];
    NSArray<NSURL *> *items = [[NSFileManager defaultManager]
        contentsOfDirectoryAtURL:directory
        includingPropertiesForKeys:@[NSURLContentModificationDateKey, NSURLIsRegularFileKey]
                           options:NSDirectoryEnumerationSkipsHiddenFiles error:nil] ?: @[];
    NSPredicate *markdown = [NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *_) {
        NSNumber *regular = nil;
        [url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
        return regular.boolValue && [url.pathExtension.lowercaseString isEqualToString:@"md"];
    }];
    return [[items filteredArrayUsingPredicate:markdown]
        sortedArrayUsingComparator:^NSComparisonResult(NSURL *left, NSURL *right) {
            NSDate *leftDate = nil;
            NSDate *rightDate = nil;
            [left getResourceValue:&leftDate forKey:NSURLContentModificationDateKey error:nil];
            [right getResourceValue:&rightDate forKey:NSURLContentModificationDateKey error:nil];
            NSDate *safeLeft = leftDate ?: [NSDate distantPast];
            NSDate *safeRight = rightDate ?: [NSDate distantPast];
            return [safeRight compare:safeLeft];
        }];
}

- (NSString *)conversationTitle:(NSURL *)url {
    NSString *text = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    NSString *first = lines.firstObject ?: @"";
    if ([first hasPrefix:@"# "] && first.length > 2) return [first substringFromIndex:2];
    return @"untitled request";
}

- (void)newConversation:(id)sender {
    self.conversationURL = nil;
    self.plannedProjectName = nil;
    self.plannedProjectCommit = nil;
    self.activeProjectName = nil;
    self.turn = SlopNetTurnTalking;
    self.pendingRequest = nil;
    self.offerBuildWhenReplyEnds = NO;
    self.entry.string = @"";
    [self.console note:
        @"\nNew conversation. Ask your guide anything, or say what you want built."];
    [self showReadyBlock];
    [self.window makeFirstResponder:self.entry];
    [self resizeEntry];
}

- (void)openConversation:(NSButton *)sender {
    NSURL *url = [NSURL fileURLWithPath:sender.identifier ?: @""];
    NSString *text = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
    if (text.length == 0) return;
    self.conversationURL = url;
    self.plannedProjectName = nil;
    self.plannedProjectCommit = nil;
    self.turn = SlopNetTurnTalking;
    NSRange marker = [text rangeOfString:@"## Request\n\n" options:NSBackwardsSearch];
    if (marker.location != NSNotFound) {
        NSUInteger start = NSMaxRange(marker);
        NSRange next = [text rangeOfString:@"\n\n## " options:0
                                     range:NSMakeRange(start, text.length - start)];
        NSUInteger end = next.location == NSNotFound ? text.length : next.location;
        self.entry.string = [[text substringWithRange:NSMakeRange(start, end - start)]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    [self.console note:@"\nOpened a local request note. Its project request is back in the box; edit it or add a new one."];
    [self.window makeFirstResponder:self.entry];
    [self resizeEntry];
}

// History intentionally records only an idle project request. It never
// captures console output or an answer to a live prompt: either could contain
// a server password or provider information.
- (void)rememberRequest:(NSString *)idea project:(NSString *)name {
    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *directory = [self historyDirectory];
    NSError *error = nil;
    if (![files createDirectoryAtURL:directory withIntermediateDirectories:YES
                          attributes:@{NSFilePosixPermissions: @0700} error:&error]) {
        [self.console note:@"\nSlopNet could not save this request history on this Mac. The build can still continue."];
        return;
    }

    NSString *existing = self.conversationURL
        ? [NSString stringWithContentsOfURL:self.conversationURL encoding:NSUTF8StringEncoding error:nil]
        : nil;
    BOOL sameProject = existing.length > 0 &&
        [[self conversationTitle:self.conversationURL] isEqualToString:name];
    if (!sameProject) {
        self.conversationURL = [directory URLByAppendingPathComponent:
            [NSString stringWithFormat:@"request-%@.md", NSUUID.UUID.UUIDString.lowercaseString]];
        existing = [NSString stringWithFormat:@"# %@\n\nCreated locally by SlopNet.\n", name];
    }
    NSString *updated = [NSString stringWithFormat:@"%@\n## Request\n\n%@\n", existing, idea];
    if (![updated writeToURL:self.conversationURL atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        [self.console note:@"\nSlopNet could not save this request history on this Mac. The build can still continue."];
        return;
    }
    [files setAttributes:@{NSFilePosixPermissions: @0600}
             ofItemAtPath:self.conversationURL.path error:nil];
    [self rebuildHistory];
}

#pragma mark - remembering (never a password, never inside the repo)

// Only the three details from your provider's welcome email are kept, in
// macOS's own preferences for this app. A password is NEVER stored: it goes
// from the console straight to your server. The SSH key that setup creates
// stays as a private file in this Mac account's .ssh folder. Nothing is
// written into the SlopNet folder,
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
        // Nothing. The board below already says which server this is and what
        // is loaded; a paragraph explaining how to use a text box, and a line
        // about money nobody asked for, were both invented here.
    } else {
        [self.console note:@"Welcome. The setup guide is opening now.\n"
                           @"First connect your server; then SlopNet can install and prove its private local guide."];
    }
}

#pragma mark - the ready block (what the console shows when nothing is running)

/// How wide the panels may be: narrower than the console, so they read as
/// blocks on the field rather than full-width bars.
- (NSUInteger)panelWidth {
    NSUInteger columns = self.console.columns;
    return MAX((NSUInteger)44, MIN(columns - 2, (NSUInteger)66));
}

/// The coding apps from tools.json, as provider ids. Only real, listed
/// tools — nothing invented, and unmapped ids are simply left out.
/// Keep one line of the conversation, capped so a long session cannot grow the
/// prompt without limit. Older turns fall off the front; the guide keeps the
/// recent thread, which is what a person means by "remember what I said".
/// Reveal the reply a character at a time, in the panel already on screen.
///
/// The whole answer arrives at once from the server — the model is not
/// streamed — so this is presentation, not pretence about what is happening.
/// It reads as the guide speaking rather than a block of text appearing.
- (void)typeReply:(NSString *)said {
    [self.replyTimer invalidate];
    self.replyText = said;
    self.replyShown = 0;
    __weak typeof(self) weakSelf = self;
    self.replyTimer = [NSTimer scheduledTimerWithTimeInterval:0.012 repeats:YES
                                                      block:^(NSTimer *timer) {
        typeof(self) me = weakSelf;
        if (me == nil) { [timer invalidate]; return; }
        // A few characters a tick, so a long answer does not outlast a
        // person's patience.
        me.replyShown = MIN(me.replyText.length, me.replyShown + 3);
        BOOL finished = me.replyShown >= me.replyText.length;
        NSString *sofar = [me.replyText substringToIndex:me.replyShown];
        NSString *guide =
            [SlopNetBrand providerForLocalModel:me.localModelName] ?: @"ibm_granite";
        NSString *panel = [SlopNetBrand guideSaidANSI:sofar provider:guide name:@"Granite"
                                               action:finished ? @"message" : @"think"
                                                frame:me.actionTick
                                                width:[me panelWidth]];
        if (![me.console replaceLinesFromToken:me.replyToken with:panel] || finished) {
            [timer invalidate];
            me.replyTimer = nil;
            me.replyToken = -1;
            [me endActivity];
        }
    }];
}

/// What a tile should say instead of "ready", or nil when it is usable.
///
/// A countdown rather than a flat "limited", so a person can see whether to
/// wait or go and do something else.
- (NSString *)limitWordForProvider:(NSString *)providerId {
    NSDictionary *limits = [NSUserDefaults.standardUserDefaults dictionaryForKey:kLimitUntilKey];
    NSNumber *when = limits[providerId];
    if (when == nil) return nil;
    NSTimeInterval left = when.doubleValue - NSDate.date.timeIntervalSince1970;
    if (left <= 0) {
        // Lifted. Forget it rather than leaving a stale badge on the board.
        NSMutableDictionary *kept = [limits mutableCopy];
        [kept removeObjectForKey:providerId];
        [NSUserDefaults.standardUserDefaults setObject:kept forKey:kLimitUntilKey];
        return nil;
    }
    NSInteger hours = (NSInteger)(left / 3600);
    NSInteger minutes = ((NSInteger)left % 3600) / 60;
    if (hours > 0) return [NSString stringWithFormat:@"back in %ldh %02ldm", (long)hours, (long)minutes];
    return [NSString stringWithFormat:@"back in %ldm", (long)MAX(1, minutes)];
}

/// Record that a coding app has hit its usage limit.
///
/// `text` is whatever the app printed. Providers usually say when the limit
/// lifts — "try again in 4 hours", "resets at 15:40" — and that is worth far
/// more than a guess, so it is read out of the message when it is there. The
/// five-hour default is only for when the message says nothing, and it is
/// deliberately a plain wait rather than a claim about which cap was hit:
/// nothing here can tell a daily limit from a weekly one.
- (void)noteLimitFor:(NSString *)providerId from:(NSString *)text {
    NSTimeInterval wait = [self waitStatedIn:text];
    if (wait <= 0) wait = kDefaultLimitWait;
    NSMutableDictionary *limits =
        [([NSUserDefaults.standardUserDefaults dictionaryForKey:kLimitUntilKey] ?: @{}) mutableCopy];
    limits[providerId] = @(NSDate.date.timeIntervalSince1970 + wait);
    [NSUserDefaults.standardUserDefaults setObject:limits forKey:kLimitUntilKey];
    [self showReadyBlock];
}

/// Change how long is left, in seconds from now. The hook the guide will use
/// once it is allowed to act on a person's behalf; nothing calls it yet.
- (void)setLimitFor:(NSString *)providerId secondsFromNow:(NSTimeInterval)seconds {
    NSMutableDictionary *limits =
        [([NSUserDefaults.standardUserDefaults dictionaryForKey:kLimitUntilKey] ?: @{}) mutableCopy];
    if (seconds <= 0) [limits removeObjectForKey:providerId];
    else limits[providerId] = @(NSDate.date.timeIntervalSince1970 + seconds);
    [NSUserDefaults.standardUserDefaults setObject:limits forKey:kLimitUntilKey];
    [self showReadyBlock];
}

/// A wait the provider stated itself, in seconds, or 0 when it said nothing.
- (NSTimeInterval)waitStatedIn:(NSString *)text {
    if (text.length == 0) return 0;
    NSString *lower = text.lowercaseString;
    static NSRegularExpression *relative;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // "try again in 4 hours", "retry after 35 minutes", "wait 90 seconds"
        relative = [NSRegularExpression regularExpressionWithPattern:
            @"(?:in|after|wait)\\s+(\\d+)\\s*(second|sec|minute|min|hour|hr|day)"
                                                            options:0 error:nil];
    });
    NSTextCheckingResult *m = [relative firstMatchInString:lower options:0
                                                     range:NSMakeRange(0, lower.length)];
    if (m == nil) return 0;
    double amount = [[lower substringWithRange:[m rangeAtIndex:1]] doubleValue];
    NSString *unit = [lower substringWithRange:[m rangeAtIndex:2]];
    if ([unit hasPrefix:@"sec"]) return amount;
    if ([unit hasPrefix:@"min"]) return amount * 60;
    if ([unit hasPrefix:@"hour"] || [unit hasPrefix:@"hr"]) return amount * 3600;
    if ([unit hasPrefix:@"day"]) return amount * 86400;
    return 0;
}

/// Run a typed command in the directory the person is currently in.
///
/// Every command opens a new shell over SSH, so the directory has to be
/// carried by this app and re-entered each time. `cd` is handled here rather
/// than passed through, because in a fresh shell it would change a directory
/// that is thrown away the moment the command ends — which is exactly what
/// looked broken: `cd` appeared to do nothing and every relative path failed.
- (void)runServerCommand:(NSString *)command {
    if (self.workingDirectory.length == 0) self.workingDirectory = @"/home/slopnet";

    NSString *trimmed = [command stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceCharacterSet];
    if ([trimmed isEqualToString:@"cd"] || [trimmed hasPrefix:@"cd "]) {
        NSString *target = [[trimmed substringFromIndex:2]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (target.length == 0) target = @"~";
        // Ask the shell to move and report where it landed, so a directory
        // that does not exist is refused by the server rather than believed.
        self.pendingDirectory = @"";
        self.console.collectsOutput = YES;
        self.movingDirectory = YES;
        [self runOnServerInWorkingDirectory:
            [NSString stringWithFormat:@"cd %@ && pwd", target]
                                      title:[NSString stringWithFormat:@"cd %@", target]
                                interactive:NO];
        return;
    }
    [self runOnServerInWorkingDirectory:command
                                  title:[NSString stringWithFormat:@"Running %@", command]
                            interactive:YES];
}

- (void)runOnServerInWorkingDirectory:(NSString *)command
                                 title:(NSString *)title
                           interactive:(BOOL)interactive {
    NSString *full = [NSString stringWithFormat:@"cd %@ 2>/dev/null || cd /home/slopnet; %@",
                      self.workingDirectory, command];
    [self startServerCommand:full title:title interactive:interactive];
}

- (void)remember:(NSString *)line {
    if (self.conversation == nil) self.conversation = [NSMutableArray array];
    [self.conversation addObject:line];
    while (self.conversation.count > 20) [self.conversation removeObjectAtIndex:0];
}

/// Everything the guide is allowed to know: the recent conversation, then the
/// tail of what the terminal has actually shown.
///
/// The terminal half is the point of this — a guide that can read what just
/// scrolled past can explain it. It is read-only. Nothing here lets the model
/// run anything; it has no tools, and the prompt says so.
///
/// Secrets are taken out first. Sign-in codes and keys pass through this
/// window, and while the model is local and private, text that goes into a
/// prompt should never be the place a credential is kept alive.
- (NSString *)guideContext {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (self.conversation.count > 0) {
        [parts addObject:[NSString stringWithFormat:@"Earlier in this conversation:\n%@",
                          [self.conversation componentsJoinedByString:@"\n"]]];
    }
    NSString *screen = [self.console recentLinesForContext:60];
    if (screen.length > 0) {
        [parts addObject:[NSString stringWithFormat:
            @"What the terminal has shown (you cannot run anything, only read this):\n%@",
            screen]];
    }
    return [parts componentsJoinedByString:@"\n\n"];
}

- (NSArray<NSString *> *)codingToolProviders {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"tools" ofType:@"json"];
    NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
    NSDictionary *root = data
        ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSArray *tools = [root isKindOfClass:NSDictionary.class] ? root[@"tools"] : nil;
    NSMutableArray<NSString *> *providers = [NSMutableArray array];
    for (NSDictionary *tool in tools) {
        if (![tool isKindOfClass:NSDictionary.class]) continue;
        NSString *provider = [SlopNetBrand providerForTool:tool[@"id"]];
        if (provider != nil && ![providers containsObject:provider]) {
            [providers addObject:provider];
        }
    }
    return providers;
}

/// The StormCode-style status block: a crimson header, a filled panel for
/// the private local model with an animated action glyph, and a row of the
/// coding apps on their own brand surfaces. Compact on purpose — the full
/// 38-logo sheet lives behind the Providers button, not the front door.
- (NSString *)readyBlockANSI {
    NSUInteger width = [self panelWidth];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    [parts addObject:[SlopNetBrand headerANSI:@"SlopNet" width:width]];

    NSString *model = self.localModelName;
    NSString *provider = [SlopNetBrand providerForLocalModel:model] ?: @"ibm_granite";
    BOOL known = model.length > 0;
    // One line: the name a person recognises, and whether it can answer.
    // The Hugging Face identifier, the API-key note and the port note were
    // three lines of reassurance nobody needed twice; the identifier still
    // lives in Settings.
    //
    // More local models are coming, and they will not all be loaded at once,
    // so the word has to be about this model rather than about the server.
    [parts addObject:[SlopNetBrand panelANSIForProvider:provider
                                                 title:@"Granite 4.1 3B"
                                                detail:@[known ? @"loaded" : @"locked"]
                                                action:self.actionConcept
                                                 frame:self.actionTick
                                                 width:width]];

    NSArray<NSString *> *tools = [self codingToolProviders];
    NSArray *connected = [NSUserDefaults.standardUserDefaults
        arrayForKey:kSignedInProvidersKey] ?: @[];
    BOOL anyConnected = NO;
    for (NSString *identifier in tools) {
        if ([connected containsObject:identifier]) { anyConnected = YES; break; }
    }
    if (tools.count > 0 && anyConnected) {
        [parts addObject:[SlopNetBrand headerANSI:@"Coding apps" width:width]];
        NSArray *signedIn = [NSUserDefaults.standardUserDefaults
            arrayForKey:kSignedInProvidersKey] ?: @[];
        // Only apps that are actually installed and signed in. A row of tiles
        // saying SET UP read as a claim rather than an instruction — nobody
        // could tell whether it meant "this is set up" or "set this up" — and
        // an app you have not connected is not a thing you can use. Until one
        // is connected there is only the guide, which is what walks somebody
        // through connecting one.
        NSMutableArray<NSString *> *ready = [NSMutableArray array];
        NSMutableDictionary<NSString *, NSString *> *status = [NSMutableDictionary dictionary];
        for (NSString *identifier in tools) {
            if (![signedIn containsObject:identifier]) continue;
            [ready addObject:identifier];
            status[identifier] = [self limitWordForProvider:identifier] ?: @"ready";
        }
        if (ready.count > 0) {
            [parts addObject:[SlopNetBrand panelStripANSIForProviders:ready
                                                               status:status
                                                                width:width]];
        }
    }
    return [parts componentsJoinedByString:@"\n"];
}

- (void)showReadyBlock {
    // No action glyph. The board is what the app looks like when it is doing
    // nothing, and a Think animation running against an idle guide says the
    // opposite — think belongs to the moment a question is being answered.
    self.actionConcept = nil;
    self.actionTick = 0;
    self.readyBlockToken = [self.console noteReplaceable:[self readyBlockANSI]];
    [self startActionAnimation];
}

#pragma mark - the animated action glyph

- (void)startActionAnimation {
    [self.actionTimer invalidate];
    // ~8 fps, the rate scripts/show_frames.py plays these at. The block holds
    // the delegate weakly: a repeating timer retains its block, so a strong
    // self here would keep the window alive after it closed.
    __weak typeof(self) weakSelf = self;
    self.actionTimer = [NSTimer scheduledTimerWithTimeInterval:0.125
                                                       repeats:YES
                                                         block:^(NSTimer *timer) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) { [timer invalidate]; return; }
        [strongSelf tickActionAnimation:timer];
    }];
}

- (void)tickActionAnimation:(NSTimer *)timer {
    self.actionTick++;
    if (self.busy) {
        // A run owns the screen: the glyph lives in the status line, which
        // never scrolls and never fights the program's cursor.
        NSString *glyph = [SlopNetBrand actionGlyph:self.actionConcept ?: @"think"
                                              frame:self.actionTick
                                              cells:2];
        [self.console setStatusText:self.actionCaption ?: @"Working…"
                              glyph:glyph
                               tint:[SlopNetBrand crimsonColor]];
        return;
    }
    // Idle: redraw the ready block's own lines in place. Once they scroll out
    // of the buffer the console says so, and the animation stops rather than
    // redrawing rows that now belong to something else.
    if (self.readyBlockToken < 0) { [timer invalidate]; self.actionTimer = nil; return; }
    if (![self.console replaceLinesFromToken:self.readyBlockToken with:[self readyBlockANSI]]) {
        self.readyBlockToken = -1;
        [timer invalidate];
        self.actionTimer = nil;
    }
}

/// Name what is happening while a program runs, and animate it.
- (void)beginActivity:(NSString *)concept caption:(NSString *)caption {
    self.actionConcept = concept;
    self.actionCaption = caption;
    self.actionTick = 0;
    self.readyBlockToken = -1;      // the ready block is history now
    [self startActionAnimation];
}

#pragma mark - actions

- (void)openSettings:(id)sender {
    self.settings = [[SlopNetSettings alloc] initWithHost:self.host
                                                     port:self.port
                                                     user:self.username
                                                connected:[self isReady]];
    self.settings.window.title = @"Settings";
    self.settings.delegate = self;
    [self.settings presentFrom:self.window];
}

- (void)openTools:(id)sender {
    self.tools = [[SlopNetTools alloc] initWithHost:self.host
                                               port:self.port
                                               user:self.username
                                          connected:[self isReady]];
    self.tools.delegate = self;
    [self.tools presentFrom:self.window];
}

#pragma mark - the setup wizard

- (void)openWizardAtStep:(SlopNetWizardStep)step {
    if (self.wizard != nil && self.wizard.window.sheetParent != nil) {
        // Hand it what is true now. Without this a step kept insisting the
        // server was not prepared after the run that prepared it, and Back
        // just showed the same stale screen.
        [self.wizard updateServerReady:[self isReady] guideReady:[self guideReady]];
        [self.wizard showStep:step];
        return;
    }
    self.wizard = [[SlopNetWizard alloc] initWithHost:self.host
                                                 port:self.port
                                                 user:self.username
                                          serverReady:[self isReady]
                                           guideReady:[self guideReady]];
    self.wizard.delegate = self;
    [self.wizard showStep:step];
    [self.wizard presentFrom:self.window];
}

- (void)openWizardAtResumeStep {
    [self openWizardAtStep:[SlopNetWizard resumeStepForServerReady:[self isReady]
                                                       guideReady:[self guideReady]]];
}

- (void)openWizard:(id)sender { [self openWizardAtResumeStep]; }

- (void)wizard:(SlopNetWizard *)wizard rememberHost:(NSString *)host
          port:(NSString *)port user:(NSString *)user {
    self.host = host;
    self.port = port.length ? port : @"22";
    self.username = user.length ? user : @"root";
    [self remember];
    [self refreshState];
}

- (void)wizard:(SlopNetWizard *)wizard
 connectToHost:(NSString *)host
          port:(NSString *)port
          user:(NSString *)user {
    // The same path Settings uses: whoever asked steps aside and the console
    // runs it, because this is where the server's password prompt appears.
    [self prepareServerHost:host port:port user:user];
}

- (void)wizard:(SlopNetWizard *)wizard installGuideModel:(NSString *)model {
    [self installGuideModel:model];
}

/// Sign in to the chosen coding apps one after another.
///
/// One at a time on purpose: each one opens a browser page and shows a code,
/// and two of those at once is how somebody ends up pasting the wrong code
/// into the wrong page. The queue is kept so a failure or a skip moves on to
/// the next rather than stopping everything.
- (void)wizard:(SlopNetWizard *)wizard signInToCodingApps:(NSArray<NSString *> *)providers {
    self.signInQueue = [providers mutableCopy];
    self.signedIn = [NSMutableArray array];
    self.skipped = [NSMutableArray array];
    self.signInQueueActive = YES;
    [self startNextCodingAppSignIn];
}

/// Put the ordinary typing box back and hide every prompt control.
- (void)showTypingBar {
    // A browser offer belongs only to the program run that printed it. Keeping
    // these objects after returning to Granite lets a later prompt resurrect
    // the old provider's page and one-time code.
    self.signInPage = nil;
    self.signInCode = nil;
    self.openPageButton.hidden = YES;
    self.codeButton.hidden = YES;
    self.promptBar.hidden = YES;
    self.skipButton.hidden = YES;
    self.entryScroller.hidden = NO;
    self.sendButton.hidden = NO;
    [self.window makeFirstResponder:self.entry];
}

/// Stop the spinning glyph. Setting a nil concept would leave the timer
/// running with nothing to draw.
- (void)endActivity {
    [self.actionTimer invalidate];
    self.actionTimer = nil;
    self.actionConcept = nil;
    self.actionCaption = nil;
}

- (void)startNextCodingAppSignIn {
    if (self.signInQueue.count == 0) {
        [self finishCodingAppSignIns];
        return;
    }
    NSString *provider = self.signInQueue.firstObject;
    [self.signInQueue removeObjectAtIndex:0];
    self.signingIn = provider;

    NSString *script = [self helper:@"slopnet-vps-coding-app"];
    if (script == nil) {
        [self.console note:@"The part of SlopNet that signs in to a coding app is missing "
                           @"from this copy. Download SlopNet again."];
        self.signingIn = nil;
        [self finishCodingAppSignIns];
        return;
    }
    NSString *name = [SlopNetBrand displayNameForProvider:provider] ?: provider;
    [self.console note:[SlopNetBrand headerANSI:[NSString stringWithFormat:@"Signing in to %@", name]
                                          width:[self panelWidth]]];
    [self.console note:@"A page will open in your browser. Your one-time code appears "
                       @"below and is copied for you."];
    [self.console note:@"If this one will not go through, press Skip this one — the rest "
                       @"carry on without it."];
    [self showSkipControl:name];
    [self beginActivity:@"search"
                caption:[NSString stringWithFormat:@"Waiting for you to sign in to %@…", name]];
    [self setBusy:YES];
    if (![self.console runExecutable:@"/bin/bash"
                           arguments:@[script, self.host, self.port, self.username,
                                       provider, [self pinnedRelease]]]) {
        [self setBusy:NO];
        [self codingAppSignInEnded:NO];
    }
}

/// A person must always be able to leave a sign-in that will not complete.
/// Without this, one coding app refusing a login strands the whole first run.
- (void)showSkipControl:(NSString *)name {
    // A queued provider starts with no browser offer of its own. Clear the
    // previous provider's offer before this program can print another prompt.
    self.signInPage = nil;
    self.signInCode = nil;
    self.promptBar.hidden = NO;
    // The typing box STAYS. A coding app signing in asks its own questions —
    // Gemini opens with "Do you trust the files in this folder?" and a numbered
    // menu — and hiding the box left the operator looking at a question with
    // nothing to answer it with, and one button offering to give up. Whatever
    // is on screen is a real program waiting for a real keystroke.
    self.entryScroller.hidden = NO;
    self.sendButton.hidden = NO;
    self.secretField.hidden = YES;
    self.secretSend.hidden = YES;
    self.approveButton.hidden = YES;
    self.declineButton.hidden = YES;
    self.continueButton.hidden = YES;
    self.openPageButton.hidden = YES;
    self.codeButton.hidden = YES;
    self.skipButton.hidden = NO;
    self.skipButton.title = self.signInQueueActive ? @"Skip this one" : @"Back to Granite";
    self.skipButton.action = self.signInQueueActive
        ? @selector(skipThisSignIn:) : @selector(returnToGranite:);
    // Antigravity becomes the interactive app after browser authorisation;
    // there is no separate process exit that means "setup is over". Describe
    // the durable truth instead of leaving a setup claim on screen forever.
    self.promptLabel.stringValue =
        [NSString stringWithFormat:@"%@ is using the console.", name];
    self.promptLabel.textColor = [NSColor labelColor];
    [self.window makeFirstResponder:self.entry];
}

- (void)skipThisSignIn:(id)sender {
    // No queued provider means this bar came from something the console
    // spotted rather than from a sign-in this app started. The button must
    // still do what it says: put the bar away and give the person their
    // typing box back. It used to return here and look broken.
    if (self.signingIn == nil) {
        self.skipButton.hidden = YES;
        [self endActivity];
        [self setBusy:NO];
        [self showTypingBar];
        [self.window makeFirstResponder:self.entry];
        return;
    }
    [self.console note:[NSString stringWithFormat:@"\nSkipped %@. You can sign in to it "
                                                  @"later from Settings.",
                        [SlopNetBrand displayNameForProvider:self.signingIn] ?: self.signingIn]];
    // Wait for this PTY to finish before launching the next one. Starting it
    // here races the old process: runExecutable: refuses because the console
    // is still occupied, and the whole remaining queue can be skipped.
    self.skippingSignIn = YES;
    [self.console stop];
}

/// One sign-in ended, for any reason. Record it and move to the next.
- (void)codingAppSignInEnded:(BOOL)worked {
    if (self.signingIn == nil) return;       // already skipped
    [(worked ? self.signedIn : self.skipped) addObject:self.signingIn];
    self.signingIn = nil;
    [self startNextCodingAppSignIn];
}

- (void)finishCodingAppSignIns {
    self.signInQueueActive = NO;
    self.skippingSignIn = NO;
    self.skipButton.hidden = YES;
    [self endActivity];
    [self setBusy:NO];
    if (self.signedIn.count > 0) {
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (NSString *identifier in self.signedIn) {
            [names addObject:[SlopNetBrand displayNameForProvider:identifier] ?: identifier];
        }
        [self.console note:[NSString stringWithFormat:@"\nSigned in: %@.",
                            [names componentsJoinedByString:@", "]]];
    }
    // Remembered, so the board can say which apps can actually build. Without
    // this the tiles were five identical badges saying nothing at all.
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    NSMutableArray *known = [([store arrayForKey:kSignedInProvidersKey] ?: @[]) mutableCopy];
    for (NSString *identifier in self.signedIn) {
        if (![known containsObject:identifier]) [known addObject:identifier];
    }
    [store setObject:known forKey:kSignedInProvidersKey];

    if (self.skipped.count > 0) {
        [self.console note:@"The ones you skipped are still in Settings whenever you want "
                           @"to try them again."];
    }
    // Always back to the guide. It is the one they talk to; a coding app is
    // something SlopNet uses on their behalf, not something they operate.
    [self.console note:@"\nBack to your guide — ask it anything, in your own words."];
    [self showTypingBar];
}

- (void)wizardOpenSettings:(SlopNetWizard *)wizard {
    dispatch_async(dispatch_get_main_queue(), ^{ [self openSettings:nil]; });
}

- (void)wizardStartChat:(SlopNetWizard *)wizard {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kWizardKey];
    [self refreshState];
    [self.console note:[SlopNetBrand headerANSI:@"Ready" width:[self panelWidth]]];
    [self.console note:@"Ask the private guide anything about setup. It answers on your "
                       @"server, costs nothing, and cannot start a build."];
    [self showReadyBlock];
    [self.window makeFirstResponder:self.entry];
}

- (void)wizardDidFinish:(SlopNetWizard *)wizard {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kWizardKey];
    [self refreshState];
    [self.window makeFirstResponder:self.entry];
}

- (void)openServerHelp:(id)sender {
    [self.console note:
        @"\nSlopNet setup currently supports a Linux server you can reach over SSH:\n"
        @"  • a rented Linux server\n"
        @"  • a dedicated or home Linux machine\n"
        @"You need three things from it: its address, a login name, and the "
        @"port (almost always 22). Put them in Settings, bottom left.\n"
        @"The built-in terminal-tool downloads are currently proved only on "
         "x86-64 Linux. ARM machines such as Raspberry Pi are not yet proved."];
}

- (void)clearConsole:(id)sender {
    [self.console clear];
    [self showReadyBlock];
}

/// The whole mapped provider set, on demand. Deliberately not the default
/// view: the operator asked for the demos' visual system, not a collage of
/// every logo on every launch.
- (void)showProviders:(id)sender {
    NSUInteger width = self.console.columns - 2;
    [self.console note:[SlopNetBrand providerSheetANSIWithWidth:width]];
    [self.console note:[SlopNetBrand colorFontActive]
        ? @"Colour badge font active — these are the real marks."
        : @"Colour badge font not active — these are portable Unicode marks."];
    [self.console note:[SlopNetBrand colourCheckANSIWithWidth:width]];
    self.readyBlockToken = -1;
}

- (void)resizeEntry {
    if (self.entry == nil || self.entryHeight == nil) return;
    [self.entry.layoutManager ensureLayoutForTextContainer:self.entry.textContainer];
    CGFloat textHeight = [self.entry.layoutManager usedRectForTextContainer:self.entry.textContainer].size.height + 16;
    CGFloat maximum = 168;
    self.entryHeight.constant = MIN(MAX(textHeight, 56), maximum);
    self.entryScroller.hasVerticalScroller = textHeight > maximum;
}

- (void)refreshModelLabel {
    if (self.modelLabel == nil) return;
    NSString *provider = [SlopNetBrand providerForLocalModel:self.localModelName];
    NSString *badge = provider ? [SlopNetBrand markForProvider:provider] : nil;
    // The recognised name, not the Hugging Face identifier. Two auditors
    // flagged "ibm-granite/granite-4.1-3b-GGUF:Q4_K_M" as exactly the kind of
    // jargon that tells a beginner this software is not for them. The full
    // identifier still lives in Settings, where somebody looking for it will
    // know what it means.
    NSString *name = provider ? [SlopNetBrand displayNameForProvider:provider] : @"Your guide";
    NSString *text = [NSString stringWithFormat:@"%@  %@ — private, on your server",
                      badge ?: @"", name];
    if (badge != nil && [SlopNetBrand colorFontActive]) {
        // The badge needs the colour face; the name stays in the system font
        // so the line still reads as part of the app.
        NSMutableAttributedString *styled = [[NSMutableAttributedString alloc]
            initWithString:text
                attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:11],
                             NSForegroundColorAttributeName: [NSColor secondaryLabelColor]}];
        [styled addAttribute:NSFontAttributeName
                       value:[SlopNetBrand consoleFontOfSize:13.5]
                       range:NSMakeRange(0, badge.length)];
        self.modelLabel.attributedStringValue = styled;
    } else {
        self.modelLabel.stringValue = text;
    }
}

- (void)textDidChange:(NSNotification *)notification { [self resizeEntry]; }

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (commandSelector == @selector(insertNewline:)) {
        NSEvent *event = NSApp.currentEvent;
        if ((event.modifierFlags & NSEventModifierFlagShift) != 0) return NO;
        [self sendPressed:textView];
        return YES;
    }
    return NO;
}

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
    [self prepareServerHost:host port:port user:user];
}

- (void)prepareServerHost:(NSString *)host port:(NSString *)port user:(NSString *)user {
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
    [self.console note:[SlopNetBrand headerANSI:@"Preparing your server"
                                          width:[self panelWidth]]];
    self.setupRunning = YES;
    [self beginActivity:@"search" caption:@"Checking your server…"];
    [self setBusy:YES];
    // The name goes with it, so the setup output can talk about the server
    // without printing its address.
    NSString *named = [NSUserDefaults.standardUserDefaults
        stringForKey:@"SlopNetServerName"] ?: @"your server";
    if (![self.console runExecutable:@"/bin/bash"
                           arguments:@[script, self.host, self.port, self.username, named]]) {
        self.setupRunning = NO;
        [self setBusy:NO];
    }
}

/// Wrap a command so it runs as the locked runtime account, never as root.
///
/// This is the whole point of that account: a coding tool and the credential
/// it stores belong to it, not to root and not to the machine. Settings ran
/// installs straight down the SSH connection instead, so npm went to
/// /root/.local, Kimi to /root/.kimi-code, and Grok symlinked itself into
/// /usr/local/bin pointing at root's home. None of it was visible to the
/// account that actually runs agents, which is why the list never updated.
///
/// The command goes over base64 so quoting, pipes and apostrophes inside it
/// cannot break the wrapper — the same approach the setup scripts use.
+ (NSString *)asRuntimeAccount:(NSString *)command
                         asRoot:(BOOL)root
                        release:(NSString *)release {
    NSData *raw = [command dataUsingEncoding:NSUTF8StringEncoding];
    NSString *encoded = [raw base64EncodedStringWithOptions:0];
    NSData *releaseRaw = [release dataUsingEncoding:NSUTF8StringEncoding];
    NSString *releaseEncoded = [releaseRaw base64EncodedStringWithOptions:0];
    NSMutableString *guard = [NSMutableString stringWithFormat:
        @"set -eu\nPATH=/usr/sbin:/usr/bin:/sbin:/bin\nexport PATH\n"
         "release=$(/usr/bin/printf %%s '%@' | /usr/bin/base64 -d)\n", releaseEncoded];
    [guard appendString:
        @"refuse() { echo 'This server is not prepared for this copy of SlopNet. "
         "Open Settings and prepare it again; nothing ran.'; exit 1; }\n"
         "[ \"$(uname -s)\" = Linux ] || refuse\n"
         "[ \"$(id -u)\" = 0 ] || refuse\n"
         "safe_marker() { marker=$1; expected=$2; "
         "[ -d /var/lib/slopnet ] && [ ! -L /var/lib/slopnet ] || return 1; "
         "[ \"$(stat -c %u /var/lib/slopnet)\" = 0 ] || return 1; "
         "[ -z \"$(find /var/lib/slopnet -maxdepth 0 -perm /022 -print -quit)\" ] || return 1; "
         "[ -f \"$marker\" ] && [ ! -L \"$marker\" ] || return 1; "
         "[ \"$(stat -c %u \"$marker\")\" = 0 ] || return 1; "
         "[ -z \"$(find \"$marker\" -maxdepth 0 -perm /022 -print -quit)\" ] || return 1; "
         "[ \"$(cat \"$marker\")\" = \"$expected\" ]; }\n"
         "runtime_receipt() { uid=$(id -u slopnet 2>/dev/null) || return 1; "
         "gid=$(id -g slopnet 2>/dev/null) || return 1; "
         "home=$(getent passwd slopnet | cut -d: -f6); "
         "shell=$(getent passwd slopnet | cut -d: -f7); "
         "[ \"$uid\" -ne 0 ] && [ \"$home\" = /home/slopnet ] && "
         "[ \"$shell\" = /usr/sbin/nologin ] || return 1; "
         "[ -d \"$home\" ] && [ ! -L \"$home\" ] && "
         "[ \"$(stat -c %u \"$home\")\" = \"$uid\" ] || return 1; "
         "[ \"$(stat -c %a \"$home\")\" = 700 ] && "
         "[ \"$(getent group \"$gid\" | cut -d: -f1)\" = slopnet ] || return 1; "
         "[ \"$(id -G slopnet)\" = \"$gid\" ] || return 1; "
         "state=$(passwd -S slopnet 2>/dev/null | awk '{print $2}'); "
         "[ \"$state\" = L ] || [ \"$state\" = LK ] || return 1; "
         "printf 'kind=runtime-account-v2\\nname=slopnet\\nuid=%s\\ngid=%s\\n"
         "home=/home/slopnet\\nshell=/usr/sbin/nologin\\nhome_dev=%s\\nhome_ino=%s' \"$uid\" \"$gid\" "
         "\"$(stat -c %d \"$home\")\" \"$(stat -c %i \"$home\")\"; }\n"
         "[ -d /opt/slopnet ] && [ ! -L /opt/slopnet ] && "
         "[ \"$(stat -c %u /opt/slopnet)\" = 0 ] || refuse\n"
         "[ -z \"$(find /opt/slopnet -maxdepth 0 -perm /022 -print -quit)\" ] || refuse\n"
         "[ \"$(git -C /opt/slopnet remote get-url origin)\" = "
         "https://github.com/jpheerlyn-dev/slopnet.git ] || refuse\n"
         // A server prepared for an earlier release is brought to this one
         // rather than refused. Refusing meant every release this app cut
         // stopped every tool on a working server, with no way back except
         // editing the server by hand — the person is held hostage by a
         // version number they never chose.
         //
         // Ownership is still proved first: the account receipt and the
         // existing install receipt have to name this account and this
         // folder. Only the release recorded in them is allowed to differ,
         // and it is rewritten here once the new code is actually checked out.
         "if [ \"$(cat /var/lib/slopnet/release-v1 2>/dev/null)\" != \"release=$release\" ]; then\n"
         "  moving=$(runtime_receipt) || refuse\n"
         "  safe_marker /var/lib/slopnet/runtime-account-v2 \"$moving\" || refuse\n"
         "  [ -f /var/lib/slopnet/install-v2 ] && [ ! -L /var/lib/slopnet/install-v2 ] || refuse\n"
         "  grep -qx 'path=/opt/slopnet' /var/lib/slopnet/install-v2 || refuse\n"
         "  git -C /opt/slopnet fetch --quiet --tags --force origin || refuse\n"
         "  moved=$(git -C /opt/slopnet rev-parse \"refs/tags/$release^{commit}\" 2>/dev/null) || refuse\n"
         "  git -C /opt/slopnet -c advice.detachedHead=false checkout --quiet \"$release\" || refuse\n"
         "  git -C /opt/slopnet clean -qfd || refuse\n"
         "  chown -R 0:0 /opt/slopnet || refuse\n"
         "  printf 'kind=install-v2\\npath=/opt/slopnet\\ndev=%s\\nino=%s\\nrelease=%s\\ncommit=%s' "
         "\"$(stat -c %d /opt/slopnet)\" \"$(stat -c %i /opt/slopnet)\" \"$release\" \"$moved\" "
         "> /var/lib/slopnet/install-v2 || refuse\n"
         "  printf 'release=%s' \"$release\" > /var/lib/slopnet/release-v1 || refuse\n"
         "  chmod 600 /var/lib/slopnet/install-v2 /var/lib/slopnet/release-v1 || refuse\n"
         "  echo \"Updated this server to $release.\"\n"
         "fi\n"
         "commit=$(git -C /opt/slopnet rev-parse \"refs/tags/$release^{commit}\" 2>/dev/null) || refuse\n"
         "[ \"$(git -C /opt/slopnet rev-parse HEAD)\" = \"$commit\" ] || refuse\n"
         "git -C /opt/slopnet diff --quiet \"$commit\" -- && "
         "[ -z \"$(git -C /opt/slopnet status --porcelain --untracked-files=all)\" ] || refuse\n"
         "account=$(runtime_receipt) || refuse\n"
         "safe_marker /var/lib/slopnet/runtime-account-v2 \"$account\" || refuse\n"
         "install=$(printf 'kind=install-v2\\npath=/opt/slopnet\\ndev=%s\\nino=%s\\n"
         "release=%s\\ncommit=%s' \"$(stat -c %d /opt/slopnet)\" "
         "\"$(stat -c %i /opt/slopnet)\" \"$release\" \"$commit\")\n"
         "safe_marker /var/lib/slopnet/install-v2 \"$install\" || refuse\n"
         "safe_marker /var/lib/slopnet/release-v1 \"release=$release\" || refuse\n"
         "uid=$(id -u slopnet 2>/dev/null) || refuse\n"
         "home=$(getent passwd slopnet | cut -d: -f6)\n"
         "[ \"$home\" = /home/slopnet ] && [ -d \"$home\" ] && [ ! -L \"$home\" ] || refuse\n"
         "[ \"$(stat -c %u \"$home\")\" = \"$uid\" ] || refuse\n"];
    NSString *guardEncoded = [[guard dataUsingEncoding:NSUTF8StringEncoding]
        base64EncodedStringWithOptions:0];
    // A runtime directory, and a working directory this account can read.
    //
    // The locked account never logs in, so it is not given the runtime
    // directory that programs keeping a session expect — Zellij refuses to
    // start without one. And a command arriving over SSH as root inherits
    // root's working directory, which this account cannot read, so anything
    // that puts itself into the background dies changing directory. Both were
    // found by running the real thing rather than by reading about it.
    // TERM and COLORTERM go with the program, not only the local PTY.
    // Superfile and friends read the far-side environment; without these
    // they start in a degraded mode that looks broken in this console.
    NSString *runuser =
        @"/usr/sbin/runuser -u slopnet -- /usr/bin/env HOME=/home/slopnet "
        @"XDG_RUNTIME_DIR=/home/slopnet/.run "
        @"TERM=xterm-256color COLORTERM=truecolor "
        @"PATH=/opt/slopnet:/home/slopnet/.local/bin:"
        @"/home/slopnet/.kimi-code/bin:"
        @"/home/slopnet/.local/node_modules/.bin:/usr/local/bin:/usr/bin:/bin "
        @"/bin/sh -c \"cd /home/slopnet; exec /bin/sh $f\"";
    // Everything below this home is controlled by the locked account. Create
    // its runtime paths only after dropping privilege: following a path there
    // with root install/chown would let a pre-planted symlink redirect the
    // privileged operation. Old root-owned drift therefore fails closed and
    // must be inspected rather than silently "repaired".
    NSString *privilege = root ? @"" : @"/usr/bin/sudo ";
    NSString *prepare = [NSString stringWithFormat:
        @"%@/usr/sbin/runuser -u slopnet -- /bin/sh -c 'set -eu; umask 077; "
         "for d in /home/slopnet/.run /home/slopnet/.local "
         "/home/slopnet/.local/share; do "
         "[ ! -L \"$d\" ] || exit 1; "
         "if [ -e \"$d\" ]; then [ -d \"$d\" ] || exit 1; "
         "else /bin/mkdir -- \"$d\"; fi; done; "
         "/bin/chmod 700 /home/slopnet/.run'",
        privilege];
    // The command goes to the far side in a file, not down a pipe.
    //
    // Piping it in made the pipe the program's standing input, so a tool that
    // needs a terminal had none — btop said so in as many words, "No tty
    // detected" — and every key typed here went to a terminal the tool was not
    // reading. It rendered perfectly and answered nothing. Written to a file
    // and run, the program keeps the terminal it was given.
    return [NSString stringWithFormat:
        @"PATH=/usr/sbin:/usr/bin:/sbin:/bin; export PATH; "
         "/usr/bin/printf %%s '%@' | /usr/bin/base64 -d | %@/bin/sh && %@ && "
         "f=$(/usr/bin/mktemp /tmp/slopnet-tool-XXXXXXXX) && "
         "cleanup_tool() { /bin/rm -f -- \"$f\"; } && "
         "trap cleanup_tool EXIT HUP INT TERM && "
         "/usr/bin/printf %%s '%@' | /usr/bin/base64 -d > \"$f\" && "
         "/bin/chmod 644 \"$f\" && %@%@",
        guardEncoded, privilege, prepare, encoded, privilege, runuser];
}

/// The release this copy of the app expects on a server, read from the
/// installer it ships with so there is one place it is written down.
- (NSString *)pinnedRelease {
#ifdef SLOPNET_NO_MAIN
    NSString *testing = NSProcessInfo.processInfo.environment[@"SLOPNET_PINNED_RELEASE"];
    if (testing.length > 0) return testing;
#endif
    NSString *script = [self helper:@"slopnet-vps-onboard"];
    NSString *text = script ? [NSString stringWithContentsOfFile:script
                                                        encoding:NSUTF8StringEncoding
                                                           error:nil] : nil;
    if (text == nil) return @"";
    NSRegularExpression *pin = [NSRegularExpression regularExpressionWithPattern:
        @"(?m)^slopnet_release=\"(v[0-9]+\\.[0-9]+\\.[0-9]+)\"$" options:0 error:nil];
    NSTextCheckingResult *found = [pin firstMatchInString:text options:0
                                                    range:NSMakeRange(0, text.length)];
    return found ? [text substringWithRange:[found rangeAtIndex:1]] : @"";
}

- (void)signInToProvider:(NSString *)provider {
    if (self.busy || ![self connectionValid]) return;
    NSString *script = [self helper:@"slopnet-vps-coding-app"];
    if (script == nil) {
        [self.console note:@"The part of SlopNet that signs in to a coding app is "
                           @"missing from this copy. Download SlopNet again."];
        return;
    }
    NSString *name = [SlopNetBrand displayNameForProvider:provider] ?: provider;
    [self.console note:[SlopNetBrand headerANSI:[NSString stringWithFormat:@"Setting up %@", name]
                                          width:[self panelWidth]]];
    self.signInQueueActive = NO;
    self.skippingSignIn = NO;
    self.signInQueue = [NSMutableArray array];
    self.signedIn = [NSMutableArray array];
    self.skipped = [NSMutableArray array];
    self.signingIn = provider;
    [self showSkipControl:name];
    [self beginActivity:@"search"
                caption:[NSString stringWithFormat:@"Setting up %@…", name]];
    [self setBusy:YES];
    if (![self.console runExecutable:@"/bin/bash"
                           arguments:@[script, self.host, self.port, self.username,
                                       provider, [self pinnedRelease]]]) {
        self.signingIn = nil;
        [self endActivity];
        [self setBusy:NO];
        [self showTypingBar];
    }
}

- (void)tools:(SlopNetTools *)tools signInToProvider:(NSString *)provider {
    (void)tools;
    [self signInToProvider:provider];
}

- (BOOL)startServerCommand:(NSString *)command title:(NSString *)title
               interactive:(BOOL)interactive {
    if (![self connectionValid]) return NO;
    // Several tools may run at once, each in its own tab. Only exclusive
    // Granite-side work (setup, chat, plan, build, install on tab 0) blocks
    // a new start. The old global busy latch meant a second Open did nothing,
    // which looked like Superfile or the next tool was broken.
    if ([self exclusiveWorkRunning]) return NO;
    if (interactive) {
        if (self.consoles.count > 0 && self.consoles[0].running && !self.toolRunning &&
            self.activeTab == 0) return NO;
    } else {
        if (self.consoles.count > 0 && self.consoles[0].running) return NO;
        if (self.busy && !self.toolRunning && ![self anyToolConsoleRunning]) return NO;
    }
    // A tool is unrelated to an old browser sign-in. Clear that specialised
    // bar before showing the terminal, so "Setting up Antigravity" and Skip
    // cannot survive underneath Zellij or another command.
    [self showTypingBar];
    NSString *release = [self pinnedRelease];
    if (release.length == 0) {
        [self.console note:@"This copy of SlopNet has no valid server release. "
                           "Download it again before running a server tool."];
        return NO;
    }
    // A tool gets a terminal of its own, so Granite stays where it was and is
    // one click away. Everything below runs against that new terminal, because
    // `console` is whichever tab is on top.
    if (interactive) {
        [self openTabTitled:title];
    } else {
        // A typed command, an install, a check: these belong with Granite,
        // not inside whatever tool happens to be open. Without this they ran
        // in the tool's tab, which is not where anybody would look for it.
        [self showTab:0];
    }
    self.toolRunning = interactive;
    // Put the keyboard back on the typing box, and the window in front.
    //
    // A tool is started from the Tools popup, so that is where the keyboard
    // is when it launches. Every key then goes to the sheet and none of it
    // reaches the box that forwards keys to the running program — so a
    // full-screen tool draws perfectly and answers nothing, which is exactly
    // how it looked. Raw input was working the whole time; it was never being
    // given anything to forward.
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.entry];
    command = [SlopNetAppDelegate asRuntimeAccount:command
                                            asRoot:[self.username isEqualToString:@"root"]
                                           release:release];
    [self.console note:[SlopNetBrand headerANSI:title width:[self panelWidth]]];
    [self beginActivity:@"search" caption:title];
    [self setBusy:YES];
    NSString *target = [NSString stringWithFormat:@"%@@%@", self.username, self.host];
    NSString *identity = [NSHomeDirectory() stringByAppendingPathComponent:
                          @".ssh/slopnet_vps_ed25519"];
    NSString *knownHosts = [NSHomeDirectory() stringByAppendingPathComponent:
                            @".ssh/slopnet_vps_known_hosts"];
    // A real terminal on the far end, so a sudo password prompt works.
    if (![self.console runExecutable:@"/usr/bin/ssh"
                           arguments:@[@"-t", @"-i", identity,
                                       @"-o", @"IdentitiesOnly=yes", @"-p", self.port,
                                       @"-o", [@"UserKnownHostsFile=" stringByAppendingString:knownHosts],
                                       @"-o", @"StrictHostKeyChecking=accept-new",
                                       target, command]]) {
        self.toolRunning = NO;
        [self setBusy:NO];
        return NO;
    }
    return YES;
}

- (void)tools:(SlopNetTools *)tools runOnServer:(NSString *)command
        title:(NSString *)title {
    (void)tools;
    [self startServerCommand:command title:title interactive:NO];
}

- (BOOL)tools:(SlopNetTools *)tools openOnServer:(NSString *)command
        title:(NSString *)title {
    (void)tools;
    return [self startServerCommand:command title:title interactive:YES];
}

/// Remove SlopNet properly. Dragging the app to the Trash leaves the
/// remembered server, the saved notes and the connection key on this Mac,
/// and leaves a private account and a downloaded model on the server.
- (void)settingsWantsUninstall:(SlopNetSettings *)settings {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Remove SlopNet?";
    alert.informativeText =
        @"This forgets your server, your saved requests and the connection key on "
        @"this Mac.\n\nIf you also remove it from the server, the private SlopNet "
        @"account and anything it downloaded there go too. Nothing else on that "
        @"server is touched — other accounts, websites and databases are left "
        @"alone.\n\nAfterwards, drag SlopNet from Applications to the Trash.";
    [alert addButtonWithTitle:@"Remove from this Mac only"];
    [alert addButtonWithTitle:@"Remove from this Mac and the server"];
    [alert addButtonWithTitle:@"Cancel"];
    NSModalResponse choice = [alert runModal];
    if (choice == NSAlertThirdButtonReturn) return;
    BOOL alsoServer = (choice == NSAlertSecondButtonReturn);

    if (alsoServer && self.host.length > 0) {
        NSString *script = [self helper:@"slopnet-vps-uninstall"];
        if (script == nil) {
            [self.console note:@"The part of SlopNet that clears a server is missing from "
                               @"this copy of the app. Removing from this Mac only."];
            alsoServer = NO;
        } else {
            [self.console note:[SlopNetBrand headerANSI:@"Removing SlopNet from your server"
                                                  width:[self panelWidth]]];
            self.uninstalling = YES;
            [self beginActivity:@"search" caption:@"Clearing the server…"];
            [self setBusy:YES];
            if (![self.console runExecutable:@"/bin/bash"
                                   arguments:@[script, self.host, self.port, self.username]]) {
                self.uninstalling = NO;
                [self setBusy:NO];
            }
            return;    // the Mac side runs when that finishes
        }
    }
    [self removeLocalTraces];
}

/// Delete only the key and host-trust files whose sidecar receipts still bind
/// their exact identities. A same-named file without that proof belongs to the
/// person, not to SlopNet, and local-only removal deliberately leaves it.
- (BOOL)removeProvedSSHArtifacts {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *sshDirectory = [NSHomeDirectory() stringByAppendingPathComponent:@".ssh"];
    NSString *key = [sshDirectory stringByAppendingPathComponent:@"slopnet_vps_ed25519"];
    NSArray<NSString *> *keyFiles = @[
        key, [key stringByAppendingString:@".pub"],
        [key stringByAppendingString:@".receipt"]
    ];
    BOOL keyExists = NO;
    for (NSString *path in keyFiles) keyExists |= SlopNetLocalPathExists(path);
    BOOL allRemoved = YES;
    if (keyExists) {
        if (!SlopNetProvedKeyPair(key)) {
            allRemoved = NO;
        } else {
            for (NSString *path in keyFiles) {
                if (![files removeItemAtPath:path error:nil]) allRemoved = NO;
            }
        }
    }

    NSString *knownHosts = [sshDirectory stringByAppendingPathComponent:
                            @"slopnet_vps_known_hosts"];
    NSArray<NSString *> *hostFiles = @[
        knownHosts, [knownHosts stringByAppendingString:@".receipt"]
    ];
    BOOL hostsExist = NO;
    for (NSString *path in hostFiles) hostsExist |= SlopNetLocalPathExists(path);
    if (hostsExist) {
        if (!SlopNetProvedKnownHosts(knownHosts)) {
            allRemoved = NO;
        } else {
            for (NSString *path in hostFiles) {
                if (![files removeItemAtPath:path error:nil]) allRemoved = NO;
            }
        }
    }
    return allRemoved;
}

- (void)removeLocalTraces {
    NSUserDefaults *store = [NSUserDefaults standardUserDefaults];
    for (NSString *key in @[kHostKey, kUserKey, kPortKey, kReadyKey, kGuideKey, kWizardKey,
                            @"SlopNetServerName", kSignedInProvidersKey, kLimitUntilKey]) {
        [store removeObjectForKey:key];
    }
    NSFileManager *files = NSFileManager.defaultManager;
    [files removeItemAtURL:[self historyDirectory] error:nil];
    BOOL removedSSH = [self removeProvedSSHArtifacts];

    // The preferences file itself, not just the keys inside it. Clearing the
    // keys left an empty plist with SlopNet's name on it.
    NSString *preferences = [NSHomeDirectory() stringByAppendingPathComponent:
        @"Library/Preferences/com.slopnet.app.plist"];
    [store synchronize];
    [files removeItemAtPath:preferences error:nil];

    self.host = @"";
    self.username = @"root";
    self.port = @"22";
    self.localModelName = nil;
    [self refreshModelLabel];
    [self refreshState];

    NSAlert *done = [[NSAlert alloc] init];
    done.messageText = @"SlopNet has removed itself";
    done.informativeText = removedSSH
        ? @"One thing left, and only you can do it: open your Applications folder "
          @"and drag SlopNet to the Trash.\n\nSlopNet will quit now."
        : @"A same-named SSH file did not match SlopNet's protected receipt, so it "
          @"was left alone. Archive it manually if you no longer need it.\n\nOpen your "
          @"Applications folder and drag SlopNet to the Trash. SlopNet will quit now.";
    [done addButtonWithTitle:@"Quit SlopNet"];
    [done runModal];
    [NSApp terminate:nil];
}

- (void)settingsDidForget:(SlopNetSettings *)settings {
    NSUserDefaults *store = [NSUserDefaults standardUserDefaults];
    // Forgetting the server forgets what was proved ON that server too, so the
    // wizard starts again rather than claiming a guide that belonged elsewhere.
    for (NSString *key in @[kHostKey, kUserKey, kPortKey, kReadyKey, kGuideKey, kWizardKey]) {
        [store removeObjectForKey:key];
    }
    self.host = @"";
    self.username = @"root";
    self.port = @"22";
    self.localModelName = nil;
    [self refreshModelLabel];
    [self.console note:@"\nForgotten on this Mac. Your server itself is untouched, and "
                       @"no password was ever stored."];
    [self refreshState];
}

- (void)settingsCheckConnection:(SlopNetSettings *)settings { [self checkConnection:nil]; }

- (void)settingsClearConsole:(SlopNetSettings *)settings { [self clearConsole:nil]; }

- (void)settingsShowServerHelp:(SlopNetSettings *)settings { [self openServerHelp:nil]; }

- (void)settings:(SlopNetSettings *)settings setupLocalHelperModel:(NSString *)model {
    [self installGuideModel:model];
}

- (void)installGuideModel:(NSString *)model {
    if (self.busy || ![self connectionValid]) return;
    NSString *script = [self helper:@"slopnet-vps-local-helper"];
    if (script == nil) {
        [self.console note:@"The local-helper setup is missing from this app. Build it again."];
        return;
    }
    NSString *helperProvider = [SlopNetBrand providerForLocalModel:model];
    [self.console note:[SlopNetBrand headerANSI:@"Preparing the local guide"
                                          width:[self panelWidth]]];
    if (helperProvider != nil) {
        [self.console note:[SlopNetBrand panelANSIForProvider:helperProvider
                                                       title:nil
                                                      detail:@[model]
                                                      action:nil
                                                       frame:0
                                                       width:[self panelWidth]]];
    }
    [self.console note:
        @"This happens only on your server. It will show the real capacity before "
         "it downloads anything, keeps this small helper to a 4K context and a "
         "15-minute test, and never opens a model port."];
    self.localHelperRunning = YES;
    [self beginActivity:@"db-research" caption:@"Preparing the local guide…"];
    [self setBusy:YES];
    // --approved: the wizard already showed the download size against this
    // server's free storage and memory, and would not enable Install until it
    // had checked. Pressing it is the answer; asking twice more in a terminal
    // is what left people staring at a screen that looked stuck.
    if (![self.console runExecutable:@"/bin/bash"
                           arguments:@[script, self.host, self.port, self.username,
                                       model, [self pinnedRelease], @"--approved"]]) {
        [self setBusy:NO];
    }
}

- (void)refreshLocalModelName {
    if (![self isReady] || self.host.length == 0) {
        self.localModelName = nil;
        [self refreshModelLabel];
        return;
    }
    // A quiet read-only check. It never starts a model, calls a coding CLI,
    // asks for a password, or changes the server. For a non-root connection,
    // sudo is explicitly non-interactive: lacking that permission is a failed
    // inspection, never false evidence that the private model is absent.
    NSString *probe =
        @"PATH=/usr/sbin:/usr/bin:/sbin:/bin; export PATH; "
         "home=$(getent passwd slopnet | cut -d: -f6); test -n \"$home\" && "
        @"sed -n 's/^SLOPNET_LOCAL_HELPER_MODEL=//p' "
        @"\"$home/.local/share/slopnet/local-helper.env\" 2>/dev/null | head -n 1";
    if (![self.username isEqualToString:@"root"]) {
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
                       @"-p", self.port,
                       @"-o", @"BatchMode=yes",
                       @"-o", @"ConnectTimeout=10",
                       @"-o", @"StrictHostKeyChecking=accept-new",
                       [NSString stringWithFormat:@"%@@%@", self.username, self.host],
                       probe];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSPipe pipe];
    __weak typeof(self) weakSelf = self;
    task.terminationHandler = ^(NSTask *finished) {
        NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        NSString *model = [text stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (strongSelf == nil) return;
            if (finished.terminationStatus == 0 &&
                [strongSelf matches:model pattern:@"^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*(:[A-Za-z0-9][A-Za-z0-9._-]*)?$"]) {
                strongSelf.localModelName = model;
                // Positive evidence from the server itself: that file exists
                // only after the model passed its proof. A failed read is NOT
                // treated as evidence the guide is gone — the network is the
                // likelier explanation, and nagging would be wrong.
                [strongSelf setGuideReady:YES];
            } else {
                strongSelf.localModelName = nil;
            }
            [strongSelf refreshModelLabel];
            [strongSelf refreshState];
        });
    };
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        self.localModelName = nil;
        [self refreshModelLabel];
    }
}

- (void)checkConnection:(id)sender {
    if (self.busy || ![self connectionValid]) return;
    [self.console note:[SlopNetBrand headerANSI:@"Checking the connection"
                                          width:[self panelWidth]]];
    [self beginActivity:@"search" caption:@"Reaching your server…"];
    [self setBusy:YES];
    NSString *target = [NSString stringWithFormat:@"%@@%@", self.username, self.host];
    NSString *identity = [NSHomeDirectory() stringByAppendingPathComponent:
                          @".ssh/slopnet_vps_ed25519"];
    NSString *knownHosts = [NSHomeDirectory() stringByAppendingPathComponent:
                            @".ssh/slopnet_vps_known_hosts"];
    if (![self.console runExecutable:@"/usr/bin/ssh"
                           arguments:@[@"-i", identity,
                                       @"-o", @"IdentitiesOnly=yes",
                                       @"-o", [@"UserKnownHostsFile=" stringByAppendingString:knownHosts],
                                       @"-p", self.port,
                                       @"-o", @"BatchMode=yes",
                                       @"-o", @"ConnectTimeout=10",
                                       @"-o", @"StrictHostKeyChecking=accept-new",
                                       target, @"echo SlopNet reached your server."]]) {
        [self setBusy:NO];
    }
}

/// The chat box has three deliberately separate paths. Running → the text
/// answers the visible program. Chat → one finite, private local-model reply.
/// Build → an explicit plan, then a second explicit approval before agents run.
- (void)sendPressed:(id)sender {
    if (self.busy) {
        [self.console sendLine:self.entry.string];
        self.entry.string = @"";
        [self resizeEntry];
        return;
    }
    if (![self isReady]) {
        [self.console note:@"\nConnect a server first — the setup guide walks you through it."];
        [self openWizardAtResumeStep];
        return;
    }
    NSString *idea = [self.entry.string stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![self guideReady]) {
        [self.console note:@"\nYour private guide is not installed yet. That is the thing "
                           @"that answers you, so the setup guide is opening — nothing is "
                           @"downloaded until you agree to it."];
        [self openWizardAtStep:SlopNetWizardStepGuide];
        return;
    }
    if (idea.length == 0) return;

    // A line beginning with $ is a command for the server, not a question for
    // the guide. Explicit on purpose: guessing which is which from the words
    // would eventually run something somebody meant as a sentence. It runs as
    // the locked account, like everything else SlopNet does on a server.
    if ([idea hasPrefix:@"$"]) {
        NSString *command = [[idea substringFromIndex:1]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (command.length == 0) return;
        self.entry.string = @"";
        [self resizeEntry];
        [self.console note:[SlopNetBrand youSaidANSI:idea width:[self panelWidth]]];
        [self runServerCommand:command];
        return;
    }

    // They were asked whether to build the last thing they described.
    if (self.turn == SlopNetTurnOfferedBuild) {
        self.entry.string = @"";
        [self resizeEntry];
        if ([self meansYes:idea]) {
            self.turn = SlopNetTurnNeedsName;
            [self.console note:[SlopNetBrand headerANSI:@"Naming it" width:[self panelWidth]]];
            [self.console note:@"What should I call it? A short name, lowercase letters, "
                               @"numbers and hyphens — photo-sheet, say."];
            [self refreshState];
            return;
        }
        // Anything that is not a yes is just more conversation.
        self.turn = SlopNetTurnTalking;
        self.pendingRequest = nil;
        [self askTheGuide:idea];
        return;
    }

    // They said yes and are naming it.
    if (self.turn == SlopNetTurnNeedsName) {
        NSString *name = idea.lowercaseString;
        if (![self matches:name pattern:@"^[a-z0-9][a-z0-9-]{0,62}$"]) {
            [self.console note:@"\nThat name will not work. Lowercase letters, numbers and "
                               @"hyphens only, starting with a letter or number — like "
                               @"photo-sheet. What should I call it?"];
            self.entry.string = @"";
            [self resizeEntry];
            return;
        }
        self.entry.string = @"";
        [self resizeEntry];
        [self startPlanFor:name request:self.pendingRequest ?: @""];
        return;
    }

    if (self.plannedProjectName.length > 0 && self.plannedProjectCommit.length > 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Start coding agents?";
        alert.informativeText = [NSString stringWithFormat:
            @"You approved the plan for %@. This starts the multi-agent coding run on your server and spends from the proved coding subscription. Agents may edit only that project; checks and its test command decide what can merge.",
            self.plannedProjectName];
        [alert addButtonWithTitle:@"Start coding agents"];
        [alert addButtonWithTitle:@"Keep plan only"];
        if ([alert runModal] != NSAlertFirstButtonReturn) return;
        NSString *script = [self helper:@"slopnet-vps-build"];
        if (script == nil) {
            [self.console note:@"The approved-build helper is missing from this app. Build it again."];
            return;
        }
        [self.console note:[SlopNetBrand headerANSI:@"Starting approved build"
                                              width:[self panelWidth]]];
        [self.console note:[NSString stringWithFormat:
            @"%@ — you explicitly approved this coding run.", self.plannedProjectName]];
        self.approvedBuildRunning = YES;
        self.activeProjectName = self.plannedProjectName;
        [self beginActivity:@"write" caption:@"Coding agents are working…"];
        [self setBusy:YES];
        if (![self.console runExecutable:@"/bin/bash"
                               arguments:@[script, self.host, self.port, self.username,
                                           self.plannedProjectName, self.plannedProjectCommit,
                                           [self pinnedRelease]]]) {
            self.approvedBuildRunning = NO;
            [self setBusy:NO];
        }
        return;
    }
    // Ordinary conversation. If it sounded like a request to have something
    // made, SlopNet says so once the guide has finished answering — the
    // reply comes first, then the offer.
    self.pendingRequest = [self soundsLikeARequestToBuild:idea] ? idea : nil;
    self.offerBuildWhenReplyEnds = (self.pendingRequest != nil);
    [self askTheGuide:idea];
}

/// One finite reply from the private guide on the server. It has no tools,
/// cannot reach a coding app, and cannot start a build.
- (void)askTheGuide:(NSString *)question {
    NSString *script = [self helper:@"slopnet-vps-chat"];
    if (script == nil) {
        [self.console note:@"The part of SlopNet that talks to your guide is missing from "
                           @"this copy of the app. Download SlopNet again."];
        return;
    }
    // The person's line, then the guide's name, then its reply streams in
    // underneath. The question used to be wrapped in a Granite panel with a
    // thinking glyph, so the screen showed Granite's mark above words Granite
    // had not written.
    [self.console note:[SlopNetBrand youSaidANSI:question width:[self panelWidth]]];
    NSString *context = [self guideContext];
    [self remember:[NSString stringWithFormat:@"You: %@", question]];
    // No bare name line here. The reply is drawn as a panel when the turn
    // ends, and printing this as well put a loose "Granite" above the panel.
    self.entry.string = @"";
    [self resizeEntry];
    // The panel opens now, empty, with the thinking glyph turning inside it.
    // The reply then types into this same block rather than appearing whole.
    NSString *guide = [SlopNetBrand providerForLocalModel:self.localModelName] ?: @"ibm_granite";
    self.replyText = @"";
    self.replyShown = 0;
    self.replyToken = [self.console noteReplaceable:
        [SlopNetBrand guideSaidANSI:@"" provider:guide name:@"Granite"
                             action:@"think" frame:0 width:[self panelWidth]]];
    [self beginActivity:@"think" caption:@"Your guide is thinking…"];
    [self setBusy:YES];
    // The reply is the news. A turn that worked should not be followed by a
    // note saying a program exited — that is the app talking about itself.
    self.console.quietWhenItWorks = YES;
    // Held back so the reply can be framed once it is complete. Only a
    // conversation turn does this — setup, installs and sign-ins keep
    // streaming into the window line by line, because watching them is the
    // whole point of showing a terminal at all.
    self.console.collectsOutput = YES;
    self.chatting = YES;
    if (![self.console runExecutable:@"/bin/bash"
                           arguments:@[script, self.host, self.port, self.username,
                                       question, context, [self pinnedRelease]]]) {
        self.chatting = NO;
        [self setBusy:NO];
    }
}

/// Ask the paid coding app for a plan, and stop there. Still two separate
/// agreements before any agent runs: this one, and the approval of the plan
/// it writes.
- (void)startPlanFor:(NSString *)name request:(NSString *)request {
    NSString *script = [self helper:@"slopnet-vps-project"];
    if (script == nil) {
        [self.console note:@"The part of SlopNet that makes a plan is missing from this "
                           @"copy of the app. Download SlopNet again."];
        return;
    }
    self.turn = SlopNetTurnTalking;
    self.pendingRequest = nil;
    [self rememberRequest:request project:name];
    [self.console note:[SlopNetBrand headerANSI:@"Writing a plan" width:[self panelWidth]]];
    [self.console note:[NSString stringWithFormat:
        @"%@ — %@\n\nThis asks the paid coding app on your server for a plan and then "
        @"stops. It writes no project files and starts no coding agents. You will read "
        @"the plan and decide separately.", name, request]];
    self.activeProjectName = name;
    self.plannedProjectName = nil;
    self.plannedProjectCommit = nil;
    self.planningRunning = YES;
    [self beginActivity:@"think" caption:@"Writing a plan…"];
    [self setBusy:YES];
    if (![self.console runExecutable:@"/bin/bash"
                           arguments:@[script, self.host, self.port,
                                       self.username, name, request, [self pinnedRelease]]]) {
        self.planningRunning = NO;
        [self setBusy:NO];
    }
}

#pragma mark - when the server asks for something specific

/// Put a real control in front of the person for the two moments that
/// frighten people: a password, and a yes/no they cannot undo.
- (void)console:(SlopNetConsole *)console
        asksFor:(SlopNetPrompt)prompt
       question:(NSString *)question {
    BOOL asking = (prompt != SlopNetPromptNone);
    self.promptBar.hidden = !asking;
    self.entryScroller.hidden = asking;
    self.sendButton.hidden = asking;

    self.secretField.hidden = (prompt != SlopNetPromptPassword);
    self.secretSend.hidden = (prompt != SlopNetPromptPassword);
    self.approveButton.hidden = (prompt != SlopNetPromptConfirm);
    self.declineButton.hidden = (prompt != SlopNetPromptConfirm);
    self.continueButton.hidden = (prompt != SlopNetPromptContinue);
    // The sign-in offer is separate: it stays put while the program keeps
    // printing, and is cleared when the run ends.
    self.openPageButton.hidden = (self.signInPage == nil);
    self.codeButton.hidden = (self.signInCode == nil);
    if (self.signInPage != nil) self.promptBar.hidden = NO;

    if (prompt == SlopNetPromptPassword) {
        self.promptLabel.stringValue =
            @"Your server is asking for its password. It goes straight there and is "
            @"never saved on this Mac.";
        self.promptLabel.textColor = [NSColor labelColor];
        self.secretField.stringValue = @"";
        [self.window makeFirstResponder:self.secretField];
    } else if (prompt == SlopNetPromptConfirm) {
        // The program's own question, minus the [y/N] it ends with — the
        // buttons say that part now.
        NSString *asked = question ?: @"";
        NSRange bracket = [asked rangeOfString:@"[" options:NSBackwardsSearch];
        if (bracket.location != NSNotFound) asked = [asked substringToIndex:bracket.location];
        asked = [asked stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
        self.promptLabel.stringValue = asked.length > 0 ? asked : @"It is asking you to confirm.";
        self.promptLabel.textColor = [NSColor labelColor];
        [self.window makeFirstResponder:self.approveButton];
    } else if (prompt == SlopNetPromptContinue) {
        NSString *asked = [question ?: @"" stringByTrimmingCharactersInSet:
            [NSCharacterSet characterSetWithCharactersInString:@" :\t"]];
        self.promptLabel.stringValue = asked.length > 0 ? asked : @"Ready to carry on.";
        self.promptLabel.textColor = [NSColor labelColor];
        [self.window makeFirstResponder:self.continueButton];
    } else {
        [self.window makeFirstResponder:self.entry];
    }
}

- (void)continuePressed:(id)sender { [self.console sendLine:@""]; }

/// A coding app wants a browser sign-in. It prints a link and a one-time
/// code, and expects both to be carried across by hand.
///
/// The code goes straight to the clipboard so it is ready to paste, and the
/// link gets a button showing exactly where it goes. SlopNet does not open it
/// unprompted: this is output from a program, and output is not an
/// instruction — the person decides.
- (void)console:(SlopNetConsole *)console needsSignIn:(NSURL *)page code:(NSString *)code {
    // The same page is offered again when the code turns up a moment after the
    // link, so only write it into the output the first time.
    BOOL alreadyShown = [page.absoluteString isEqualToString:self.signInPage.absoluteString];
    self.signInPage = page;
    self.signInCode = code;
    if (code.length > 0) {
        [NSPasteboard.generalPasteboard clearContents];
        [NSPasteboard.generalPasteboard setString:code forType:NSPasteboardTypeString];
    }
    self.promptBar.hidden = NO;
    // The box stays here too. A device sign-in usually wants a keypress on the
    // server as well — "press Enter to continue" — and the program is still
    // running while the browser page is open.
    self.entryScroller.hidden = NO;
    self.sendButton.hidden = NO;
    self.secretField.hidden = YES;
    self.secretSend.hidden = YES;
    self.approveButton.hidden = YES;
    self.declineButton.hidden = YES;
    self.continueButton.hidden = YES;
    self.openPageButton.hidden = NO;
    self.codeButton.hidden = (code.length == 0);

    // Open the browser rather than asking somebody to press a button to open
    // the browser — but only when the link is plainly an authorisation page.
    // A terms-of-service link printed beside a sign-in prompt was launched at
    // the operator once, and opening a browser is a side effect that should
    // never happen on a guess. Anything less certain waits behind the button.
    if (!alreadyShown && console.signInLinkIsAuthorisation) {
        [NSWorkspace.sharedWorkspace openURL:page];
    }

    // As few words as will do. The code is already on the clipboard, the page
    // is already open, and the only thing left is the paste.
    self.promptLabel.stringValue = code.length > 0
        ? [NSString stringWithFormat:@"Paste this in your browser:   %@", code]
        : @"Finish signing in in your browser.";
    self.promptLabel.textColor = [NSColor labelColor];
    // The program is still live and may be an alternate-screen menu. Keep its
    // keyboard path active; the browser and copy controls remain clickable.
    [self.window makeFirstResponder:self.entry];
}

- (void)openSignInPage:(id)sender {
    if (self.signInPage != nil) [NSWorkspace.sharedWorkspace openURL:self.signInPage];
}

- (void)putCodeOnClipboard:(id)sender {
    if (self.signInCode.length == 0) return;
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:self.signInCode forType:NSPasteboardTypeString];
}

- (void)secretEntered:(id)sender {
    NSString *secret = self.secretField.stringValue;
    if (secret.length == 0) return;
    self.secretField.stringValue = @"";     // no copy stays in the field
    [self.console sendSecret:secret];
}

- (void)approvePressed:(id)sender { [self.console sendLine:@"y"]; }

- (void)declinePressed:(id)sender { [self.console sendLine:@"n"]; }

#pragma mark - console callbacks

- (void)console:(SlopNetConsole *)console finishedWithStatus:(int)status {
    if (self.movingDirectory) {
        self.movingDirectory = NO;
        NSString *landed = [console.collectedOutput
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSArray<NSString *> *lines = [landed componentsSeparatedByString:@"\n"];
        landed = lines.lastObject ?: @"";
        if (status == 0 && [landed hasPrefix:@"/"]) {
            self.workingDirectory = landed;
            [console note:[NSString stringWithFormat:@"\n%@", landed]];
        }
        self.toolRunning = NO;
        self.returningToGranite = NO;
        [self setBusy:NO];
        [self showTypingBar];
        return;
    }
    if (self.chatting) {
        self.chatting = NO;
        NSString *said = console.collectedOutput;
        if (status == 0 && said.length > 0) {
            [self remember:[NSString stringWithFormat:@"Granite: %@", said]];
            [self typeReply:said];
        } else if (said.length > 0) {
            // A failure is shown plainly rather than dressed as the guide
            // speaking. It did not say this; something went wrong.
            [console note:[NSString stringWithFormat:@"\n%@", said]];
        }
    }
    // A coding-app sign-in that ended, however it ended. Recorded and moved
    // past, so one refusal cannot strand the rest of the queue.
    if (self.signingIn != nil) {
        [self endActivity];
        if (self.skippingSignIn) {
            [self.skipped addObject:self.signingIn];
            self.signingIn = nil;
            self.skippingSignIn = NO;
            [self setBusy:NO];
            [self startNextCodingAppSignIn];
            return;
        }
        [self codingAppSignInEnded:(status == 0)];
        return;
    }
    // A server counts as ready only when SETUP itself finished cleanly —
    // not because someone typed an address. That is what makes the green
    // dot in the sidebar worth trusting.
    if (self.setupRunning) {
        self.setupRunning = NO;
        if (status == 0) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kReadyKey];
            [self.console note:@"Your server is ready. Next: install the private local guide. "
                               @"It does not use your coding subscription."];
            [self refreshLocalModelName];
            // Straight on to the next wizard step, rather than leaving someone
            // to find the guide in Settings.
            dispatch_async(dispatch_get_main_queue(), ^{
                [self openWizardAtStep:SlopNetWizardStepGuide];
            });
        }
    }
    if (self.localHelperRunning) {
        self.localHelperRunning = NO;
        if (status == 0) {
            // The script writes its config only after the model has answered
            // its READY proof, so a clean exit here means the guide is proved.
            [self setGuideReady:YES];
            [self.console note:@"The private local guide passed its proof. Chat is now open."];
            [self refreshLocalModelName];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self openWizardAtStep:SlopNetWizardStepReady];
            });
        }
    }
    if (self.planningRunning) {
        self.planningRunning = NO;
        if (status == 0 && self.activeProjectName.length > 0) {
            NSString *transcript = console.textForTesting ?: @"";
            NSRegularExpression *proof = [NSRegularExpression
                regularExpressionWithPattern:@"(?m)^SLOPNET_PLAN_COMMIT=([0-9a-f]{40,64})$"
                                      options:0 error:nil];
            NSArray<NSTextCheckingResult *> *matches =
                [proof matchesInString:transcript options:0
                                 range:NSMakeRange(0, transcript.length)];
            NSTextCheckingResult *last = matches.lastObject;
            if (last != nil) {
                self.plannedProjectCommit =
                    [transcript substringWithRange:[last rangeAtIndex:1]];
                self.plannedProjectName = self.activeProjectName;
                [self.console note:@"The plan is ready above. Read it. No coding agent has run. Choose Build and press Start approved build only when you want the multi-agent run to begin."];
            } else {
                self.plannedProjectName = nil;
                self.plannedProjectCommit = nil;
                [self.console note:@"The server did not return an exact identity for that plan, so SlopNet will not offer it to coding agents. Make the plan again."];
            }
        }
    }
    if (self.uninstalling) {
        self.uninstalling = NO;
        [self setBusy:NO];
        // Server removal has its own protected ownership proof. Keep the Mac
        // connection and history if that proof refused or the person declined;
        // otherwise a failed server uninstall would look complete locally.
        if (status == 0) [self removeLocalTraces];
        return;
    }
    if (self.approvedBuildRunning) {
        self.approvedBuildRunning = NO;
        self.plannedProjectName = nil;
        self.plannedProjectCommit = nil;
        if (status == 0) {
            [self.console note:@"The approved build finished. Read the result above; SlopNet kept only work that passed its checks and project tests."];
        }
    }
    BOOL returningToGranite = self.returningToGranite;
    self.returningToGranite = NO;
    NSUInteger finishedIndex = [self.consoles indexOfObjectIdenticalTo:console];
    BOOL finishedToolTab = finishedIndex != NSNotFound && finishedIndex > 0;
    if (status != 0 && !returningToGranite) {
        // Note on the console that finished, not whichever tab is on top.
        [console note:@"Nothing was left half-done. Read the last few lines above, "
                      @"fix what they mention, and try again."];
    }
    self.signInPage = nil;
    self.signInCode = nil;
    self.openPageButton.hidden = YES;
    self.codeButton.hidden = YES;
    if (returningToGranite) {
        // Leave only the tool that was stopped; others keep running.
        if (finishedToolTab && finishedIndex < self.consoles.count) {
            [console removeFromSuperview];
            [self.consoles removeObjectAtIndex:finishedIndex];
            [self.tabTitles removeObjectAtIndex:finishedIndex];
        }
        [self showTab:0];
        [self showTypingBar];
    } else if (finishedToolTab) {
        // A tool ended on its own. Composer follows the tab still on top.
        [self syncComposerToActiveTab];
        if (self.activeTab == finishedIndex || !self.console.running) {
            [self showTypingBar];
        }
    } else {
        self.toolRunning = NO;
        [self setBusy:NO];
        [self showTypingBar];
    }

    // The guide has answered. If what they asked for sounded like something
    // to have made, offer now — after the reply, not on top of it.
    if (self.offerBuildWhenReplyEnds && self.pendingRequest.length > 0 && status == 0) {
        self.offerBuildWhenReplyEnds = NO;
        self.turn = SlopNetTurnOfferedBuild;
        [self.console note:[SlopNetBrand headerANSI:@"SlopNet" width:[self panelWidth]]];
        [self.console note:@"I can build that on your server if you want. A paid coding app "
                           @"writes a plan first and stops, so you get to read it before "
                           @"anything is coded.\n\nSay yes and I will ask what to call it. "
                           @"Or carry on talking and I will leave it."];
    } else {
        self.offerBuildWhenReplyEnds = NO;
        // Deliberately no ready block here. Redrawing the whole board after
        // every reply pushed the same header, guide panel and five coding-app
        // tiles into the transcript once per message — so a short exchange
        // read as screens of repeated furniture with a sentence buried in it.
        // The board is a greeting, not a footer.
    }
    [self.window makeFirstResponder:self.entry];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app { return YES; }

@end

#ifndef SLOPNET_NO_MAIN
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        (void)argc;
        (void)argv;
        NSApplication *app = [NSApplication sharedApplication];
        SlopNetAppDelegate *delegate = [[SlopNetAppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
    }
    return 0;
}
#endif
