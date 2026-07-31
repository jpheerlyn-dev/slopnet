# Finding 18: product-surface provider palette

**Status:** PASS — all 34 panels rebuilt and reviewed in macOS Terminal using
`Menlo-RegularStormCodeColor`; all 68 required contrast pairs pass.

## Outcome

Palette v2 fixed readability, but several cards still failed a more important
test: the logo and its panel merged into one shape, or the chosen colour
belonged to the parent company rather than the product people recognise.
Palette v3 treats the provider's current product surface as part of the logo.

The board now has three deliberately different kinds of card:

- light identity fields where the source mark is dark or multicolour;
- dark product surfaces that make bright marks read at terminal size;
- fully saturated inverse treatments where the field itself is iconic.

This restores StormCode's black/red character without making the board a row
of interchangeable black cards. The red borders provide structure; each
provider's surface, mark, and wordmark provide recognition.

## Before

Palette v2 passed numerical contrast but contained the weak or misleading
treatments called out above.

![Before — palette v2, all 34 panels](17-palette-v2-after.png)

## After

Fresh macOS Terminal captures at 14 pt and 130 × 43 cells, using the installed
`Menlo-RegularStormCodeColor` profile font:

![After — palette v3, all 34 panels](18-palette-v3-after.png)

## Identity and surface decisions

