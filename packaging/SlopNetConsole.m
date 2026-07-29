#import "SlopNetConsole.h"
#import <util.h>
#import <termios.h>
#import <sys/ioctl.h>
#import <signal.h>
#import <unistd.h>

@interface SlopNetConsole ()
@property(nonatomic, strong) NSTextView *output;
@property(nonatomic, strong) NSScrollView *scroller;
@property(nonatomic, strong) NSTextField *status;
@property(nonatomic, strong) NSButton *stopButton;
@property(nonatomic, assign) int master;          // our end of the PTY
@property(nonatomic, assign) pid_t child;
@property(nonatomic, strong) dispatch_source_t reader;
@property(nonatomic, strong) NSMutableArray<NSMutableString *> *lines;
@property(nonatomic, assign) NSUInteger row;      // cursor line
@property(nonatomic, assign) NSUInteger column;   // cursor column
@property(nonatomic, assign) BOOL needsRedraw;
@end

/// Keep the console light even during a long build.
static const NSUInteger kMaxLines = 4000;

@implementation SlopNetConsole

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _master = -1;
    _child = -1;
    _lines = [NSMutableArray arrayWithObject:[NSMutableString string]];
    _row = 0;
    _column = 0;

    _output = [[NSTextView alloc] initWithFrame:NSZeroRect];
    _output.editable = NO;
    _output.selectable = YES;
    _output.richText = NO;
    _output.drawsBackground = YES;
    _output.backgroundColor = [NSColor textBackgroundColor];
    _output.font = [NSFont monospacedSystemFontOfSize:11.5 weight:NSFontWeightRegular];
    _output.textColor = [NSColor textColor];
    _output.automaticQuoteSubstitutionEnabled = NO;
    _output.textContainerInset = NSMakeSize(8, 8);

    _scroller = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _scroller.hasVerticalScroller = YES;
    _scroller.autohidesScrollers = NO;
    _scroller.borderType = NSBezelBorder;
    _scroller.documentView = _output;
    _scroller.translatesAutoresizingMaskIntoConstraints = NO;
    _output.minSize = NSMakeSize(0, 0);
    _output.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    _output.verticallyResizable = YES;
    _output.horizontallyResizable = NO;
    _output.autoresizingMask = NSViewWidthSizable;
    _output.textContainer.widthTracksTextView = YES;
    [self addSubview:_scroller];

    _status = [NSTextField labelWithString:@"Nothing running."];
    _status.font = [NSFont systemFontOfSize:11];
    _status.textColor = [NSColor secondaryLabelColor];
    _status.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_status];

    _stopButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    _stopButton.title = @"Stop";
    _stopButton.bezelStyle = NSBezelStyleRounded;
    _stopButton.target = self;
    _stopButton.action = @selector(stopPressed:);
    _stopButton.enabled = NO;
    _stopButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_stopButton];

    [NSLayoutConstraint activateConstraints:@[
        [_scroller.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_scroller.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scroller.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_status.topAnchor constraintEqualToAnchor:_scroller.bottomAnchor constant:6],
        [_status.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:2],
        [_status.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_status.trailingAnchor constraintLessThanOrEqualToAnchor:_stopButton.leadingAnchor constant:-8],
        [_stopButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:_status.trailingAnchor constant:8],
        [_stopButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_stopButton.centerYAnchor constraintEqualToAnchor:_status.centerYAnchor],
        [_stopButton.widthAnchor constraintEqualToConstant:80],
    ]];
    return self;
}

- (BOOL)running { return self.child > 0; }

#pragma mark - showing text

/// Push the line buffer into the view. Called after each chunk, not per
/// character, so a chatty program cannot make the window crawl.
- (void)redraw {
    if (!self.needsRedraw) return;
    self.needsRedraw = NO;
    NSString *joined = [self.lines componentsJoinedByString:@"\n"];
    NSDictionary *attributes = @{
        NSFontAttributeName: self.output.font,
        NSForegroundColorAttributeName: [NSColor textColor],
    };
    NSRange visible = [self.output visibleRect].size.height > 0
        ? [self.output selectedRange] : NSMakeRange(0, 0);
    (void)visible;
    [self.output.textStorage setAttributedString:
        [[NSAttributedString alloc] initWithString:joined attributes:attributes]];
    [self.output scrollRangeToVisible:
        NSMakeRange(self.output.textStorage.length, 0)];
}

