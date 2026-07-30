# J07 — build something real, with the whole fleet

> **State: executed on 2026-07-29; findings, not an app, resulted.** Read
> `J07_FINDINGS.md` and `register/PENDING_OPERATOR.md`. Do not rerun this
> exam until the operator schedules the VPS agent-proof repair work.

**Where:** a fresh folder OUTSIDE the slopnet repo (an orbit, per
`SLOPNET.md`). **Size:** large. **Do this last** — it is the exam, and
its findings are the v0.3 backlog.

## Why this job exists

Everything so far has been proven with fake agents, tiny probes, and
scratch repos. None of that proves a real person can build a real thing.
This job does the real run: several paid coding agents, working in
parallel, on one actual small app, judged by real tests.

## What to do

1. Pick a genuinely small but real project — the operator's choice; if
   they haven't said, use: *a command-line tool that takes a folder of
   photos and writes an HTML contact sheet.* Small, testable, obviously
   useful, no API keys or network needed.
2. In a fresh directory, with nothing but SlopNet installed:
   ```bash
   slopnet go "<the project, described in one plain sentence>"
   ```
3. Let it run. **Do not help it.** Do not hand-edit files, do not fix
   prompts mid-run, do not re-plan to make it look better. The point is
   to see what actually happens.
4. When it stops, whatever the outcome: run the program, run its tests,
   read the register.

## What to write down

`archive/jobs/J07_FINDINGS.md`, honest and chronological:

- The plan the planner produced (paste `WAVES.md`).
- Which agent did which task, how long each took, what merged, what
  failed and exactly why.
- **Did the thing actually work?** Run it. Paste the output.
- Every moment a human would have been confused, lost, or annoyed.
- Cost, if the agents report it, or a note that they don't.
- Total check-clock time, and how much of it needed a human.
- One-line verdict: *could a beginner have done this alone?*

## Rules

- **Do not fix the tool during this job.** Findings only. A tester who
  repairs the track invalidates the test. Fixes are the operator's to
  schedule as v0.3.
- Every failure gets recorded with its real message, including
  embarrassing ones. An unflattering finding is the most valuable thing
  this job can produce.
- Do not touch the slopnet repo except to add `archive/jobs/J07_FINDINGS.md` and
  a register entry.
- If the run destroys nothing but produces nothing either, that is a
  *result*, not a failure of the job — write it up plainly.

## Acceptance

`archive/jobs/J07_FINDINGS.md` exists, contains real pasted output (not
summaries), and answers the verdict question. The register carries the
session entry. A different agent runs `slopnet verify` afterwards to
confirm the slopnet repo itself is still green (rule 7).
