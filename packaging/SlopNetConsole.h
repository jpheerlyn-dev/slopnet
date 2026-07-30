// SlopNetConsole — a real terminal, living inside the app window.
//
// Why a pseudo-terminal (PTY) and not plain pipes: the things SlopNet
// runs are interactive. `ssh` reads a password straight from the
// terminal device, and SlopNet's own steps ask "continue? [y]". A piped
// process has no terminal, so those prompts either never appear or never
// receive an answer. A PTY makes the child believe it is talking to a
// person, which is the only way these flows work unattended by Terminal.
//
// This view owns: the scrolling output, a status line, and a stop button.
// The app's single large composer sends any answer to this terminal.
//
// Colour is part of the contract, not decoration. The console keeps each
// run of text with its own foreground and background, so StormCode-style
// output — brand-filled panels on a jet-black field with crimson frames —
// arrives in the app looking the way it does in a terminal.

#import <Cocoa/Cocoa.h>

@class SlopNetConsole;

/// What the running program is waiting for, as far as the console can tell
/// from what it just printed. Used to put a real control in front of the
/// person instead of asking them to type blind into a terminal.
typedef NS_ENUM(NSInteger, SlopNetPrompt) {
    SlopNetPromptNone = 0,   ///< nothing waiting, or ordinary typing
    SlopNetPromptPassword,   ///< a password or passphrase, which must not echo
    SlopNetPromptConfirm,    ///< a yes/no question
    SlopNetPromptContinue,   ///< it just wants Return pressed to carry on
};

@protocol SlopNetConsoleDelegate <NSObject>
@optional
- (void)console:(SlopNetConsole *)console finishedWithStatus:(int)status;
/// A sign-in page and its one-time code appeared in the output. Coding tools
/// authenticate by printing a link and a code for a browser; making somebody
/// copy both out of a terminal by hand is the worst moment in setup.
/// `code` may be nil when the tool printed only a link.
- (void)console:(SlopNetConsole *)console
    needsSignIn:(NSURL *)page
           code:(NSString *)code;
/// The running program started, or stopped, waiting for something specific.
/// `question` is the line it is waiting on, for showing above the control.
- (void)console:(SlopNetConsole *)console
       asksFor:(SlopNetPrompt)prompt
      question:(NSString *)question;

@end

@interface SlopNetConsole : NSView

@property(nonatomic, weak) id<SlopNetConsoleDelegate> delegate;
@property(nonatomic, readonly) BOOL running;

/// How many characters fit across the console at its current width. Panel
/// builders use this to fit their frames to the window instead of emitting
/// a check wider than the view.
@property(nonatomic, readonly) NSUInteger columns;

/// Run a program with arguments. Any previous run must have finished.
/// Returns NO and shows a plain-English line if it cannot start.
/// Say nothing when the next run ends cleanly.
///
/// A conversation turn is a program run, but nobody wants a note telling them
/// their sentence finished — the reply arriving is the news. Failures are
/// still announced, because those a person does need to see. Cleared after
/// each run, so it never silences the next one by accident.
@property(nonatomic, assign) BOOL quietWhenItWorks;

/// Everything currently on screen, for probes to read back.
- (NSString *)textForTesting;

- (BOOL)runExecutable:(NSString *)path
            arguments:(NSArray<NSString *> *)arguments;

/// Write one line (plus Return) to the running program, as if typed.
- (void)sendLine:(NSString *)line;

/// Write a secret the person typed into a real password field. It goes
/// straight to the program and is never put in the console buffer, never
/// logged, and never kept after this call.
- (void)sendSecret:(NSString *)secret;

/// Ask the running program to stop, then kill it if it ignores that.
- (void)stop;

/// Put a note in the console that did not come from a program. The text may
/// carry ANSI colour; SlopNet's own notes use it for headers and panels.
- (void)note:(NSString *)text;

/// Print lines that can be redrawn later, and return a token naming the
/// first of them. Use it to animate a glyph in place: the token stays valid
/// while those lines are still in the buffer.
- (NSInteger)noteReplaceable:(NSString *)text;

/// Redraw lines previously printed with -noteReplaceable:. Returns NO once
/// they have scrolled out of the buffer, which is the caller's cue to stop
/// animating. Never disturbs the cursor a running program is writing at.
- (BOOL)replaceLinesFromToken:(NSInteger)token with:(NSString *)text;

/// The line under the console: an optional badge glyph drawn in the colour
/// font, then plain text. Pass nil for the glyph when there is nothing to
/// show. This never scrolls, so it is where live activity belongs.
- (void)setStatusText:(NSString *)text
                glyph:(NSString *)glyph
                 tint:(NSColor *)tint;

/// Empty the console.
- (void)clear;


#pragma mark - for probes only

/// Everything printed so far, plain. Used by tests to assert on output.
- (NSString *)string;
/// Scroll state, so a probe can park the view and prove new output leaves it
/// alone. Not used by the app.
- (void)scrollToTopForTesting;
- (void)scrollToBottomForTesting;
- (CGFloat)scrollOffsetForTesting;
- (BOOL)isFollowingTailForTesting;
@end
