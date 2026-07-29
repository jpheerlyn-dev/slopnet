#import "SlopNetConsole.h"
#import <util.h>
#import <termios.h>
#import <sys/ioctl.h>
#import <signal.h>
#import <unistd.h>

@interface SlopNetConsole ()
@property(nonatomic, strong) NSTextView *output;
@property(nonatomic, strong) NSScrollView *scroller;
@property(nonatomic, strong) NSTextField *input;
@property(nonatomic, strong) NSTextField *status;
@property(nonatomic, strong) NSButton *stopButton;
@property(nonatomic, assign) int master;          // our end of the PTY
@property(nonatomic, assign) pid_t child;
@property(nonatomic, strong) dispatch_source_t reader;
@property(nonatomic, strong) NSMutableString *pending;
@end

@implementation SlopNetConsole

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _master = -1;
    _child = -1;
    _pending = [NSMutableString string];

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

    _input = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _input.placeholderString = @"Type an answer here and press Return (for example: y)";
    _input.font = [NSFont monospacedSystemFontOfSize:11.5 weight:NSFontWeightRegular];
    _input.target = self;
    _input.action = @selector(inputEntered:);
    _input.enabled = NO;
    _input.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_input];

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
        [_input.topAnchor constraintEqualToAnchor:_status.bottomAnchor constant:6],
        [_input.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_input.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_stopButton.leadingAnchor constraintEqualToAnchor:_input.trailingAnchor constant:8],
        [_stopButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_stopButton.centerYAnchor constraintEqualToAnchor:_input.centerYAnchor],
        [_stopButton.widthAnchor constraintEqualToConstant:80],
        [_input.heightAnchor constraintEqualToConstant:24],
    ]];
    return self;
}

- (BOOL)running { return self.child > 0; }

#pragma mark - showing text

- (void)appendRaw:(NSString *)text {
    if (text.length == 0) return;
    NSTextStorage *storage = self.output.textStorage;
    [storage beginEditing];
    NSDictionary *attributes = @{
        NSFontAttributeName: self.output.font,
        NSForegroundColorAttributeName: [NSColor textColor],
    };
    [storage appendAttributedString:
        [[NSAttributedString alloc] initWithString:text attributes:attributes]];
    [storage endEditing];
    [self.output scrollRangeToVisible:NSMakeRange(storage.length, 0)];
}

- (void)note:(NSString *)text {
    [self appendRaw:[NSString stringWithFormat:@"%@\n", text]];
}

- (void)clear {
    [self.output.textStorage
        setAttributedString:[[NSAttributedString alloc] initWithString:@""]];
}

/// Programs decorate output with escape sequences for colour and cursor
/// movement. A plain text view would show them as gibberish, so remove
/// them and keep the words. Carriage returns become newlines so progress
/// lines stay readable instead of overwriting each other invisibly.
- (NSString *)readable:(NSString *)raw {
    NSMutableString *clean = [NSMutableString stringWithCapacity:raw.length];
    NSUInteger i = 0, n = raw.length;
    while (i < n) {
        unichar c = [raw characterAtIndex:i];
        if (c == 0x1B) {                       // ESC
            i++;
            if (i < n && [raw characterAtIndex:i] == '[') {
                i++;
                while (i < n) {                // CSI ... final byte @..~
                    unichar f = [raw characterAtIndex:i];
                    i++;
                    if (f >= 0x40 && f <= 0x7E) break;
                }
            } else if (i < n && ([raw characterAtIndex:i] == ']')) {
                while (i < n && [raw characterAtIndex:i] != 0x07) i++;
                if (i < n) i++;
            } else if (i < n) {
                i++;
            }
            continue;
        }
        if (c == '\r') {
            if (i + 1 < n && [raw characterAtIndex:i + 1] == '\n') { i++; continue; }
            [clean appendString:@"\n"];
            i++;
            continue;
        }
        if (c == 0x08) { i++; continue; }      // backspace
        [clean appendFormat:@"%C", c];
        i++;
    }
    return clean;
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
    self.input.enabled = YES;
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
            [strongSelf appendRaw:[strongSelf readable:chunk]];
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
    self.input.enabled = NO;
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

- (void)inputEntered:(id)sender {
    if (!self.running) return;
    [self sendLine:self.input.stringValue];
    self.input.stringValue = @"";
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
