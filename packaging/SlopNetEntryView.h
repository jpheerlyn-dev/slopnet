// The chat-style entry box shared by Granite questions and running programs.

#import <Cocoa/Cocoa.h>

@class SlopNetConsole;

@interface SlopNetEntryView : NSTextView
@property(nonatomic, copy) NSString *prompt;

/// A short readable name for a key, used by the readout that shows what was
/// last passed to a running tool.
+ (NSString *)nameForKeyEvent:(NSEvent *)event;
/// The running program these keys belong to, when there is one.
@property(nonatomic, weak) SlopNetConsole *console;
@end
