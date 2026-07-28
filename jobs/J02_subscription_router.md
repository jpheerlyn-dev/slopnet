# J02 — reach the subscriptions that have no CLI of their own

**Where:** the `slopnet` repo. **Size:** medium.
**Blocked until:** `jobs/RESEARCH_subscriptions_REPORT.md` exists (the
operator produces it from `RESEARCH_subscriptions.md`). If it is not
there, stop and say so — do not guess endpoints or variable names.

## Why this job exists

Four of the operator's subscriptions have CLIs on the machine (Claude
Code, Codex, Gemini CLI, Grok Build — handled by J01). Two do not:
Moonshot Kimi's coding plan and zAI's coding plan. Those are usually
reached by pointing an existing CLI, or a plain HTTP call, at a
compatible endpoint. The research report says exactly how; this job
implements only what the report *verified from primary sources*.

## What to build

1. **A `providers` section in `.slopnet/crew.json`** describing each
   non-CLI subscription: display name, how it is reached (env-var
   overrides on an existing CLI, or a direct HTTP endpoint), the env var
   names, and the model id. Nothing hard-coded that the report marked
   "unclear" or "not found".
2. **Env-var workers in `crew.py`.** A worker of kind `env-cli` runs an
   existing CLI with extra environment variables set for that one
   invocation (never exported globally, never written to disk). A worker
   of kind `api` already exists — extend it with the report's endpoints.
3. **`slopnet setup` offers them** alongside the installed CLIs, but only
   when the report confirmed the subscription covers terminal use. If the
   report says "bills separately as API credit", the setup wizard must
   say that in one plain sentence before the operator picks it — nobody
   should discover a bill by surprise.
4. **Failure messages that name the cause.** Use the report's §7 strings
   so an unauthenticated or rate-limited agent reports
   `[!!] kimi — not logged in` rather than a generic failure.
5. **Never log a token.** Secrets come from the environment, are used for
   one subprocess, and are never printed, never written to
   `.slopnet/`, never included in a register entry. Add a red-team attack
   proving a token in the environment does not appear in any file the run
   writes.

## Rules

- Standard library only. No new dependencies.
- Anything the report could not verify goes in `PENDING_OPERATOR.md` as a
  question — it does not go in the code as a guess.
- Do not change how the four working CLIs are driven (that is J01's).

## Acceptance (run these; paste real output)

```bash
python3 ./slopnet setup
```
Kimi and zAI appear only if the report supports them; any billing caveat
is shown in plain English.

```bash
bash tests/redteam.sh
```
Must pass, including your new no-token-leak attack.
