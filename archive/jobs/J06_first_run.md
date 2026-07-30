# J06 — first-run polish: the tool teaches itself

> **State: completed historical brief.** It polished the local command path.
> The remaining first-run work is a separately scheduled VPS setup proof.

**Where:** the `slopnet` repo. **Size:** small–medium.
**Touches:** `slopnet`, `install.sh`, `doctor.sh`.

## Why this job exists

The operator's own transcript is the evidence: an experienced-enough user
typed a path with the wrong letter case, hit an error that told them the
wrong thing, pasted a command with a missing bracket, and quit
frustrated. Every one of those was the tool's fault, not theirs.

## What to build

1. **`slopnet` with no arguments** prints a short welcome that *fits on
   one screen*: what this is (1 line), the three things most people want
   (`go`, `doctor`, `check`) with one plain sentence each, and one line
   pointing at the README. Not the argparse dump.
2. **Every error message ends with the next action.** Audit every
   `die(...)` and every failure path in `slopnet` and `crew.py`. Each
   must answer: what happened, why it matters, what to type next. Three
   short lines maximum, in the RULE/WHY/FIX spirit already used by the
   checks.
3. **Make it runnable from anywhere.** Provide (and document in
   `install.sh`) the one line that puts `slopnet` on the user's PATH, so
   they type `slopnet` rather than `python3 ./slopnet`. It must work on a
   default macOS zsh setup, be idempotent, and print what it changed.
   If it edits a shell profile, say which file and why, and never edit
   anything outside the user's own profile.
4. **`slopnet doctor --fix` fixes what it safely can** and, for anything
   it cannot fix itself (branch rules needing `gh`), prints the exact
   thing to click, in order, in plain words.
5. **Python version check.** If `python3` is older than 3.9, say so in
   one sentence with the fix, rather than failing later with a traceback.

## Rules

- No new dependencies. No new commands beyond what is listed above.
- Do not shorten an error by removing the reason — brevity never beats
  clarity here.
- Never edit a file outside the repo except the user's shell profile in
  step 3, and only with a printed explanation.

## Acceptance (run these; paste real output)

```bash
./slopnet
```
Fits on one screen and reads like a friendly note, not a manual page.

```bash
cd /tmp && slopnet doctor
```
(after your PATH step) — runs from anywhere and explains itself.

Deliberately break three things — remove a hook, corrupt the manifest,
delete `checks/` — and paste each error message. All three must tell you
exactly what to type next.
