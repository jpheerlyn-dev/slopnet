# T02 — `checks/`: the six enforcement scripts (the law)

**Where:** the `slopnet` repo. **Model:** large. **Depends on:** T01.
**Read first:** `build/SLOPNET_DESIGN.md` §3 and §3.1.

## The contract every check obeys (non-negotiable)

- File: `checks/<name>.sh`, POSIX sh (`#!/bin/sh`), executable,
  shellcheck-clean.
- Two modes: **default** = examine *staged* changes
  (`git diff --cached --name-only -z`, content via `git diff --cached`);
  **`--all`** = examine the whole tracked tree (used by CI).
- Exit 0 = pass. Exit 1 = fail. On fail print **exactly three lines**,
  nothing else — they will be read by an LLM whose context must not be
  poisoned:
  ```
  RULE: <one sentence — what is forbidden>
  WHY:  <one sentence — what goes wrong otherwise>
  FIX:  <one imperative sentence — the exact next action>
  ```
  If multiple files violate, name at most 3 in the RULE line ("…and 4 more").
- Speed: each check ≤150 ms on a normal laptop for a typical commit;
  the whole suite must stay under one second. No network calls, ever.
- No dependencies beyond git + POSIX coreutils, except where a binary is
  explicitly optional-with-fallback (secrets.sh only).

## The six checks

1. **`secrets.sh`** — if a `gitleaks` binary exists at `.slopnet/bin/gitleaks`
   or on PATH: run it (staged mode: `protect --staged`; `--all`: `detect`)
   with repo config `.gitleaks.toml` (T03 ships it; tolerate its absence).
   Otherwise **fallback regexes** over staged added lines / tree:
   `AKIA[0-9A-Z]{16}`, `ghp_[A-Za-z0-9]{36,}`, `sk-[A-Za-z0-9]{20,}`,
   `-----BEGIN( [A-Z]+)? PRIVATE KEY-----`, and generic
   `(api[_-]?key|secret|token|passwd|password)['"]?\s*[:=]\s*['"][^'"]{12,}`.
   Also: block any staged file named `.env` or `.env.*` except `.env.example`.
2. **`protected-paths.sh`** — read `PROTECTED.txt` (skip blank/`#` lines);
   fail if any staged path starts with a listed prefix. `--all` mode: no-op
   (protection is about *changes*), exit 0.
3. **`naming.sh`** — fail on any staged (or, `--all`, tracked) path where:
   a segment contains spaces; a segment (case-insensitive) is or ends with
   `untitled`, `temp`, `tmp`, `misc`, `stuff`, `copy`, `new-folder`,
   `-old`, `_old`, `-final`, `_final`, `-v2`, `_v2`, `(1)`; the file ends
   `.bak`, `.orig`, `.tmp`; or a **directory** segment contains characters
   outside `[a-z0-9._-]` (files keep their case; conventional names
   README.md, AGENTS.md, HUMANS.md, MAP.md, SLOPNET.md, LICENSE, LOG.md,
   PROTECTED.txt, MANIFEST.sha256, Makefile, Dockerfile are always allowed).
   Then apply extra shell-glob patterns from `banned-names.txt`.
4. **`junk.sh`** — fail on staged paths matching: `.DS_Store`, `Thumbs.db`,
   `__pycache__/`, `*.pyc`, `node_modules/`, `.idea/`, `*.swp`, `*.log`.
   (`--all`: same over tracked files.)
5. **`slop-lint.sh`** — over staged **added** lines
   (`git diff --cached -U0 | grep '^+'`; `--all`: whole files of tracked
   source): fail on
   Python naked handlers `except\s*:\s*(pass|\.\.\.)?\s*$`,
   empty JS/TS catch `catch\s*(\([^)]*\))?\s*{\s*}`,
   and bypass phrases in comments/strings: `simplified version`,
   `in a real implementation`, `placeholder implementation`,
   `left as an exercise`, `would normally`, `for now, just`.
   These patterns are **reimplemented from scratch** — the `grain`
   project has no license; take not one line of its code (its idea
   credits go in a comment header).
6. **`register.sh`** — default mode: ensure `register/YYYY-MM-DD.md`
   (today, local time) exists — create it with a `# Register — <date>`
   header and `git add` it if missing — then exit 0 (this check is
   plumbing, not a wall; the post-commit hook writes the machine lines).
   `--all` mode (CI): for the HEAD commit's author date, fail if no
   `register/<that-date>.md` is tracked.

## Rules

- Names above are final. No extra checks, no config formats beyond the
  two txt files. Header comment in each script: 2 lines — what it blocks
  and which mode does what.
- Everything you commit must pass your own checks.
- Log in `LOG.md`; blockers to `build/PENDING.md`; never guess.

## Acceptance (operator runs these — expect the shown outcome)

```bash
sh -c 'for c in checks/*.sh; do sh "$c" --all || echo "FAIL $c"; done; echo suite-ok'
```
```bash
touch ".DS_Store" && git add -f .DS_Store && sh checks/junk.sh; git rm -f --cached .DS_Store; rm .DS_Store
```
(second command must print the three-line RULE/WHY/FIX block and exit 1)
```bash
time sh -c 'for c in checks/*.sh; do sh "$c"; done'   # total < 1s
```
