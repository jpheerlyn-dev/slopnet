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

/// Recognised display name ("Claude", "Granite", …); the id itself when unknown.
+ (NSString *)displayNameForProvider:(NSString *)providerId;

/// Every mapped provider id, in glyph (codepoint) order — the full set.
+ (NSArray<NSString *> *)allProviders;

/// Provider id for a tools.json tool id (codex → openai …); nil when unknown.
+ (NSString *)providerForTool:(NSString *)toolId;

/// Provider id for a local model identifier such as
/// "ibm-granite/granite-4.1-3b-GGUF:Q4_K_M"; nil when unknown.
+ (NSString *)providerForLocalModel:(NSString *)model;

@end
