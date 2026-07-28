# CREW.md — putting a fleet of agents to work

SlopNet's walls stop bad work landing. The crew is how good work gets
made: one agent **plans**, several agents **write code at the same time**,
and the walls plus your own tests decide what is allowed to stay.

Three commands, in order:

```bash
slopnet setup
```
Meets your crew. It looks for coding agents you are already logged into
(claude, codex, gemini, hermes, cursor-agent) and any API keys in your
shell, then asks three plain questions: who plans, who writes code, and
what command runs your tests. Saved to `.slopnet/crew.json` — edit it by
hand any time.

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

## Honest limits

The crew drives coding agents through their non-interactive "do one job"
mode. Flags differ between tools and change between versions; if an agent
does nothing, open `.slopnet/crew.json` and fix its `command` line — the
`{prompt}` placeholder is where the task text goes. API workers default
to a sensible model; set `"model"` in the same file to choose your own.
