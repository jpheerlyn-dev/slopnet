# Jobs — current queue

## Active work

**Guided VPS setup completed the live Codex proof on a tested Ubuntu VPS.**

The implementation remains deliberately narrow: Linux VPS plus one Codex CLI.
It creates a private non-root runtime account without changing SSH policy,
asks before installation and device login, checks private credential storage,
and runs the disposable edit proof. On Ubuntu 24.04 it offered the
documented Bubblewrap-only AppArmor profile instead of disabling the global
user-namespace restriction. That upstream profile gives the setup executable
the permissions it needs, then drops the sandbox child into a
capability-denying profile. Codex then wrote the disposable file in 16 seconds
and SlopNet removed the proof workspace.

## Current position — no file-opening required

| Area | State | Evidence or next action |
|---|---|---|
| Original local SlopNet engine (J01–J06) | Done; historical | The briefs and research live in `archive/jobs/`. They are not the VPS product. |
| Whole-fleet real-world exam (J07) | Done; historical failure | Every available worker failed its real proof. Raw chronology: `archive/jobs/J07_FINDINGS.md`; a new full-fleet run needs an explicit operator brief after the first real project flow. |
| Docker VPS containment gate | Done on tested VPS | Non-root, offline, read-only gate passed. Full output: `register/2026-07-29.md`. |
| Guided VPS setup and one Codex proof | Done on tested VPS | Private non-root credential store confirmed; Ubuntu's Bubblewrap-only profile retained the global restriction and denies child capabilities; Codex wrote the disposable file in 16s and the proof was removed. |
| Mac control app | v0.6 ready to install; live first-project proof pending | Dock app keeps setup inside its own console (no Terminal automation), has Settings-based connection/tool controls, one growing multi-line request box, and private local Markdown request history. Settings can now inspect and, with two confirmations, install/test an optional server-only Llama.cpp GGUF helper under `slopnet`; its draft is offline and must be approved before the plan-only project helper uses it. A live first project and first local-model install remain separate proofs. |
| J08 hosted brains / more providers / Hermes / OpenClaw / Buzz | Deferred | Do not start before the preceding proof succeeds. |
| GitHub branch protection | Failed direct-push enforcement test | GitHub accepted direct pushes to `main` while reporting all four required checks as “expected.” Record the exact bypass in `register/PENDING_OPERATOR.md`; restore a non-bypassable pull-request/status-check path before release. |

## The product rule

SlopNet is for a person who wants software made, not a person who wants to
learn deployment, agent flags, credential files, Docker, or Git. A change is
in scope only if it makes the path from one VPS plus one coding subscription
to a proved result shorter, safer, or easier to understand.

## Immediate next proof

Use the Mac app after VPS setup succeeds. Choose the first project folder name
and give it one plain-language request. SlopNet must create only that project
and make a plan with the already-proved Codex app. Confirm that no coding agent
runs from the app's plan-only step; record the actual plan before scheduling
the separate explicit approval/run step, additional providers, or a J07 rerun.

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
