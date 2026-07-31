// A replaceable block that grows: the reply-typing case that used to freeze.
#import <Cocoa/Cocoa.h>
#import "SlopNetConsole.h"
#import "SlopNetBrand.h"
static int failures = 0;
static void check(BOOL ok, const char *what) {
    fprintf(stderr, "%s %s\n", ok ? "ok  " : "FAIL", what);
    if (!ok) failures++;
}
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    SlopNetConsole *c = [[SlopNetConsole alloc] initWithFrame:NSMakeRect(0,0,900,400)];
    [c layoutSubtreeIfNeeded];
    NSInteger token = [c noteReplaceable:
        [SlopNetBrand guideSaidANSI:@"" provider:@"ibm_granite" name:@"Granite"
                             action:@"think" frame:0 width:60]];
    check(token >= 0, "an empty reply panel is drawn");

    NSString *longReply = @"The message indicates that the model has been loaded but the "
                           "system is not currently inside a git repository. To resolve "
                           "this you can start one, or move into a folder that already is "
                           "one, and then try the same thing again.";
    BOOL grew = [c replaceLinesFromToken:token
                                    with:[SlopNetBrand guideSaidANSI:longReply
                                                            provider:@"ibm_granite"
                                                                name:@"Granite"
                                                              action:@"message" frame:0
                                                               width:60]];
    check(grew, "the panel accepts a reply taller than it started");
    NSString *shown = c.textForTesting;
    // A single word, because the wrap can fall anywhere and an assertion that
    // spans a line break fails for a reason that has nothing to do with the bug.
    check([shown containsString:@"again"],
          "the end of the reply is on screen, not just the first two lines");
    check([shown containsString:@"Message"], "and the header says Message, not Think");

    // Shrinking back must not leave the tall version behind.
    [c replaceLinesFromToken:token
                        with:[SlopNetBrand guideSaidANSI:@"Short." provider:@"ibm_granite"
                                                    name:@"Granite" action:@"message"
                                                   frame:0 width:60]];
    check(![c.textForTesting containsString:@"again"],
          "and a shorter reply does not leave the old lines behind");
    fprintf(stderr, failures == 0 ? "\nGROW PROBE DONE — all ok\n"
                                  : "\nGROW PROBE DONE — %d failed\n", failures);
} return failures == 0 ? 0 : 1; }
