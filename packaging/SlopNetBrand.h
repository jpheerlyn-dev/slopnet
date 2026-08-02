// SlopNetBrand — provider marks for the console and pickers.
//
// The tables are ported from packaging/terminal-visuals (StormCode's BRAND /
// GLYPH / MARK data). The bundled colour font carries each provider's real
// logo as a full-colour bitmap on a Private Use Area codepoint; when that
// font cannot be registered, every mark falls back to a plain Unicode
// character that renders in any font, so the console stays readable.
//
// Operator decisions honoured here (packaging/terminal-visuals/AGENT_BRIEF.md,
// 2026-07-30):
//  - the FULL glyph set is exposed, not the short demo_swarm.py roster
//  - no multicolour per-letter Google wordmark treatment
//  - IBM Granite cubes are their own glyph (U+E027), separate from `ibm`

#import <Cocoa/Cocoa.h>

@interface SlopNetBrand : NSObject

#pragma mark - the StormCode palette

// The shell colours, from packaging/terminal-visuals/scripts/demo_agency.py
// and runtime-modules/app.py. This is the spec, not a suggestion: a jet-black
// field, crimson chrome and borders, and a brand's own colours inside any
// panel that brand owns.

/// #000000 — the field every console cell is painted on.
+ (NSColor *)voidColor;
/// #FF003C — borders, frames, and SlopNet's own voice.
+ (NSColor *)crimsonColor;
/// #E8E8E8 — ordinary program output on the void field.
+ (NSColor *)inkColor;
/// #666666 — secondary detail (app.py's SHELL_GHOST).
+ (NSColor *)ghostColor;
/// Near-black with a cold lift — the liquid-glass host surface behind panels.
+ (NSColor *)chromeFieldColor;
/// Soft crimson used to tint glass toward StormCode without flooding it.
+ (NSColor *)chromeTintColor;
/// Phosphor green for live status, matching Granite's tint on black.
+ (NSColor *)phosphorColor;

#pragma mark - window chrome (retro terminal × liquid glass)

/// YES when this process can use macOS Liquid Glass (NSGlassEffectView).
+ (BOOL)liquidGlassAvailable;

/// Dark red-black shell for chrome. Does not change the console field.
+ (void)applyTerminalChromeToWindow:(NSWindow *)window;

/// Wrap chrome (sidebar, composer) in crimson-tinted Liquid Glass.
/// Never pass the console or its holder — that broke the live terminal.
+ (NSView *)glassPanelWrapping:(NSView *)content
                  cornerRadius:(CGFloat)radius
                     tintColor:(NSColor *)tint;

/// Glass bezel on a button when the system has one; rounded push otherwise.
+ (void)styleChromeButton:(NSButton *)button;

/// Monospaced label colour for section rails ("RECENT REQUESTS", version…).
+ (void)styleChromeCaption:(NSTextField *)label;

/// Panel background for a provider (BRAND bg); the void colour when unknown.
+ (NSColor *)backgroundColorForProvider:(NSString *)providerId;
/// Text colour to use inside that provider's panel (BRAND fg).
+ (NSColor *)foregroundColorForProvider:(NSString *)providerId;
/// The provider's mark colour (BRAND mark, falling back to fg).
+ (NSColor *)markColorForProvider:(NSString *)providerId;
/// Readable-on-black label colour for chrome outside a panel (BRAND tint).
+ (NSColor *)tintColorForProvider:(NSString *)providerId;

#pragma mark - the colour badge font

/// YES when the bundled colour badge font is registered and usable.
/// Registration happens once, on first call, for this process only —
/// nothing is installed on the Mac.
+ (BOOL)colorFontActive;

/// The console text font: the bundled colour face when it registered,
/// otherwise the system monospaced font. Either way text stays readable.
+ (NSFont *)consoleFontOfSize:(CGFloat)size;

/// One-or-two-cell mark for a provider id: the real colour badge when the
/// bundled font is active, a plain Unicode approximation otherwise, and a
/// neutral "•" for a provider nobody has mapped yet.
+ (NSString *)markForProvider:(NSString *)providerId;
+ (NSString *)paddedMarkForProvider:(NSString *)providerId;

/// Recognised display name ("Claude", "Granite", …); the id itself when unknown.
+ (NSString *)displayNameForProvider:(NSString *)providerId;

/// Every mapped provider id, in glyph (codepoint) order — the full set.
+ (NSArray<NSString *> *)allProviders;

/// Provider id for a tools.json tool id (codex → openai …); nil when unknown.
+ (NSString *)providerForTool:(NSString *)toolId;

