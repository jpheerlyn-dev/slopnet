# Jobs — the run order to "type one command and it works"

**The goal these jobs deliver:** **REDACTED** opens Apple Terminal, types

```bash
slopnet go "build me a thing"
```

…and SlopNet picks the crew, plans the work, runs several coding agents
in parallel, and merges only what passes. No manual prompting, no flags
to remember, no editing config by hand.

Hand each job below to a coding agent as its whole prompt, one job per
session, in wave order. Every job is self-contained.

## How to dispatch

Open a coding agent in the **slopnet** repo and paste:

> Read `AGENTS.md`, `CREW.md`, and `jobs/<the job file>`. Do exactly that
> job. Run its acceptance commands yourself and paste the real output
> into `register/<today>.md` with `slopnet sign`. Anything you cannot
> resolve goes to `register/PENDING_OPERATOR.md` — never guess. When you
> finish, ask a *different* agent to run `slopnet verify` (rule 7).

…then the full text of the job file.

## Waves

| Wave | Job | What it delivers | Size |
|---|---|---|---|
| 1 | `J01_agent_adapters.md` | every CLI you subscribe to, driven correctly and proven | **large** |
| 1 | `J02_subscription_router.md` | Kimi + zAI coding plans reachable from the crew | medium (needs `RESEARCH_subscriptions.md` first) |
| 2 | `J03_go_command.md` | `slopnet go "idea"` — the one-command path | **large** |
| 2 | `J04_live_progress.md` | a live terminal view while the fleet works | medium |
| 3 | `J05_readme.md` | the public README a child can follow | medium |
| 3 | `J06_first_run.md` | first-run polish: `slopnet` alone teaches itself | small–medium |
| 4 | `J07_real_world_test.md` | build a real small app with the fleet, end to end | **large** |

Research prompts (paste into a deep-research agent, save the answer
where the job says): `RESEARCH_subscriptions.md`.

## Rules that apply to every job

1. Never rename anything. Naming is the operator's.
2. Never weaken a wall to make a job pass. If a check blocks you, that is
   the check working — fix your work.
3. Prove it by running it. Paste real terminal output into the register;
   an agent's summary is not evidence.
4. Nothing merges without the walls and (where they exist) real tests.
5. If a job turns out to be wrong, say so in `PENDING_OPERATOR.md` and
   stop. An honest blocker beats a confident mess.
