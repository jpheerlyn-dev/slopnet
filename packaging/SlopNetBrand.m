#import "SlopNetBrand.h"
#import <CoreText/CoreText.h>

// The bundled colour face. Built by packaging/terminal-visuals/scripts
// (build_iconfont.py → patch_font.py → build_colorfont.py): Menlo plus a
// full-colour sbix bitmap per provider logo. Menlo derivatives may ship
// inside this local app but must never be published as a standalone
// download — see packaging/terminal-visuals/README.md.
static NSString *const kColorFontFile = @"Menlo-StormCode-Color";
static NSString *const kColorFontPSName = @"Menlo-RegularStormCodeColor";

// Each provider: id, recognised display name, base PUA codepoint in the
// colour font, and a plain-Unicode fallback mark. Codepoints are append-only
// and never renumbered (they are baked into built fonts). The colour font
// also carries a two-cell-wide twin of every badge at codepoint + 0x200;
// the app uses that one, because a single Menlo cell is far too narrow for
// a logo at text size.
typedef struct {
    __unsafe_unretained NSString *pid;
    __unsafe_unretained NSString *display;
    unichar codepoint;
    __unsafe_unretained NSString *mark;
} SlopNetBrandEntry;

static const SlopNetBrandEntry kBrands[] = {
    { @"anthropic",   @"Claude",       0xE000, @"✳" },
    { @"google",      @"Gemini",       0xE001, @"✦" },  // no multicolour wordmark: operator decision 2026-07-30
    { @"openai",      @"ChatGPT",      0xE002, @"❋" },
    { @"xai",         @"Grok",         0xE003, @"⦸" },
    { @"moonshot",    @"Moonshot",     0xE004, @"☾" },
    { @"zai",         @"GLM",          0xE005, @"⧫" },
    { @"minimax",     @"MiniMax",      0xE006, @"⬢" },
    { @"mistral",     @"Mistral",      0xE007, @"▤" },
    { @"alibaba",     @"Qwen",         0xE008, @"◈" },
    { @"aihorde",     @"AI Horde",     0xE009, @"⚔" },
    { @"cerebras",    @"Cerebras",     0xE00A, @"⬣" },
    { @"cohere",      @"Cohere",       0xE00B, @"◐" },
    { @"deepseek",    @"DeepSeek",     0xE00C, @"▲" },
    { @"huggingface", @"Hugging Face", 0xE00E, @"☻" },
    { @"ibm",         @"IBM",          0xE00F, @"☰" },
    { @"internlm",    @"InternLM",     0xE010, @"◧" },
    { @"meta",        @"Meta",         0xE011, @"∞" },
    { @"microsoft",   @"Microsoft",    0xE012, @"⊞" },
    { @"nous",        @"Nous",         0xE013, @"✧" },
    { @"nvidia",      @"NVIDIA",       0xE014, @"◤" },
    { @"ollama",      @"Ollama",       0xE015, @"◍" },
    { @"openrouter",  @"OpenRouter",   0xE016, @"⋈" },
    { @"perplexity",  @"Perplexity",   0xE017, @"⌕" },
    { @"tencent",     @"Tencent",      0xE018, @"◑" },
    { @"together",    @"Together",     0xE019, @"⧉" },
    { @"venice",      @"Venice",       0xE01A, @"⚿" },
    { @"stormcode",   @"StormCode",    0xE01B, @"🌀" },
    { @"cognition",   @"Devin",        0xE01C, @"⬡" },
    { @"xiaomi",      @"Xiaomi",       0xE01E, @"▣" },
    { @"inclusionai", @"InclusionAI",  0xE01F, @"◉" },
    { @"nova",        @"Nova",         0xE020, @"✶" },
    { @"poolside",    @"Poolside",     0xE021, @"≋" },
    { @"scale",       @"Scale",        0xE022, @"▰" },
    { @"stepfun",     @"StepFun",      0xE023, @"▦" },
    { @"jina",        @"Jina",         0xE024, @"⊙" },
    { @"rivescript",  @"RiveScript",   0xE025, @"❖" },
    { @"searxng",     @"SearXNG",      0xE026, @"⊚" },
    { @"ibm_granite", @"Granite",      0xE027, @"❐" },  // SlopNet's local default model
};
static const NSUInteger kBrandCount = sizeof(kBrands) / sizeof(kBrands[0]);

@implementation SlopNetBrand

+ (const SlopNetBrandEntry *)entryForProvider:(NSString *)providerId {
    for (NSUInteger i = 0; i < kBrandCount; i++) {
        if ([kBrands[i].pid isEqualToString:providerId]) return &kBrands[i];
    }
    return NULL;
}

+ (BOOL)colorFontActive {
    static BOOL active = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *url = [[NSBundle mainBundle] URLForResource:kColorFontFile
                                             withExtension:@"ttf"];
        if (url == nil) return;                 // font not bundled: plain marks
        CFErrorRef error = NULL;
        bool registered = CTFontManagerRegisterFontsForURL(
            (__bridge CFURLRef)url, kCTFontManagerScopeProcess, &error);
        if (!registered && error != NULL &&
            CFErrorGetCode(error) != kCTFontManagerErrorAlreadyRegistered) {
            // Damaged or unreadable font file. Say so once, fall back to
            // plain marks, and leave the console on the system font.
            NSLog(@"SlopNet: colour badge font did not register: %@",
                  (__bridge NSError *)error);
            CFRelease(error);
            return;
        }
        if (error != NULL) CFRelease(error);
        // Trust the font server, not the registration call: the font is
        // only "active" if it can actually be instantiated by name.
        active = ([NSFont fontWithName:kColorFontPSName size:12] != nil);
    });
    return active;
}

+ (NSFont *)consoleFontOfSize:(CGFloat)size {
    if ([self colorFontActive]) {
        NSFont *font = [NSFont fontWithName:kColorFontPSName size:size];
        if (font != nil) return font;
    }
    return [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular];
}

+ (NSString *)markForProvider:(NSString *)providerId {
    const SlopNetBrandEntry *entry = [self entryForProvider:providerId ?: @""];
    if (entry == NULL) return @"•";             // unmapped provider: neutral mark
    if ([self colorFontActive]) {
        // The two-cell-wide badge twin (codepoint + 0x200).
        unichar wide = entry->codepoint + 0x200;
        return [NSString stringWithCharacters:&wide length:1];
    }
    return entry->mark;
}

+ (NSString *)displayNameForProvider:(NSString *)providerId {
    const SlopNetBrandEntry *entry = [self entryForProvider:providerId ?: @""];
    return entry ? entry->display : (providerId ?: @"");
}

+ (NSArray<NSString *> *)allProviders {
    NSMutableArray<NSString *> *all = [NSMutableArray arrayWithCapacity:kBrandCount];
    for (NSUInteger i = 0; i < kBrandCount; i++) [all addObject:kBrands[i].pid];
    return all;
}

+ (NSString *)providerForTool:(NSString *)toolId {
    // tools.json ids → provider ids. Only real, operator-listed tools.
    static NSDictionary<NSString *, NSString *> *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{ @"codex":  @"openai",
                 @"claude": @"anthropic",
                 @"kimi":   @"moonshot",
                 @"gemini": @"google",
                 @"grok":   @"xai" };
    });
    return toolId ? map[toolId] : nil;
}

+ (NSString *)providerForLocalModel:(NSString *)model {
    if (model.length == 0) return nil;
    // Hugging Face identifiers carry the org up front: "ibm-granite/…".
    if ([model hasPrefix:@"ibm-granite/"]) return @"ibm_granite";
    return nil;
}

@end
