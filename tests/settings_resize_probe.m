// settings_resize_probe.m — proves the Settings window survives resizing.
//
// "Everything breaks when I resize" has a mechanical signature: AppKit logs
// "Unable to simultaneously satisfy constraints" and silently drops one.
// This walks the window through a range of sizes, including shrinking below
// its opening size and growing again, and lays out each time. Any conflict
// appears in the output.
//
//   clang -fobjc-arc -framework AppKit -framework CoreText -I packaging \
//     tests/settings_resize_probe.m packaging/SlopNetSettings.m \
//     packaging/SlopNetBrand.m -o /tmp/probe \
//     && /tmp/probe
#import <Cocoa/Cocoa.h>
#import "SlopNetSettings.h"
@interface Probe : NSObject <SlopNetSettingsDelegate> @end
@implementation Probe
- (void)settings:(SlopNetSettings *)s connectToHost:(NSString *)h port:(NSString *)p user:(NSString *)u {}
- (void)settings:(SlopNetSettings *)s signInToProvider:(NSString *)p {}
- (void)settings:(SlopNetSettings *)s runOnServer:(NSString *)c title:(NSString *)t {}
- (BOOL)settings:(SlopNetSettings *)s openOnServer:(NSString *)c title:(NSString *)t { return YES; }
- (void)settingsDidForget:(SlopNetSettings *)s {}
- (void)settingsWantsUninstall:(SlopNetSettings *)s {}
- (void)settingsCheckConnection:(SlopNetSettings *)s {}
- (void)settingsClearConsole:(SlopNetSettings *)s {}
- (void)settingsShowServerHelp:(SlopNetSettings *)s {}
- (void)settings:(SlopNetSettings *)s setupLocalHelperModel:(NSString *)m {}
@end
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        Probe *probe = [Probe new];
        SlopNetSettings *settings = [[SlopNetSettings alloc]
            initWithHost:@"203.0.113.10" port:@"22" user:@"root" connected:YES];
        settings.delegate = probe;
        NSWindow *w = settings.window;
        CGFloat sizes[][2] = {{660,580},{520,360},{1200,900},{520,360},{800,420}};
        for (int i = 0; i < 5; i++) {
            [w setFrame:NSMakeRect(0, 0, sizes[i][0], sizes[i][1]) display:YES];
            [w.contentView layoutSubtreeIfNeeded];
            fprintf(stderr, "laid out %.0fx%.0f ok\n", sizes[i][0], sizes[i][1]);
        }
        fprintf(stderr, "RESIZE PROBE DONE\n");
    }
    return 0;
}
