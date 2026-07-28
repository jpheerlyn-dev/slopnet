# T05 — `doctor.sh`: the green-tick checklist

**Where:** the `slopnet` repo. **Model:** medium. **Depends on:** T03, T04.
**Read first:** `build/SLOPNET_DESIGN.md` §2 layer 3 and §4 red line 1.

## What it is

The one command a beginner runs to know they're safe. Output is a short
checklist in plain sentences — a ten-year-old must understand every line.
Format per line: `[OK]` or `[!!]`, a space, one sentence. No jargon
without a one-word gloss, no stack traces, no walls of text.

## Deliverables

**`doctor.sh`** — bash, read-only (changes nothing), checks in order:

1. Hooks armed: `.git/hooks/pre-commit` and `post-commit` exist and
   contain `slopnet-armed`. FIX line if not: "Run ./install.sh".
2. Engine mode: `.slopnet/bin/lefthook` present and no `.slopnet/fallback`
   → "[OK] Fast engine running." Else "[OK] Fallback mode — slower, same
   protection." (fallback is OK, not [!!]).
3. Law present: all six `checks/*.sh` exist and are executable.
4. Manifest verifies: `shasum -a 256 -c MANIFEST.sha256` quietly.
5. CI present: `.github/workflows/slopnet.yml` exists.
6. **Branch protection** (the only non-file wall): if the `gh` CLI is
   available and authenticated, query
   `gh api repos/{owner}/{repo}/branches/<default>/protection` — [OK] if
   required status checks include the CI jobs; otherwise `[!!]` with ONE
   line: "Turn on branch protection: Settings → Branches → require the
   slopnet checks. This is the wall nobody can climb." If `gh` is absent,
   print the same instruction prefixed "[??] Can't check from here —".
7. Register alive: `register/` exists and today's or a prior day-file is
   tracked.

Exit 0 only if every line is [OK] (the [??] gh-absent case exits 0 with a
visible caveat; `[!!]` exits 1).

## Rules

- Read-only. No network beyond the optional `gh` call. No new names.
- Every sentence passes the ten-year-old test. Log in `LOG.md`.

## Acceptance (operator runs these)

```bash
./doctor.sh; echo "exit=$?"
```
(fresh armed repo: all [OK] except possibly branch protection — and that
line alone must tell you exactly what to click)
```bash
mv .git/hooks/pre-commit /tmp/pc && ./doctor.sh; echo "exit=$?"; mv /tmp/pc .git/hooks/pre-commit
```
(must show the [!!] hooks line with "Run ./install.sh" and exit 1)