- (NSMutableString *)currentLine {
    while (self.lines.count <= self.row) {
        [self.lines addObject:[NSMutableString string]];
    }
    return self.lines[self.row];
}

/// Write text at the cursor, overwriting what is already there — this is
/// what makes a progress line update in place instead of repeating.
- (void)putText:(NSString *)text {
    NSMutableString *line = [self currentLine];
    while (line.length < self.column) [line appendString:@" "];
    NSUInteger end = self.column + text.length;
    if (end <= line.length) {
        [line replaceCharactersInRange:NSMakeRange(self.column, text.length)
                            withString:text];
    } else {
        [line deleteCharactersInRange:
            NSMakeRange(self.column, line.length - self.column)];
        [line appendString:text];
    }
    self.column = end;
}

- (void)newline {
    self.row++;
    self.column = 0;
    [self currentLine];
    if (self.lines.count > kMaxLines) {
        NSUInteger drop = self.lines.count - kMaxLines;
        [self.lines removeObjectsInRange:NSMakeRange(0, drop)];
        self.row = self.row > drop ? self.row - drop : 0;
    }
}

/// A deliberately small terminal: enough to render progress lines, menus
/// and prompts correctly. It is not a full terminal emulator — a
/// full-screen program (a file manager, an editor) needs more than this.
- (void)consume:(NSString *)raw {
    NSUInteger i = 0, n = raw.length;
    while (i < n) {
        unichar c = [raw characterAtIndex:i];

        if (c == 0x1B) {                                  // escape
            i++;
            if (i < n && [raw characterAtIndex:i] == '[') {
                i++;
                NSMutableString *digits = [NSMutableString string];
                unichar final = 0;
                while (i < n) {
                    unichar f = [raw characterAtIndex:i];
                    i++;
                    if ((f >= '0' && f <= '9') || f == ';') {
                        [digits appendFormat:@"%C", f];
                        continue;
                    }
                    final = f;
                    break;
                }
                NSInteger value = digits.length ? [digits intValue] : 1;
                switch (final) {
                    case 'A':                              // cursor up
                        self.row = (self.row >= (NSUInteger)value) ? self.row - value : 0;
                        break;
                    case 'B':                              // cursor down
                        self.row += value;
                        [self currentLine];
                        break;
                    case 'C': self.column += value; break; // right
                    case 'D':                              // left
                        self.column = (self.column >= (NSUInteger)value)
                            ? self.column - value : 0;
                        break;
                    case 'G':                              // column
                        self.column = value > 0 ? (NSUInteger)(value - 1) : 0;
                        break;
                    case 'H': case 'f':                    // home
                        self.row = 0; self.column = 0;
                        break;
                    case 'K': {                            // erase in line
                        NSMutableString *line = [self currentLine];
                        if (self.column < line.length) {
                            [line deleteCharactersInRange:
                                NSMakeRange(self.column, line.length - self.column)];
                        }
                        break;
                    }
                    case 'J':                              // erase screen
                        if (value == 2 || digits.length == 0) {
                            [self.lines removeAllObjects];
                            [self.lines addObject:[NSMutableString string]];
                            self.row = 0; self.column = 0;
                        }
                        break;
                    default: break;                        // colours etc: ignore
                }
            } else if (i < n && [raw characterAtIndex:i] == ']') {
                while (i < n && [raw characterAtIndex:i] != 0x07) i++;   // title
                if (i < n) i++;
            } else if (i < n) {
                i++;
            }
            continue;
        }

        if (c == '\n') { [self newline]; i++; continue; }
        if (c == '\r') { self.column = 0; i++; continue; }
        if (c == 0x08) {                                   // backspace
            if (self.column > 0) self.column--;
            i++;
            continue;
        }
        if (c == '\t') {
            [self putText:@"    "];
            i++;
            continue;
        }
        if (c < 0x20) { i++; continue; }                   // other control bytes

        NSUInteger start = i;
        while (i < n) {
            unichar t = [raw characterAtIndex:i];
            if (t < 0x20 || t == 0x1B) break;
            i++;
        }
        [self putText:[raw substringWithRange:NSMakeRange(start, i - start)]];
    }
    self.needsRedraw = YES;
    [self redraw];
}

- (void)note:(NSString *)text {
    [self consume:[NSString stringWithFormat:@"%@\n", text]];
}

- (void)clear {
    [self.lines removeAllObjects];
    [self.lines addObject:[NSMutableString string]];
    self.row = 0;
    self.column = 0;
    self.needsRedraw = YES;
    [self redraw];
}


