// SlopNetSettings — the settings window.
//
// Everything you set up once lives here: which server SlopNet talks to, and
// the private local guide. Tools are installed and launched from the Tools
// popup, not from here. It opens from the sidebar, does its job, and gets
// out of the way.
//
// The guided path currently supports a Linux server reachable over SSH.
// Built-in terminal-tool downloads are proved only on x86-64 Linux.

#import <Cocoa/Cocoa.h>

@class SlopNetSettings;

@protocol SlopNetSettingsDelegate <NSObject>
/// Connect to this server and prepare it (runs in the main console).
- (void)settings:(SlopNetSettings *)settings
   connectToHost:(NSString *)host
            port:(NSString *)port
            user:(NSString *)user;
/// Forget this Mac's memory of the server (never touches the server).
- (void)settingsDidForget:(SlopNetSettings *)settings;
/// Remove SlopNet properly: everything it put on this Mac, and optionally
/// everything it put on the server. Dragging the app to the Trash leaves
/// both behind.
- (void)settingsWantsUninstall:(SlopNetSettings *)settings;
/// Small utility actions live in Settings so the main window stays focused
/// on the work the person is asking SlopNet to do.
- (void)settingsCheckConnection:(SlopNetSettings *)settings;
- (void)settingsClearConsole:(SlopNetSettings *)settings;
- (void)settingsShowServerHelp:(SlopNetSettings *)settings;
/// Set up the optional, server-only local helper with one public Hugging Face
/// GGUF.  This is deliberately separate from coding subscriptions: it never
/// receives an API key and only drafts wording a person can accept or reject.
- (void)settings:(SlopNetSettings *)settings
setupLocalHelperModel:(NSString *)model;
@end

@interface SlopNetSettings : NSWindowController

@property(nonatomic, weak) id<SlopNetSettingsDelegate> delegate;

- (instancetype)initWithHost:(NSString *)host
                        port:(NSString *)port
                        user:(NSString *)user
                   connected:(BOOL)connected;

/// Show as a sheet on the main window.
- (void)presentFrom:(NSWindow *)parent;

@end