| Provider | Decision and reason |
|---|---|
| Qwen | Replaced the stale purple spiral with the current first-party three-segment Q mark from [Qwen](https://qwen.ai/). Electric blue `#082DFF` is now the recognisable field; the mark and type are inverted to white so they cannot disappear into it. |
| Claude | Retained the clay treatment. The darker `#B15C40` preserves Claude's orange identity while allowing white terminal text to pass at 4.69:1; canonical `#D97757` remains the external tint. |
| Gemini | Retained the white field and four-colour sparkle, and kept the product name **Gemini** rather than parent-company **Google**. |
| MiniMax | Switched from logo-adjacent red to the deep ink `#181E25` used by [MiniMax](https://www.minimax.io/). Its coral/pink gradient now reads immediately instead of dissolving into the panel. |
| Mistral | Retained white because the pixel mark depends on its native orange/red steps. Dark orange type passes on white, while the brighter amber tint remains visible on black chrome. |
| Moonshot | Used the official charcoal `#1D1D1F` rather than generic pure black, preserving the brand's restrained dark identity and separating it from Grok. |
| ChatGPT | Removed OpenAI green completely from the card. The monochrome white Blossom on classic ChatGPT slate `#343541` is product-recognisable and follows [OpenAI's rule that the Blossom must remain monochrome](https://openai.com/brand/). |
| Grok | Replaced the obsolete xAI-era angular asset with the [current first-party Grok slashed-ring mark](https://x.ai/_next/static/media/GROKLogo.1686pj7pmiyvt.svg). The provider key/company remain `xai`/xAI, but the visible product is now **Grok**, white on black as used by the current app. |
| GLM | Replaced corporate blue with the dark `#141618` product surface used by [Z.ai](https://z.ai/). The display stays **GLM** and the white mark is no longer confused with a blue panel. |
| Cerebras | Removed the unsupported purple field. A warm off-white surface exposes the native orange/black mark and follows the black, orange, and warm-neutral system on [Cerebras](https://www.cerebras.ai/). |
| Hugging Face | Changed yellow-on-yellow to the current deep navy `#0B0F19` surface from [Hugging Face](https://huggingface.co/). The yellow emoji is now the focal point and white labels remain crisp. |
| Meta | Moved the blue infinity mark onto the near-black hero treatment used by [Meta AI](https://ai.meta.com/), retaining its gradient rather than flattening it into the background. |
| Nova | Changed purple-on-purple to the black product shell used by [Amazon Nova](https://nova.amazon.com/). The visible identity is consistently **Nova**: full-colour asterisk, product name, and product surface; Amazon remains company metadata only. |
| Perplexity | Uses its near-black blue product surface and keeps the native teal mark/tint, matching [Perplexity](https://www.perplexity.ai/) while giving the mark strong graphical contrast. |
| Tencent | Replaced blue-on-blue with a pale ice-blue field derived from [Tencent](https://www.tencent.com/), preserving the full-colour mark and a dark blue wordmark. |
| Together | Replaced magenta-on-magenta with the deep navy surface used by [Together AI](https://www.together.ai/); the multicolour magenta/lavender/orange mark now carries the identity. |
| IBM | Retains strong IBM blue and the complete striped wordmark. The redundant text label remains suppressed in icon-font mode, so the panel reads `IBM`, never `IBMIBM`. |
| NVIDIA / OpenRouter | Retain their unmistakable full-saturation green and lime fields. Black type and their different mark geometry keep the adjacent green treatments distinct. |
| Poolside | Retains cyan because it provides strong separation for the native indigo globe and does not repeat either neighbouring field. |
| StormCode | Retains the board's strongest card: true black, pure `#FF003C` tornado and type, and the same red border rhythm as the application chrome. |
| Remaining providers | AI Horde, Cohere, DeepSeek, InternLM, Microsoft, Nous, Devin, Xiaomi, InclusionAI, Scale, StepFun, Ollama, and Venice retain their v2 treatments: each already had a recognisable native mark, readable type, and a surface distinct from its neighbours. |

## Contrast table

Ratios use WCAG relative luminance for sRGB colours. Panel text must reach
4.5:1 against its own panel; `tint` must independently reach 4.5:1 against
black because it is used in the roster and log feed. Panel-background contrast
against the terminal is intentionally not measured.

| Provider | Background | Text | Text/panel | Tint | Tint/black |
|---|---:|---:|---:|---:|---:|
| Qwen | `#082DFF` | `#FFFFFF` | 7.42:1 | `#8DB3FF` | 10.02:1 |
| Claude | `#B15C40` | `#FFFFFF` | 4.69:1 | `#D97757` | 6.73:1 |
| Gemini | `#FFFFFF` | `#202124` | 16.10:1 | `#4285F4` | 5.89:1 |
| MiniMax | `#181E25` | `#FFFFFF` | 16.78:1 | `#E34872` | 5.44:1 |
| Mistral | `#FFFFFF` | `#B53600` | 6.01:1 | `#FFAF01` | 11.38:1 |
| Moonshot | `#1D1D1F` | `#FFFFFF` | 16.83:1 | `#E2E3EA` | 16.41:1 |
| Ollama | `#FFFFFF` | `#000000` | 21.00:1 | `#E0DDD4` | 15.46:1 |
| ChatGPT | `#343541` | `#FFFFFF` | 12.13:1 | `#FFFFFF` | 21.00:1 |
| Grok | `#000000` | `#FFFFFF` | 21.00:1 | `#BDBDBD` | 11.18:1 |
| GLM | `#141618` | `#FFFFFF` | 18.14:1 | `#8DB3FF` | 10.02:1 |
| AI Horde | `#FFAA00` | `#000000` | 11.00:1 | `#56B4F8` | 9.28:1 |
| Cerebras | `#F7F5F2` | `#000000` | 19.30:1 | `#F15A29` | 6.23:1 |
| Cohere | `#F0EBE1` | `#1D4045` | 9.44:1 | `#7FD1B9` | 11.72:1 |
| DeepSeek | `#212327` | `#FFFFFF` | 15.74:1 | `#6E88FF` | 6.63:1 |
| Hugging Face | `#0B0F19` | `#FFFFFF` | 19.15:1 | `#FFD21E` | 14.49:1 |
| IBM | `#1F70C1` | `#FFFFFF` | 5.07:1 | `#75B9FF` | 10.14:1 |
| InternLM | `#858599` | `#000000` | 5.81:1 | `#858599` | 5.81:1 |
| Meta | `#111112` | `#FFFFFF` | 18.87:1 | `#2997FF` | 6.96:1 |
| Microsoft | `#FFFFFF` | `#242424` | 15.52:1 | `#F25022` | 5.95:1 |
| Nous | `#000000` | `#FFFFFF` | 21.00:1 | `#D8D4CF` | 14.24:1 |
| NVIDIA | `#76B900` | `#000000` | 8.71:1 | `#8FD400` | 11.59:1 |
| OpenRouter | `#C8FF00` | `#000000` | 17.76:1 | `#C8FF00` | 17.76:1 |
| Perplexity | `#010E17` | `#FFFFFF` | 19.51:1 | `#22B8CD` | 8.81:1 |
| Tencent | `#EAF3FA` | `#003A8C` | 9.43:1 | `#4D8FFF` | 6.69:1 |
| Together | `#151532` | `#FFFFFF` | 17.72:1 | `#FC6B3C` | 7.31:1 |
| Venice | `#F7F5ED` | `#0E2942` | 13.60:1 | `#3C8FDD` | 6.17:1 |
| StormCode | `#000000` | `#FF003C` | 5.32:1 | `#FF003C` | 5.32:1 |
| Devin | `#001423` | `#FFFFFF` | 18.68:1 | `#68D5DD` | 12.15:1 |
| Xiaomi | `#FF6900` | `#000000` | 7.27:1 | `#FF6900` | 7.27:1 |
| InclusionAI | `#6D3BD1` | `#FFFFFF` | 6.57:1 | `#B794F4` | 8.56:1 |
| Nova | `#000000` | `#FFFFFF` | 21.00:1 | `#E433FF` | 6.22:1 |
| Poolside | `#22C7D9` | `#211B55` | 7.57:1 | `#7B73FF` | 5.74:1 |
| Scale | `#000000` | `#FFFFFF` | 21.00:1 | `#B39DDB` | 8.76:1 |
| StepFun | `#FFFFFF` | `#000000` | 21.00:1 | `#E8E5DF` | 16.70:1 |

The tightest panel-text result is Claude at 4.69:1. The tightest
tint-on-black result is StormCode at 5.32:1. All 68 required pairs pass.

## Verification

- Complete icon/font pipeline: PASS — 34 logos and 34 inline marks generated;
  33 vector glyphs merged, with AI Horde's existing bitmap-only fallback;
  34 logos × 8 sizes × 4 widths produced 1,088 colour-font bitmaps with zero
  provider failures.
- Packaged and installed colour-font SHA-256 match:
  `1de0c1ba761a7d45287257fbaec43cf5a9bdebe4caad2e8ad8d7767d10cc7261`.
- Real Terminal review: PASS — three full-resolution pages inspected using the
  active `Menlo-RegularStormCodeColor` profile font.
- Provider-panel grid: PASS — every row is square.
- Swarm-demo grid: PASS — every row is square.
- Test suite: PASS — 139 tests in 14.66 seconds.

