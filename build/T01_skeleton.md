# T01 — repo skeleton + the five human files

**Where:** the `slopnet` repo root. **Model:** small–medium.
**Read first:** `build/SLOPNET_DESIGN.md` (§2 and §3).

## Context (compressed)

SlopNet is a GitHub template repo that makes AI-agent workspaces
structurally slop-proof. Two user actions: "Use this template" +
`./install.sh`. Three pillars: Walls (mechanical checks), Register
(automatic paper trail), Orbit (new ideas live in satellite repos).
Red lines: ten-year-old simple · swamp-impossible · CEO-grade, zero upkeep.

## Deliverables (create exactly these; nothing else)

1. **`README.md`** — five lines, no more:
   what SlopNet is (1 line) · who it's for (1 line) · the two actions
   (2 lines: template button, `./install.sh`) · "Rules for agents:
   AGENTS.md. Everything else: MAP.md." (1 line).
2. **`AGENTS.md`** — ≤40 lines. Contents in this order: one-line purpose;
   "the machinery in `checks/` is the law — this file only points";
   the six rules (never invent/change names — operator-only; never
   delete — archive; no junk files; no empty folders; new ideas go in
   orbit repos per SLOPNET.md, never in this trunk; sign LOG-style
   entries in the register before finishing); a short "if you are a
   small model" block (touch only files in your brief; on unexpected
   failure STOP and log; never fix by disabling); pointers to MAP.md,
   SLOPNET.md, register/README.md.
3. **`HUMANS.md`** — ≤30 lines: the prompt format
   (GOAL / WHERE / DON'T / CHECK), five habits (one theme per prompt;
   read the register first; name things yourself; small models get
   small tasks; paste errors verbatim), and the human's jobs (naming
   verdicts, clicking the real app, answering PENDING items).
4. **`MAP.md`** — a stub with three sections and one line each:
   "Your app goes here (add a row per feature: page → file → backend)",
   "Ideas in orbit → SLOPNET.md", "Rules → AGENTS.md · Record → register/".
5. **`SLOPNET.md`** — copy the orbit law from `build/SLOPNET_DESIGN.md`
   §2 pillar 3, plus: the five orbit rules, an EMPTY registry table
   (header row only: Name | Repo | What it is | Calls | Status |
   Last known good), the four statuses, the spin-up recipe, the
   graduation checklist, and the two idea-repo templates (README +
   AGENTS) — all of which exist already in **REDACTED**'s SLOPNET.md;
   reproduce the same structure generically (no **REDACTED** references).
6. **`register/README.md`** — the protocol: one file per day
   (`YYYY-MM-DD.md`); machine lines are appended automatically by a
   post-commit hook (T03 builds it); humans/agents add prose entries
   `## HH:MM — <who> did`; past entries are never edited; questions go
   to `register/PENDING_OPERATOR.md` (create it with a two-line header:
   Open / Ruled).
7. **`.gitignore`** — exactly: `.slopnet/`, `.env`, `.env.*`,
   `!.env.example`, `.DS_Store`, `__pycache__/`, `*.pyc`,
   `node_modules/`, `*.log`, `.idea/`, `.vscode/`, `*.swp`.
8. **`PROTECTED.txt`** — header comment ("One path-prefix per line.
   Commits touching these paths are blocked locally. The operator edits
   this file; agents never do.") + commented-out examples
   (`# core/sealed-feature/`), no active entries.
9. **`banned-names.txt`** — header comment ("Extra banned name patterns,
   one per line, shell-glob style. Operator-editable.") + no active
   entries (defaults live in the check itself, T02).

## Rules

- Do not create `checks/`, `hooks/`, CI files, or any file not listed —
  later tasks own those. No empty folders.
- Wording throughout must pass the ten-year-old test: short sentences,
  no jargon without a one-word gloss.
- Log your session in `LOG.md`; blockers to `build/PENDING.md`.

## Acceptance (operator runs these)

```bash
wc -l README.md AGENTS.md HUMANS.md   # ≤5-ish, ≤40, ≤30 body lines
```
```bash
ls register/ && cat .gitignore PROTECTED.txt banned-names.txt
```
- A non-coder reading README.md alone knows the two actions to take.
