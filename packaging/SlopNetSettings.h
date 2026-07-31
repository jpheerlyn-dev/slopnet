// SlopNetSettings — the settings window.
//
// Everything you set up once lives here: which server SlopNet talks to,
// and which coding tools are on it. It opens from the sidebar, does its
// job, and gets out of the way.
//
// "Server" means any computer you can reach over SSH — a rented VPS, a
// dedicated box, a machine in your cupboard, a Raspberry Pi. SlopNet does
// not care who sold it to you.

#import <Cocoa/Cocoa.h>

@class SlopNetSettings;

@protocol SlopNetSettingsDelegate <NSObject>
/// Connect to this server and prepare it (runs in the main console).
- (void)settings:(SlopNetSettings *)settings
   connectToHost:(NSString *)host
            port:(NSString *)port
            user:(NSString *)user;
/// Run one command on the server, visibly, in the main console.
/// Install and sign in to one coding app, through the same path the wizard
/// uses — which also brings the server's copy of SlopNet up to the release
/// this app expects.
- (void)settings:(SlopNetSettings *)settings signInToProvider:(NSString *)provider;
- (void)settings:(SlopNetSettings *)settings runOnServer:(NSString *)command
           title:(NSString *)title;
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

/// Ask the server which tools it already has, and update the list.
- (void)refreshToolStatus;

@end