/// Provider id for a local model identifier such as
/// "ibm-granite/granite-4.1-3b-GGUF:Q4_K_M"; nil when unknown.
+ (NSString *)providerForLocalModel:(NSString *)model;

#pragma mark - action glyphs

/// Concept names with drawn action glyphs: "search", "think", "read",
/// "write", "message", "user-message" and the rest of the built set.
+ (NSArray<NSString *> *)actionConcepts;

/// How many animation frames a concept has. 1 means it is a static icon,
/// 0 means the bundled font has no glyph for it.
+ (NSUInteger)frameCountForAction:(NSString *)concept;

/// One frame of an action glyph, as a string occupying exactly `cells`
/// columns. Frames advance with `index`, wrapping. Without the colour font
/// this is a plain spinner character, so the columns never shift.
+ (NSString *)actionGlyph:(NSString *)concept frame:(NSUInteger)index cells:(NSUInteger)cells;

#pragma mark - panels (the StormCode blocks)

/// SlopNet's own voice: a crimson section header on the void field, drawn
/// as ANSI so it goes through the console's colour path.
+ (NSString *)headerANSI:(NSString *)title width:(NSUInteger)width;
/// ASCII letters and digits remapped onto the striped IBM face bundled at
/// U+E800. Anything else — spaces, punctuation, accents — passes through, so a
/// heading keeps its shape. One striped glyph is one cell, like the base face.
+ (NSString *)stripedText:(NSString *)text;
/// One turn of the conversation, drawn as the person's line and nothing else.
+ (NSArray<NSString *> *)wrapText:(NSString *)text toColumns:(NSInteger)columns;
+ (NSString *)youSaidANSI:(NSString *)text width:(NSUInteger)width;
/// The guide's name on its own line, with its mark, ready for the reply to
/// stream underneath in ordinary ink.
/// A finished reply, framed the way demo_agency.py frames a turn: the vendor's
/// logo and name, the message icon beside it, then the words on that vendor's
/// own surface.
/// The same panel, with an action glyph in its header — `think` while the
/// guide is working, `message` once it has spoken.
+ (NSString *)guideSaidANSI:(NSString *)text
                   provider:(NSString *)providerId
                       name:(NSString *)name
                     action:(NSString *)action
                      frame:(NSUInteger)frame
                      width:(NSUInteger)width;
+ (NSString *)guideSaidANSI:(NSString *)text
                   provider:(NSString *)providerId
                       name:(NSString *)name
                      width:(NSUInteger)width;
+ (NSString *)guideRepliesANSIForProvider:(NSString *)providerId
                                     name:(NSString *)name;

/// A provider's panel: a crimson frame around a brand-filled block whose
/// first row carries the badge and the display name. `detail` lines are
/// drawn inside the fill in the brand's own text colour; pass nil for none.
/// `action`/`frame` add an animated glyph row when the concept has one.
+ (NSString *)panelANSIForProvider:(NSString *)providerId
                             title:(NSString *)title
                            detail:(NSArray<NSString *> *)detail
                            action:(NSString *)action
                             frame:(NSUInteger)frame
                             width:(NSUInteger)width;

/// A labelled block of compact brand-filled cells, one per provider: the
/// badge and its display name on that brand's own surface.
+ (NSString *)brandSheetANSIForProviders:(NSArray<NSString *> *)providers
                                   label:(NSString *)label
                                   width:(NSUInteger)width;

/// A row of small side-by-side panels, one per provider — the lane look the
/// demos use. Wraps onto further rows when they will not fit the width.
/// The coding-app tiles, each carrying a line of plain status underneath its
/// name — whether it is signed in, and so whether it can build anything.
/// Two to a row rather than three, so a name and a status both fit.
+ (NSString *)panelStripANSIForProviders:(NSArray<NSString *> *)providers
                                  status:(NSDictionary<NSString *, NSString *> *)status
                                   width:(NSUInteger)width;
+ (NSString *)panelStripANSIForProviders:(NSArray<NSString *> *)providers
                                   width:(NSUInteger)width;

/// A 24-bit colour check: one gradient row painted with 48;2;r;g;b and one
/// row of 38;2;r;g;b text. A diagnostic — if these are flat, the console is
/// not carrying truecolor.
+ (NSString *)colourCheckANSIWithWidth:(NSUInteger)width;

/// The whole mapped set as one such block — a debug sheet, not the app's
/// front door.
+ (NSString *)providerSheetANSIWithWidth:(NSUInteger)width;

@end
