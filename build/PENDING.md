# PENDING — blockers and questions for the operator. Newest at bottom.

## 2026-07-28 — Kimi (T02)

1. `.DS_Store` is tracked in git (came in with the initial commit).
   `checks/junk.sh --all` fails until it is untracked and the removal is
   committed: `git rm --cached .DS_Store`. (Your T02 acceptance step 2
   already does the untracking; it just needs to land in a commit.)
2. `build/T07_redteam.md` lines 26 and 28 contained literal decoy secrets
   (an "sk-" style key and a five-dash BEGIN PRIVATE KEY banner —
   defanged in this file too, same reason). `checks/secrets.sh
   --all` cannot tell they are fake, so it fails. Ruling needed: reword
   the decoys so they do not match (describe them, or have the red-team
   script build them by concatenation at runtime), or exclude `build/`
   from secret scanning (not recommended — secrets hide anywhere).
3. `suite-ok` on a fresh checkout needs a commit containing `checks/` and
   `register/2026-07-28.md` (register.sh --all verifies a day-file for
   HEAD's author date). All T02 files are staged and ready; I did not
   commit because git mutations need your go-ahead.

## 2026-07-28 — Codex (T04)

1. `doctor.sh` is not present, but T04 requires it in the exact machinery
   set covered by `MANIFEST.sha256`. T05 owns that file, so I did not invent
   or partially implement it.
2. Consequently, `./update-manifest.sh` stops with the missing-file message
   and does not generate `MANIFEST.sha256`. After T05 adds `doctor.sh`, run
   the generator and commit the manifest in the same commit.

## 2026-07-28 — Codex (T05)

1. The T04 blocker is resolved: `doctor.sh` now exists and
   `MANIFEST.sha256` was generated and verified.
2. The missing-hook acceptance variant could not be run because this
   environment denied moving `.git/hooks/pre-commit` to `/private/tmp`.
   The hook was not changed; the normal doctor run and all non-mutating
   validations pass.

## 2026-07-28 — Claude (round cleanup) — resolutions

- Kimi item 1: RESOLVED — `.DS_Store` is no longer tracked; nothing to commit.
- Kimi item 2: RULED per Kimi's own recommendation — decoys defanged in
  the brief (assembled at runtime by redteam.sh); `build/` stays scanned.
- Kimi item 3 / Codex T04 item: RESOLVED — everything commits this round.
- New fix: `install.sh` refused to run from the repo root when the user
  cd'd via a different letter-case path (macOS case-insensitive
  filesystem vs string comparison). Root test now uses
  `git rev-parse --show-prefix`. This bug cost the operator real
  frustration — logged as v0.2 evidence for the no-manual-commands rule.
