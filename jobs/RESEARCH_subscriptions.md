# Research prompt — wiring paid coding subscriptions into a terminal

> **State: completed historical research prompt.** Its report is preserved
> below as time-stamped research; neither document proves a provider login or
> billing boundary on the VPS.

**How to use this:** paste everything in the block into a deep-research
agent in your browser. Save its answer as
`jobs/RESEARCH_subscriptions_REPORT.md` in the slopnet repo. Job
`J02_subscription_router.md` then implements what it finds.

**Why it's needed — updated 2026-07-28 after installing both:**

- **Kimi is solved.** Kimi Code CLI 0.29.2 installs to
  `~/.kimi-code/bin/kimi`, is a real coding agent, and runs headlessly
  as `kimi --auto -p "PROMPT"` (`--auto` = fully autonomous;
  `-y/--yolo` still asks questions, so `--auto` is the one for
  unattended work). Auth is `kimi login` (device-code flow).
  Already wired into `crew.py`. **Question 1 below is now only about
  whether the coding plan covers this CLI or bills separately.**
- **zAI is NOT solved, and `zai-cli` is not the answer.** The installed
  `zai-cli` v1.1.0 is a client for Z.AI's MCP *services* — vision,
  search, page reading, repo browsing, and TypeScript tool chains. It
  does not edit files in a project, so it cannot be a coding agent in
  the fleet, and `zai-cli doctor` reports `apiKeyPresent: false` (it
  wants an API key, i.e. credit, not the coding subscription).
  **Question 2 is therefore the important one: how does the zAI/GLM
  coding plan actually reach a terminal coding agent?**

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

Already verified locally, do NOT re-research these invocations:
  claude --dangerously-skip-permissions -p "PROMPT"
  codex exec "PROMPT"
  gemini --yolo -p "PROMPT"
  grok --permission-mode bypassPermissions -p "PROMPT"
  kimi --auto -p "PROMPT"        (Kimi Code CLI 0.29.2, auth: kimi login)
  hermes -z "PROMPT"
Also already established: the npm package `zai-cli` is a Z.AI MCP
services client (vision/search/read/repo/tool-chains), NOT a coding
agent, and it wants an API key rather than using the coding plan. Do not
recommend it as a coding agent.

ANSWER THESE, each with a primary source link (official docs, official
repo, or vendor dashboard page) and a "last verified" date:

1. MOONSHOT KIMI CODING PLAN — the CLI is already installed and working
   headlessly, so answer only:
   a. Does the Kimi *coding plan* subscription cover use of Kimi Code CLI
      (`kimi login`), or does CLI use draw on separately-billed API
      credit? Quote the pricing/plan page.
   b. Any documented limit on concurrent sessions or automated use.
   c. Which model alias `-m` should point at for coding work.

2. zAI / GLM CODING PLAN — mostly answered by Z.AI's own docs, which say
   the plan is used by pointing **Claude Code** at it with an API key
   from z.ai/manage-apikey, and that Claude Code's Opus/Sonnet/Haiku
   model variables map to GLM models. `npx @z_ai/coding-helper`
   configures this automatically. So answer only what remains:
   a. The exact `ANTHROPIC_BASE_URL` value for the GLM coding plan,
      quoted from Z.AI's own documentation (not a blog). This is the one
      value SlopNet still needs.
   b. The current model ids to set for
      ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL (docs showed GLM-4.7;
      the page also references a newer GLM-5.2 — say which is current
      and how to switch).
   c. Does the CODING PLAN cover this usage, or does it draw
      pay-per-token API credit? Quote the pricing page.
   d. Anything in the terms that forbids driving it automatically or in
      parallel.
   e. Is Claude Code the only supported host, or are Codex/other CLIs
      documented too?

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
