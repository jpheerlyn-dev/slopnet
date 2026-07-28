# T07 — `build/redteam.sh`: 20 slop attacks, 0 may land

**Where:** the `slopnet` repo. **Model:** medium. **Depends on:** T02–T05.

## What it is

The acceptance gate for the Walls: a script that plays a careless or
malicious agent, attempts twenty classic slop moves against a fresh
SlopNet workspace, and demands every one is blocked. This is Milestone
M1's exit test from the design.

## Deliverable

**`build/redteam.sh`** — bash. Creates a temp dir, copies the template in
(everything except `.git`, `build/`, `LOG.md`), runs `git init` +
`./install.sh`, makes one legitimate baseline commit, then attempts each
attack below as a real staged commit. Score line per attack:
`BLOCKED <n> <name>` or `LANDED <n> <name>`. Final line:
`SCORE: <blocked>/20`. Exit 0 only at 20/20. Clean up the temp dir.

The twenty attacks (commit attempts unless marked CI-layer):

1. Commit `.DS_Store`.
2. Commit `__pycache__/x.pyc`.
3. Commit `debug.log`.
4. Commit `.env` containing `API_KEY=sk-aaaaaaaaaaaaaaaaaaaaaaaa`.
5. Commit `config.py` containing `AKIA` + 16 uppercase chars (fake AWS key).
6. Commit `deploy.pem` containing a `-----BEGIN PRIVATE KEY-----` block.
7. Commit `notes copy.md` (space + banned word).
8. Commit `untitled.txt`.
9. Commit dir `New Folder/x.txt`.
10. Commit `report_final_v2.md`.
11. Commit `main.py.bak`.
12. Commit dir `MyStuff/readme.md` (uppercase dir segment).
13. Commit `handler.py` containing `except:\n    pass`.
14. Commit `api.js` containing `catch (e) {}`.
15. Commit `service.py` containing `# simplified version for now`.
16. Commit a source file with NO register day-file staged and the
    register dir deleted first — expect the check to auto-restore/create
    today's file (this one PASSES by the file reappearing, score it
    BLOCKED if the commit lands *with* a register file present).
17. Add `sealed/` to PROTECTED.txt (as the operator), then commit a
    change to `sealed/core.py` — expect block.
18. Bypass attempt: repeat attack 5 with `git commit --no-verify` — the
    commit WILL land locally; then run `sh checks/secrets.sh --all` and
    score BLOCKED only if it fails (proving the CI layer catches what
    the hook missed). Label: `(CI-layer)`.
19. Tamper: append a comment to `checks/junk.sh`, commit with
    `--no-verify`, then run the manifest verify command — score BLOCKED
    only if verification fails. Label: `(CI-layer)`.
20. Commit `weird name (1).txt`.

## Rules

- The script must not touch the real repo's state — temp dir only.
- If any attack LANDS, do not "fix" the redteam script to look away —
  file the failing check as a PENDING item and stop. The score is the
  truth; SlopNet exists because agents fudge scores.
- Log in `LOG.md` with the full scorecard pasted.

## Acceptance (operator runs it)

```bash
bash build/redteam.sh
```
Expected: twenty `BLOCKED` lines, `SCORE: 20/20`, exit 0.
