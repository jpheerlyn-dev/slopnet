// SlopNetConsole — a real terminal, living inside the app window.
//
// Why a pseudo-terminal (PTY) and not plain pipes: the things SlopNet
// runs are interactive. `ssh` reads a password straight from the
// terminal device, and SlopNet's own steps ask "continue? [y]". A piped
// process has no terminal, so those prompts either never appear or never
// receive an answer. A PTY makes the child believe it is talking to a
// person, which is the only way these flows work unattended by Terminal.
//
// This view owns: the scrolling output, one input line, a status line,
// and a stop button. It never interprets what it runs.

#import <Cocoa/Cocoa.h>

@class SlopNetConsole;

@protocol SlopNetConsoleDelegate <NSObject>
@optional
- (void)console:(SlopNetConsole *)console finishedWithStatus:(int)status;
@end

@interface SlopNetConsole : NSView

@property(nonatomic, weak) id<SlopNetConsoleDelegate> delegate;
@property(nonatomic, readonly) BOOL running;

/// Run a program with arguments. Any previous run must have finished.
/// Returns NO and shows a plain-English line if it cannot start.
- (BOOL)runExecutable:(NSString *)path
            arguments:(NSArray<NSString *> *)arguments;

/// Write one line (plus Return) to the running program, as if typed.
- (void)sendLine:(NSString *)line;

/// Ask the running program to stop, then kill it if it ignores that.
- (void)stop;

/// Put a note in the console that did not come from a program.
- (void)note:(NSString *)text;

/// Empty the console.
- (void)clear;

@end
