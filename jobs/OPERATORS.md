# Jobs — current queue

## Active work

**Guided VPS setup reached the live **REDACTED** Codex proof, which is blocked by
the VPS user-namespace policy.**

The implementation is deliberately narrow: Linux VPS plus one Codex CLI. It
creates a private non-root runtime account without changing SSH policy, asks
before installation and device login, checks private credential storage, and
runs the disposable edit proof. The live VPS result decides whether it earns
the next step.

## Current position — no file-opening required

| Area | State | Evidence or next action |
|---|---|---|
| Original local SlopNet engine (J01–J06) | Done; historical | The briefs and research live in `archive/jobs/`. They are not the VPS product. |
| Whole-fleet real-world exam (J07) | Done; no app was built | Every available worker failed its real proof. Raw chronology: `archive/jobs/J07_FINDINGS.md`; rerun only after the VPS proof. |
| Docker VPS containment gate | Done on **REDACTED** | Non-root, offline, read-only gate passed. Full output: `register/2026-07-29.md`. |
| Guided VPS setup and one Codex proof | Blocked by **REDACTED** sandbox policy | Login and private credentials work; bubblewrap installed, but the non-root account cannot create its required user namespace. No host security setting was changed. |
| J08 hosted brains / more providers / Hermes / OpenClaw / Buzz | Deferred | Do not start before the preceding proof succeeds. |
| GitHub branch protection | Incomplete | Configure `law`, `manifest`, `register-audit`, and `container` as required checks after GitHub authentication is restored. |

## The product rule

SlopNet is for a person who wants software made, not a person who wants to
learn deployment, agent flags, credential files, Docker, or Git. A change is
in scope only if it makes the path from one VPS plus one coding subscription
to a proved result shorter, safer, or easier to understand.

## Archive

`archive/jobs/` contains every completed, deferred, failed, and research job
document intact. `archive/reference/` contains retired design and companion
notes. They are preserved evidence, not a queue. Do not move them back, edit
history, or dispatch a brief from there unless the operator explicitly
schedules it again.

## Dispatch rule

For a newly scheduled job, give one agent the complete named brief. It must
read `AGENTS.md` and `CREW.md`, run its acceptance commands, sign the current
register, file unresolved questions in `register/PENDING_OPERATOR.md`, and
obtain a countersign from a different agent with `slopnet verify`.
