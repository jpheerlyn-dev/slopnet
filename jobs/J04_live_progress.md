# J04 — a live view while the fleet works

> **State: completed historical brief.** Preserve it as implementation
> evidence; do not dispatch it before the one-agent VPS runtime exists.

**Where:** the `slopnet` repo. **Size:** medium. **Touches:** `slopnet`,
`crew.py` (emit only — the engine must stay UI-free).

## Why this job exists

Today `slopnet run` prints a line when a task finishes. With three agents
working for several minutes each, the terminal looks frozen — and a
frozen-looking terminal is how a beginner decides the tool is broken.

## What to build

A live, plain-text status block that updates in place while the wave
runs. No new dependencies — plain ANSI (`\r`, cursor up) or a simple
repaint. It must degrade gracefully when output is not a terminal (in
CI or piped to a file, print one line per state change instead).

Show, per task:

```
Wave 1 of 2                                    3m12s
  T1-weather-page   claude      working…       2m41s
  T2-weather-tests  codex       testing…       1m58s
  T3-readme         gemini      MERGED         0m47s
```

States, in plain words a child understands: `waiting`, `working…`,
`checking…` (walls), `testing…`, `MERGED`, `FAILED — <short reason>`.

Also required:

- **The clock keeps moving** even when an agent is silent, so it never
  looks hung.
- **A hint after 2 minutes of silence** from one agent: a dim line
  saying which agent is still thinking. Not an error — agents are slow.
- **Keep the engine UI-free.** `crew.py` may only call the `emit`
  callback it already has; all cursor movement lives in the CLI. (This
  separation is inherited from StormCode and is why the UI can be
  replaced later without touching the runner.)
- **The final summary stays on screen** after the live block ends.

## Rules

- Standard library only.
- Never hide a failure to keep the display tidy: every FAILED line keeps
  its reason.
- If the terminal is narrow (< 60 columns), degrade to one line per task
  rather than wrapping into a mess.

## Acceptance (run these; paste real output)

Run a two-task wave with real agents and paste a screenshot-style copy of
the live block mid-run and the final summary.

```bash
./slopnet run 2>&1 | cat
```
Piped (not a terminal): must print clean one-line-per-change output with
no escape codes.

```bash
bash tests/redteam.sh
```
Still passes.
