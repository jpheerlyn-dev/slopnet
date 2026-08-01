// SlopNetTools — browse, install and launch tools from the vetted list.
//
// Library is every tool in tools.json, with install or set-up when that is
// proved. Installed is where you launch one; it opens a terminal tab in the
// main window. Settings is for connection and model configuration, not this.

#import <Cocoa/Cocoa.h>

@class SlopNetTools;

@protocol SlopNetToolsDelegate <NSObject>
/// Install a tool on the server, visibly, in the main console.
- (void)tools:(SlopNetTools *)tools runOnServer:(NSString *)command
        title:(NSString *)title;
/// Open an interactive tool in its own terminal tab. Returns NO when another
/// job already owns the console, so the popup stays open instead of hiding a
/// tool that never started.
- (BOOL)tools:(SlopNetTools *)tools openOnServer:(NSString *)command
        title:(NSString *)title;
/// Install and sign in to one coding app, through the same path the wizard uses.
- (void)tools:(SlopNetTools *)tools signInToProvider:(NSString *)provider;
@end

@interface SlopNetTools : NSWindowController

@property(nonatomic, weak) id<SlopNetToolsDelegate> delegate;

- (instancetype)initWithHost:(NSString *)host
                        port:(NSString *)port
                        user:(NSString *)user
                   connected:(BOOL)connected;

/// Show as a sheet on the main window.
- (void)presentFrom:(NSWindow *)parent;

/// Ask the server which tools it already has, and update both tabs.
- (void)refreshToolStatus;

/// Providers SlopNet can carry through a browser sign-in from the Library.
+ (BOOL)signInSupportedForProvider:(NSString *)provider;

@end
