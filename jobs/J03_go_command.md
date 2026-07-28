# J03 — `slopnet go "idea"`: the one command

**Where:** the `slopnet` repo. **Size:** large. **Touches:** `slopnet`,
`crew.py`, `CREW.md`, `README.md` (a line, not the rewrite — that's J05).
**Best done after:** J01.

## The goal, exactly

The operator opens Apple Terminal, types one line, answers at most a
couple of plain questions, and watches the work happen:

```bash
slopnet go "a webpage that shows the weather for my town"
```

Everything else — arming the repo, choosing the crew, planning, running
the fleet, gating, merging — happens without another command.

## What `go` must do, in order

1. **Not in a git repo?** Offer, in one plain sentence, to start one here
   (`slopnet init` under the hood). Never touch a directory above.
2. **Repo not armed?** Arm it silently (hooks, register, first day-file).
3. **No crew yet?** Run the setup questions inline — same wizard as
   `slopnet setup`, not a copy of it.
4. **Plan** the idea into `WAVES.md`, then **show the operator the plan
   in plain English** and ask one question: *Run this? (y/n/edit)*.
   `edit` opens `WAVES.md` in `$EDITOR` (default: nano) and re-asks.
   This is the one approval gate — it exists because a plan is cheap to
   fix and a wrong run is expensive.
5. **Run** the waves (existing runner).
6. **Finish with a plain-English report**: what merged, what failed and
   why, and the single most useful next command.

Add `--yes` to skip the approval question (for people who want no
questions at all), and `--wave N` passthrough.

## Rules

- **`go` must be re-runnable.** If the operator runs it twice, nothing is
  duplicated or clobbered: an existing crew is reused, an existing
  `WAVES.md` is offered rather than silently overwritten.
- **Ctrl-C must leave a clean tree.** Interrupt mid-run: worktrees are
  removed, no half-merge, and the register says the run was interrupted.
  Prove this in the acceptance run.
- Every question has an obvious default shown in brackets, e.g.
  `Run this? [y]`. A child pressing Enter must get the sensible thing.
- No new dependencies, no new files beyond what already exists.
- Do not reimplement setup/plan/run — call them.

## Acceptance (run these; paste real output)

```bash
cd $(mktemp -d) && git init -q && slopnet go "a python script that prints the date, with a test" --yes
```
(Use the repo's `./slopnet` path if it isn't installed yet.) A real agent
does the work; the run ends with files merged and the walls green.

```bash
slopnet go "same idea again"
```
Second run must reuse the crew and not clobber the previous plan.

Interrupt a run with Ctrl-C and then show `git status` is clean and
`git worktree list` has no leftovers.
