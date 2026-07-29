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
- (void)settings:(SlopNetSettings *)settings runOnServer:(NSString *)command
           title:(NSString *)title;
/// Forget this Mac's memory of the server (never touches the server).
- (void)settingsDidForget:(SlopNetSettings *)settings;
/// Small utility actions live in Settings so the main window stays focused
/// on the work the person is asking SlopNet to do.
- (void)settingsCheckConnection:(SlopNetSettings *)settings;
- (void)settingsClearConsole:(SlopNetSettings *)settings;
- (void)settingsShowServerHelp:(SlopNetSettings *)settings;
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
