# J01 — drive every subscribed CLI correctly (and prove it)

> **State: completed historical brief.** Its local-path implementation and
> evidence are preserved in the repository and register. Do not dispatch it
> again as VPS proof; a selected CLI must be re-proven in the VPS runtime.

**Where:** the `slopnet` repo. **Size:** large. **Touches:** `crew.py`,
`tests/`, `CREW.md`.

## Why this job exists

`crew.py` currently guesses how to invoke each coding CLI. Guessed flags
are how "easy mode" breaks on someone else's machine. The flags below
were **verified on the operator's Mac on 2026-07-28** by reading each
tool's own `--help`. Your job is to make `crew.py` use them, handle the
ones that need permission flags, and prove each one really edits files.

## The verified invocation table

| Agent | Non-interactive invocation | Auto-approve flag (needed to edit files unattended) |
|---|---|---|
| `claude` (Claude Code 2.1.220) | `claude -p "PROMPT"` | `--dangerously-skip-permissions` |
| `codex` (codex-cli 0.145.0) | `codex exec "PROMPT"` | check `codex exec --help` for its sandbox/approval flag |
| `gemini` (Gemini CLI 0.52.0) | `gemini -p "PROMPT"` | `--yolo` (or `--approval-mode yolo`) |
| `grok` (Grok Build) | `grok -p "PROMPT"` | `--permission-mode bypassPermissions` (see its `--help` list) |
| `hermes` | `hermes -z "PROMPT"` | one-shot mode; confirm it can edit files at all |

Also verified: `grok` supports `--prompt-file PATH` and
`--output-format plain|json`, and `codex exec` accepts the prompt on
stdin — useful if a prompt is too long for a shell argument.

## What to build

1. **A real agent registry in `crew.py`.** Replace the `KNOWN_AGENTS`
   guesses with entries carrying: the invocation template, the
   auto-approve flag, and a `probe` string. Keep `{prompt}` as the
   placeholder the runner substitutes (it is already shell-quoted).
2. **Long prompts must not break.** If a prompt exceeds ~100 KB, write it
   to a temp file and use the agent's file/stdin form. Never truncate a
   task brief silently.
3. **`slopnet setup` proves each agent before trusting it.** For every
   agent the operator picks, run a tiny probe job in a throwaway temp
   git repo: *"Create a file named probe.txt containing the word ready.
   Do nothing else."* Then check the file exists. Report per agent:
   `[OK] claude — wrote the file in 4s` or
   `[!!] hermes — ran but changed nothing (see notes)`. Save the result in
   `.slopnet/crew.json` as `"proven": true|false` with the date.
   **An unproven agent may not be given real work** — `slopnet run`
   refuses it with a one-line explanation.
4. **Timeouts and honesty.** Per-agent timeout (default 900s, in the
   config). On timeout the attempt FAILS with "agent timed out after Ns"
   — never a silent pass.
5. **`CREW.md`**: replace the "Honest limits" paragraph with the real
   table, and say plainly which agents are proven on this machine.

## Rules

- Do not add a dependency. Standard library only.
- Do not weaken `refuse_fake_gate` or any check to make a probe pass.
- If an agent cannot be driven headlessly at all, record that in
  `PENDING_OPERATOR.md` and mark it unusable in the registry — do not
  fake support for it.

## Acceptance (you run these; paste real output into the register)

```bash
python3 ./slopnet setup
```
Every installed agent must be listed, probed, and marked proven/unproven
with a reason.

```bash
bash tests/redteam.sh
```
Must still end `SCORE: 26/26` (or higher if you add attacks — add one
that proves an *unproven* agent is refused real work).

```bash
python3 ./slopnet verify
```
Then have a different agent run it too (rule 7).
