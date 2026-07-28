# PENDING — blockers and questions for the operator. Newest at bottom.

## 2026-07-28 — Kimi (T02)

1. `.DS_Store` is tracked in git (came in with the initial commit).
   `checks/junk.sh --all` fails until it is untracked and the removal is
   committed: `git rm --cached .DS_Store`. (Your T02 acceptance step 2
   already does the untracking; it just needs to land in a commit.)
2. `build/T07_redteam.md` lines 26 and 28 contain literal decoy secrets
   (`sk-aaaaaaaa…`, `-----BEGIN PRIVATE KEY-----`). `checks/secrets.sh
   --all` cannot tell they are fake, so it fails. Ruling needed: reword
   the decoys so they do not match (describe them, or have the red-team
   script build them by concatenation at runtime), or exclude `build/`
   from secret scanning (not recommended — secrets hide anywhere).
3. `suite-ok` on a fresh checkout needs a commit containing `checks/` and
   `register/2026-07-28.md` (register.sh --all verifies a day-file for
   HEAD's author date). All T02 files are staged and ready; I did not
   commit because git mutations need your go-ahead.
