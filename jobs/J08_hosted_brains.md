# J08 — hosted brains: one protocol, many models

**Where:** the `slopnet` repo. **Size:** medium. **Touches:** `crew.py`,
`CREW.md`, `jobs/RESEARCH_subscriptions.md` (tick off what it answers).

## The decision this job implements

The operator asked whether SlopNet should run everything through Claude
Code. The answer, established 2026-07-28, is **partly — and the split is
not a preference, it is a fact about how subscriptions authenticate:**

| Subscription | How it logs in | Can it be driven through another CLI? |
|---|---|---|
| Claude | vendor account (OAuth) | n/a — it *is* the host |
| Google AI Pro | Google account (OAuth) in Gemini CLI | **No.** Locked to Gemini CLI. |
| ChatGPT | OpenAI account (OAuth) in Codex | **No.** Locked to Codex. |
| Grok | vendor login in Grok CLI | **No.** Locked to Grok CLI. |
| **zAI GLM coding plan** | **API key** | **Yes** — official docs describe exactly this, through Claude Code. |
| **Moonshot Kimi coding plan** | API key *and* its own CLI | Its own CLI already works; hosting is optional (verify). |

**An OAuth subscription cannot be redirected into another vendor's CLI.**
Using Gemini or GPT models inside Claude Code would need separate
pay-per-token API keys — money the operator is not currently spending —
so "everything through Claude Code" would silently strand two paid
subscriptions.

So: **native CLI where the login demands it; hosted brain where a key
allows it.** Hosted brains inherit the host's permission model, prompt
format, and output shape, which is the consistency the operator wanted,
without losing the subscriptions that can't be hosted.

Keep the fleet mixed for a second reason: different models fail
differently, and a single-host fleet stops entirely when that one
provider rate-limits or goes down.

## What to build

1. **Finish `HOSTED_BRAINS` in `crew.py`.** The `zai-glm` entry exists
   with its endpoint deliberately blank. Fill `ANTHROPIC_BASE_URL` from
   a **primary source** — Z.AI's own docs page, or by running
   `npx @z_ai/coding-helper` and reading what it configures. Do not
   invent or copy a URL from a blog. If you cannot confirm it, leave it
   blank, say so in `PENDING_OPERATOR.md`, and stop.
2. **Add Kimi as an optional hosted brain** only if the research report
   confirms Moonshot publishes an Anthropic-compatible endpoint covered
   by the coding plan. Its native CLI stays the default either way.
3. **`slopnet setup` explains hosted brains in one plain sentence** when
   it offers one, e.g. *"zai-glm — Z.AI's GLM model, driven through
   Claude Code using your ZAI_API_KEY."* And when a hosted brain is
   configured but its key is missing, say which variable to set rather
   than hiding the option.
4. **Prove a hosted brain really works** with the J01 probe (write
   `probe.txt`), and record `"proven": true` only on success.
5. **A red-team attack for secret hygiene:** run a hosted brain with a
   fake token in the environment and prove the token appears in no file
   the run writes — not the register, not `.slopnet/`, not the worktree,
   not any log.
6. **`CREW.md`**: add a short "Where your models come from" section with
   the table above, in plain words.

## Rules

- Standard library only.
- Tokens are read from the environment at run time and passed to one
  subprocess. Never written to `.slopnet/crew.json`, never printed,
  never committed.
- Do not remove or downgrade any native CLI to favour the host — that
  would strand a paid subscription.
- Do not claim a provider is supported until its probe has passed on a
  real run.

## Acceptance (run these; paste real output)

```bash
python3 ./slopnet setup
```
Hosted brains appear only when host + key are both present, with the
plain-English explanation.

```bash
bash tests/redteam.sh
```
Passes, including your new no-token-leak attack.
