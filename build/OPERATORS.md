# SlopNet build — operator's run order

You dispatch these tasks to coding agents, one task per session, in wave
order. Each `T0x_*.md` brief is **self-contained** — paste the whole file
as the agent's prompt (plus the one context line under "how to dispatch").
The end state: SlopNet v0.1 exists, proven, and becomes the template for
porting **REDACTED** into ****REDACTED**** (Wave 4).

## Wave 0 — you, by hand (10 minutes)

1. Create a **private** GitHub repo named `slopnet` on your account.
2. Clone it locally, next to **REDACTED** (not inside it).
3. Copy into it: this whole `slopnet_build/` folder **as `build/`**, plus
   `SLOPNET_DESIGN.md` from the **REDACTED** root **into `build/`**.
4. Create an empty `LOG.md` at the repo root containing one line:
   `# LOG — sessions on this repo. Newest at bottom.`
5. Commit and push: `git add -A && git commit -m "Build kit" && git push`.
6. In **REDACTED**'s `SLOPNET.md` registry, add the row:
   `| slopnet | github.com/<you>/slopnet | the framework itself | n/a | cooking | — |`

## How to dispatch a task

Open a coding agent session **in the slopnet repo checkout** and paste:

> Read `build/SLOPNET_DESIGN.md` first — it is the design authority.
> Then do exactly the task below. Log your session in `LOG.md` before
> finishing. Blockers and questions go in `build/PENDING.md` — never guess.

…followed by the full text of the task brief.

## The waves

| Wave | Task | What it builds | Model size | Depends on |
|---|---|---|---|---|
| 1 | `T01_skeleton.md` | repo skeleton + the five human files + .gitignore | small–medium | Wave 0 |
| 1 | `T02_checks.md` | `checks/` — the six enforcement scripts (the law) | **large** | T01 |
| 1 | `T03_install_hooks.md` | `install.sh`, git-hook shims, `lefthook.yml`, `.gitleaks.toml` | medium–large | T02 |
| 1 | `T04_ci_manifest.md` | CI workflow + `MANIFEST.sha256` + regen script | medium | T02, T03 |
| 1 | `T05_doctor.md` | `doctor.sh` — the green-tick checklist | medium | T03, T04 |
| 2 | `T06_claude_adapter.md` | `adapters/claude-code/` (ported from **REDACTED**, source embedded) | small–medium | T01 |
| 2 | `T07_redteam.md` | `build/redteam.sh` — 20 slop attacks, must go 0-for-20 | medium | T02–T05 |
| 3 | `T08_classroom_test.md` | fresh-eyes walkthrough + `build/FINDINGS.md` | **small on purpose** | all of Wave 1–2 |
| 4 | `T09_**REDACTED**` | `**REDACTED**` — **runs inside **REDACTED**, not slopnet** | **large** | v0.1 proven; naming audit ruled |

## Your duties per task (they are short but non-optional)

- **Verify acceptance yourself.** Every brief ends with acceptance
  commands. Run them. An agent's summary saying "done" is not evidence —
  that rule is the reason SlopNet exists.
- **Read `LOG.md` and `build/PENDING.md` before dispatching the next
  task.** Answer PENDING items; unanswered questions become guesses.
- **Never let an agent rename anything.** Names in the briefs are final
  unless you change them yourself.
- If a task fails twice with the same agent, stop, read its LOG entry,
  and either fix the blocker or bring the brief back to a stronger model.

## Wave 4 prerequisites (the **REDACTED** gate)

Do not dispatch T09 until: (a) T07's red-team scores 20/20, (b) T08's
findings are folded in, and (c) **the **REDACTED** naming audit is ruled** —
v2.00 writes names into stone, so the verdicts must exist first. The
naming audit is still an open item in **REDACTED**'s
`register/PENDING_OPERATOR.md`.
