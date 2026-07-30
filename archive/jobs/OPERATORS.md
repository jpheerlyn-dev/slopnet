# Archived — original local-first jobs and dispatch notes

## Current state — 2026-07-29

This is a status index, not a new job. Preserve the job briefs as evidence;
do not delete, rename, or silently rerun them.

| Job | Current state | What the next agent should know |
|---|---|---|
| J01–J06 | Implemented and independently verified when merged | They describe the original local-first command path. Their evidence is in the register. |
| J07 | Run completed; it produced findings, not an app | Read `J07_FINDINGS.md` and `register/PENDING_OPERATOR.md`. Do not rerun until the operator schedules the v0.3 repair and proof work. |
| J08 | Explicitly deferred by the operator | Do not start it while the VPS remote runner and one real credentialed-agent proof are still missing. |

The immediate MVP work is not another broad integration: establish one
reviewed VPS agent-runtime path, prove one subscribed coding CLI can edit and
test there, then repeat J07. Docker's strict no-network container gate is
already proven separately; it must not be weakened or repurposed as the
credentialed agent runtime.

## The only active product rule

SlopNet must become easier for a newcomer at every step. A change belongs in
the current MVP only if it helps a person with a VPS and one coding plan get
from “I want a thing built” to a proved result with fewer hidden choices,
fewer machine-specific steps, and clearer recovery when something fails.

The next implementation brief must therefore cover one guided VPS setup and
one real agent proof before it covers more providers, a multi-agent fleet, or
any Hermes, OpenClaw, or Buzz integration. Until an operator names and
schedules that brief, no job in this folder is active work.

## Original J01–J07 sequence

**The goal these jobs were written to deliver:** **REDACTED** opens Apple Terminal, types

```bash
slopnet go "build me a thing"
```

…and SlopNet picks the crew, plans the work, runs several coding agents
in parallel, and merges only what passes. No manual prompting, no flags
to remember, no editing config by hand.

That local-first sequence is historical evidence, not the finished product
direction. The current MVP policy is VPS-first; see `SLOPNET.md`.

If an operator explicitly reschedules one of these historical briefs, hand it
to a coding agent as its whole prompt, one job per session, in wave order.
Every brief is self-contained.

## How to dispatch a rescheduled historical brief

Open a coding agent in the **slopnet** repo and paste:

> Read `AGENTS.md`, `CREW.md`, and `jobs/<the job file>`. Do exactly that
> job. Run its acceptance commands yourself and paste the real output
> into `register/<today>.md` with `slopnet sign`. Anything you cannot
> resolve goes to `register/PENDING_OPERATOR.md` — never guess. When you
> finish, ask a *different* agent to run `slopnet verify` (rule 7).

…then the full text of the job file.

## Historical waves

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
2. Never weaken a check to make a job pass. If a check blocks you, that is
   the check working — fix your work.
3. Prove it by running it. Paste real terminal output into the register;
   an agent's summary is not evidence.
4. Nothing merges without the checks and (where they exist) real tests.
5. If a job turns out to be wrong, say so in `PENDING_OPERATOR.md` and
   stop. An honest blocker beats a confident mess.