#pragma mark - running

- (BOOL)runExecutable:(NSString *)path arguments:(NSArray<NSString *> *)arguments {
    if (self.running) {
        [self note:@"Something is already running here. Stop it first."];
        return NO;
    }
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
        [self note:[NSString stringWithFormat:
            @"Cannot run %@ — it is missing or not executable.", path]];
        return NO;
    }

    struct winsize size = {0};
    size.ws_col = 100;
    size.ws_row = 30;

    int master = -1;
    pid_t pid = forkpty(&master, NULL, NULL, &size);
    if (pid < 0) {
        [self note:@"macOS would not give SlopNet a terminal for that program."];
        return NO;
    }

    if (pid == 0) {
        // Child: become the program. Nothing here may touch Cocoa.
        NSMutableArray *all = [NSMutableArray arrayWithObject:path];
        [all addObjectsFromArray:arguments ?: @[]];
        char **argv = calloc(all.count + 1, sizeof(char *));
        for (NSUInteger i = 0; i < all.count; i++) {
            argv[i] = strdup([all[i] UTF8String]);
        }
        argv[all.count] = NULL;
        setenv("TERM", "xterm-256color", 1);
        setenv("SLOPNET_IN_APP", "1", 1);
        execv(path.UTF8String, argv);
        _exit(127);                    // only reached if execv failed
    }

    self.master = master;
    self.child = pid;
    self.stopButton.enabled = YES;
    self.status.stringValue = [NSString stringWithFormat:@"Running %@ …",
                               path.lastPathComponent];

    __weak typeof(self) weakSelf = self;
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    self.reader = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, master, 0, queue);
    dispatch_source_set_event_handler(self.reader, ^{
        char buffer[4096];
        ssize_t got = read(master, buffer, sizeof(buffer));
        if (got <= 0) {
            dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf childEnded]; });
            return;
        }
        NSString *chunk = [[NSString alloc] initWithBytes:buffer
                                                   length:(NSUInteger)got
                                                 encoding:NSUTF8StringEncoding];
        if (chunk == nil) {
            chunk = [[NSString alloc] initWithBytes:buffer
                                             length:(NSUInteger)got
                                           encoding:NSISOLatin1StringEncoding];
        }
        if (chunk.length == 0) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (strongSelf == nil) return;
            [strongSelf consume:chunk];
        });
    });
    dispatch_resume(self.reader);
    return YES;
}

- (void)childEnded {
    if (self.child <= 0) return;
    if (self.reader) {
        dispatch_source_cancel(self.reader);
        self.reader = nil;
    }
    int raw = 0;
    pid_t finished = waitpid(self.child, &raw, WNOHANG);
    if (finished == 0) {
        // Not reaped yet: wait briefly rather than leaving a zombie.
        waitpid(self.child, &raw, 0);
    }
    int status = WIFEXITED(raw) ? WEXITSTATUS(raw) : -1;
    if (self.master >= 0) { close(self.master); self.master = -1; }
    self.child = -1;
    self.stopButton.enabled = NO;

    if (status == 0) {
        self.status.stringValue = @"Finished successfully.";
        [self note:@"\n— finished —"];
    } else if (status < 0) {
        self.status.stringValue = @"Stopped.";
        [self note:@"\n— stopped —"];
    } else {
        self.status.stringValue = [NSString stringWithFormat:
            @"Stopped with a problem (code %d). The last lines above say why.", status];
        [self note:[NSString stringWithFormat:@"\n— stopped, code %d —", status]];
    }
    if ([self.delegate respondsToSelector:@selector(console:finishedWithStatus:)]) {
        [self.delegate console:self finishedWithStatus:status];
    }
}

- (void)sendLine:(NSString *)line {
    if (!self.running || self.master < 0) return;
    NSString *withReturn = [line stringByAppendingString:@"\n"];
    const char *bytes = withReturn.UTF8String;
    size_t remaining = strlen(bytes);
    while (remaining > 0) {
        ssize_t wrote = write(self.master, bytes, remaining);
        if (wrote <= 0) break;
        bytes += wrote;
        remaining -= (size_t)wrote;
    }
}

- (void)stopPressed:(id)sender { [self stop]; }

- (void)stop {
    if (!self.running) return;
    [self note:@"\n(asking it to stop…)"];
    kill(self.child, SIGTERM);
    pid_t stopping = self.child;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (self.child == stopping) kill(stopping, SIGKILL);
    });
}

@end
