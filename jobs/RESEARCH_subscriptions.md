# Research prompt — wiring paid coding subscriptions into a terminal

**How to use this:** paste everything in the block into a deep-research
agent in your browser. Save its answer as
`jobs/RESEARCH_subscriptions_REPORT.md` in the slopnet repo. Job
`J02_subscription_router.md` then implements what it finds.

**Why it's needed:** two of the operator's six subscriptions (Moonshot
Kimi's coding plan, zAI's coding plan) have no dedicated CLI installed on
the machine. The common pattern is that such plans expose an
Anthropic- or OpenAI-compatible endpoint you point an existing CLI at —
but the exact variables, endpoints, and whether a *subscription* (as
opposed to pay-per-token API credit) may be used this way must be
verified from primary sources, not assumed.

---

```
I need a precise, current, primary-sourced guide to using paid AI coding
subscriptions from a Mac terminal, for an open-source tool called SlopNet
that runs several coding agents in parallel.

The user's subscriptions:
1. Google AI Pro (uses the Gemini CLI)
2. ChatGPT paid plan (uses Codex CLI)
3. Claude paid plan (uses Claude Code)
4. Grok paid plan (uses Grok Build CLI)
5. Moonshot Kimi coding plan
6. zAI coding plan

Already verified locally, do not re-research: claude -p "PROMPT"
(--dangerously-skip-permissions), codex exec "PROMPT", gemini -p
"PROMPT" (--yolo), grok -p "PROMPT" (--permission-mode ...),
hermes -z "PROMPT".

ANSWER THESE, each with a primary source link (official docs, official
repo, or vendor dashboard page) and a "last verified" date:

1. MOONSHOT KIMI CODING PLAN
   a. Does the plan include terminal/CLI use, or is it web/app only?
   b. Is there an official Kimi CLI? If yes: install command and the
      non-interactive invocation flags.
   c. If it works by pointing another CLI at a compatible endpoint
      (commonly Claude Code via ANTHROPIC_BASE_URL + ANTHROPIC_AUTH_TOKEN,
      or an OpenAI-compatible base URL): give the exact variable names,
      the exact endpoint URL, where the user obtains the token, and
      whether the SUBSCRIPTION covers it or it bills separately as API
      credit. Be explicit about that billing distinction.
   d. Model identifiers to use.

2. zAI CODING PLAN — the same four questions (a–d).

3. GROK BUILD — is CLI use included in the standard paid plan, and does
   it authenticate by login or by API key?

4. RUNNING SEVERAL AT ONCE: for each of the six, are there documented
   limits on concurrent sessions, rate limits, or terms that forbid
   automated/parallel invocation? Quote the relevant terms text.

5. AUTHENTICATION STATE: for each CLI, where is the login/token stored
   (file path or keychain), and does a non-interactive run reuse an
   existing login without prompting?

6. SAFETY FLAGS: for each CLI, the flag that allows unattended file
   edits, and any documented warning about it. Note which ones can run
   shell commands without asking, since that decides whether they are
   safe to run inside an isolated git worktree.

7. FAILURE MODES: what each CLI prints/exits when unauthenticated, out of
   quota, or rate-limited — the exact strings or exit codes if
   documented, so a wrapper can tell "not logged in" from "job failed".

OUTPUT FORMAT
- One section per numbered area, each ending with a table:
  agent | invocation | auth method | auto-approve flag | subscription
  covers CLI? (yes/no/unclear) | source link | verified date
- A final "DO NOT ASSUME" list: everything you could NOT verify from a
  primary source, stated plainly as unknown.
- Where vendor docs conflict with community posts, say so and prefer the
  vendor doc.
- Do not invent endpoints, variable names, or model ids. If you cannot
  find it, write "not found in primary sources".
```
