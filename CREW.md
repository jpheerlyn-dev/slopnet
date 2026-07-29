# CREW.md — putting a fleet of agents to work

> **Current status: local-engine reference, not the VPS-first beginner
> product.** It documents the existing planner and fleet behaviour. The
> first guided VPS Codex proof is awaiting live verification; the general
> credentialed agent runtime described in `SLOPNET.md` does not exist yet, so
> do not give this file to a newcomer as setup instructions.

SlopNet's walls stop bad work landing. The crew is how good work gets
made: one agent **plans**, several agents **write code at the same time**,
and the walls plus your own tests decide what is allowed to stay.

The everyday path is one command:

```bash
slopnet go "a small web page that shows today's weather"
```

It starts or arms the repository, runs the same setup wizard when there
is no saved crew, asks an agent for a plan, shows that plan, and asks
`Run this? (y/n/edit) [y]` before calling the existing runner. `edit`
opens `WAVES.md` in `$EDITOR` (or `nano`). Use `--yes` to accept the
sensible defaults without questions, or `--wave N` to pass one wave to
the runner. Running `go` again reuses the crew and offers the existing
`WAVES.md`; it never silently replaces either one.

If a run is interrupted, SlopNet stops the active agents, removes their
disposable worktrees and attempt branches, aborts any half-merge, and
records the interruption before returning to a clean tree.

The three commands underneath `go` remain available separately:

Three commands, in order:

```bash
slopnet setup
```
Meets your crew. It looks for installed coding-agent CLIs
(claude, codex, gemini, grok, kimi, hermes, cursor-agent), any API keys in
your shell, and non-CLI coding plans that the research report verified.
Finding a CLI is not a login claim: the required edit proof decides whether
it can safely receive real work.
(today: **zAI GLM** via Claude Code when `ZAI_API_KEY` is set). Billing
caveats from that report are printed in plain English before you pick.
Each selected agent then has to create one exact file in a throwaway git
repo. The command, 900-second default timeout, proof result, reason, date,
and a `providers` section (env-var names and endpoints only — never
tokens) are saved to `.slopnet/crew.json` — edit the timeout by hand any
time.

```bash
slopnet plan "a small web page that shows today's weather"
```
The planner writes **WAVES.md**: waves of tasks, in plain English, each
naming the files it owns. Tasks in the same wave run at the same time, so
they are never allowed to own the same file. A plan that breaks the
contract is rejected and the planner gets one chance to fix it — a bad
plan never runs. **Read WAVES.md before running it.** It is meant to be
readable; if it isn't, say so and re-plan.

```bash
slopnet run          # or: slopnet run --wave 2
```
Each task gets its own private copy of the repo (a git worktree) and its
own coding agent. They work in parallel. Then, for each attempt:

1. **The walls judge it** — the same checks that guard your commits.
2. **Your tests judge it** — the real command, which must exit 0.
3. Only if both pass is the work merged into your tree. Anything else is
   thrown away, and the run tells you exactly why.

The register records every run automatically.

## The rules that make this safe

- **An agent never says whether its own work is good.** Tests and walls do.
- **A test command that cannot fail is refused.** `true`, `exit 0`,
  `echo OK`, or anything ending `|| true` would launder bad work as
  proven, so SlopNet won't accept it. (Blank is fine — then the walls
  judge alone, and SlopNet says so out loud.)
- **Failed work is discarded, never merged.** Its branch is deleted; your
  tree is untouched.
- **A dirty tree stops the run** — the crew only starts from a clean
  commit, so nothing of yours can be lost.
- **Same wave, different files.** Enforced when the plan is parsed.

## If something goes wrong

Every failure line says why: a wall's RULE, a test's last lines, or a
merge conflict (that branch is kept so you can look). Nothing fails
silently. Re-run a single wave with `--wave N` after fixing the cause.

## Agent commands and proof on this machine

These are the installed tools' real unattended edit commands, checked
from their own help and then tested by asking each one to write
`probe.txt`. `{prompt}` is shell-quoted by the runner.

| Agent | Command used for a normal prompt | Edit permission | Prompts over 100 KiB | Probe on 2026-07-28 |
|---|---|---|---|---|
| `claude` | `claude --dangerously-skip-permissions -p {prompt}` | explicit bypass flag | stdin from a temporary file | **UNPROVEN** — OAuth session expired |
| `codex` | `codex exec --sandbox workspace-write {prompt}` | workspace-only sandbox | stdin from a temporary file | **PROVEN** — wrote the file in 10s |
| `gemini` | `gemini --yolo -p {prompt}` | `--yolo` | stdin from a temporary file | **UNPROVEN** — no authentication method configured |
| `grok` | `grok --permission-mode bypassPermissions -p {prompt}` | explicit bypass mode | `--prompt-file` | **PROVEN** — wrote the file in 5s |
| `kimi` | `kimi -p {prompt}` | prompt mode itself uses `auto` permission | temporary file referenced by the prompt | **PROVEN** — wrote the file in 11s |
| `hermes` | `hermes -z {prompt}` | one-shot mode auto-bypasses approvals | temporary file referenced by the prompt | **PROVEN** — wrote the file in 13s |

On this Mac, Codex, Grok, Kimi, and Hermes are proven. Claude and Gemini
are installed but are not trusted until the operator logs them in and
runs `slopnet setup` again. An unproven agent is refused by `slopnet
plan` and `slopnet run`; a process that exceeds its configured timeout
fails plainly with `agent timed out after Ns`.

Prompt files are removed after each attempt and task briefs are never
truncated. API workers default to a sensible model; set `"model"` in
`.slopnet/crew.json` to choose your own.

## Non-CLI subscriptions (env-cli)

Some coding plans ship no CLI of their own. The research report
(`archive/jobs/RESEARCH_subscriptions_REPORT.md`) is the only source for how
they join the fleet:

| Plan | How SlopNet reaches it | Host CLI | Env (token via `$VAR`) | Covers terminal? |
|---|---|---|---|---|
| **Kimi coding plan** | Its own CLI (`kimi`) | — | login via `kimi login` | **yes** — membership quota |
| **zAI GLM coding plan** | `env-cli` worker `zai-glm` | `claude` | `ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic`, `ANTHROPIC_AUTH_TOKEN=$ZAI_API_KEY`, model defaults GLM-4.7 / GLM-4.5-Air | **yes** — Coding Plan quota, not cash balance |

`env-cli` sets those variables for **one subprocess only**. Tokens are
never written to `.slopnet/`, never printed, never put in the register.
Auth/rate-limit failures use the report's §7 strings so you see
`[!!] kimi — not logged in` rather than a generic exit code.
