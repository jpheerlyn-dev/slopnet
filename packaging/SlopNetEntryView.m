// NSTextView has no native placeholder on the oldest macOS version SlopNet
// supports. Keep the tiny drawing behaviour here instead of putting a fake
// label over the editor (which would steal clicks and accessibility focus).

#import "SlopNetEntryView.h"
#import "SlopNetConsole.h"

@implementation SlopNetEntryView
- (void)setPrompt:(NSString *)prompt {
    _prompt = [prompt copy];
    [self setNeedsDisplay:YES];
}
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    if (self.string.length == 0 && self.prompt.length > 0) {
        NSDictionary *attributes = @{
            NSFontAttributeName: self.font ?: [NSFont systemFontOfSize:12],
            NSForegroundColorAttributeName: [NSColor placeholderTextColor],
        };
        // Line-fragment padding sits inside the container on top of the inset,
        // and typed text begins after both. Drawing the placeholder at the
        // inset alone put it five points to the left of where the caret rests,
        // so the insertion point appeared to sit inside the first word.
        CGFloat left = self.textContainerInset.width + self.textContainer.lineFragmentPadding;
        [self.prompt drawAtPoint:NSMakePoint(left, self.textContainerInset.height + 1)
                   withAttributes:attributes];
    }
}

/// Send a key straight to the running program instead of editing text.
///
/// A full-screen program — a login menu, a file browser — reads arrow keys as
/// escape sequences and Enter as a carriage return. Without this the operator
/// could see such a menu and had no way to move in it, which is what made a
/// sign-in look frozen.
///
/// A program using the alternate screen owns every non-Command key as it is
/// pressed. Outside that screen only navigation, an empty Return and Ctrl-C
/// bypass the line editor. That keeps ordinary questions, sudo answers and
/// passwords on their existing finished-line paths.
- (void)keyDown:(NSEvent *)event {
    if (!self.console.running) { [super keyDown:event]; return; }
    if ((event.modifierFlags & NSEventModifierFlagCommand) != 0) {
        [super keyDown:event];
        return;
    }
    if ([self.console sendKeyEvent:event]) return;
    SlopNetKey key; BOOL send = YES;
    switch (event.keyCode) {
        case 126: key = SlopNetKeyUp;     break;
        case 125: key = SlopNetKeyDown;   break;
        case 124: key = SlopNetKeyRight;  break;
        case 123: key = SlopNetKeyLeft;   break;
        case 53:  key = SlopNetKeyEscape; break;
        case 48:  key = SlopNetKeyTab;    break;
        case 36:                                  // return
        case 76:
            key = SlopNetKeyEnter;
            send = (self.string.length == 0);
            break;
        default: send = NO; key = SlopNetKeyEnter; break;
    }
    // Ctrl-C, so a line-oriented program can still be interrupted without
    // turning every other Control combination into editor text.
    if ((event.modifierFlags & NSEventModifierFlagControl) &&
        [event.charactersIgnoringModifiers.lowercaseString isEqualToString:@"c"]) {
        key = SlopNetKeyInterrupt; send = YES;
    }
    if (!send) { [super keyDown:event]; return; }
    [self.console sendKey:key];
}

- (void)didChangeText { [super didChangeText]; [self setNeedsDisplay:YES]; }
@end
