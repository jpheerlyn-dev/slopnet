# LOG — sessions on this repo. Newest at bottom.
# 2026-07-28 — Codex

- Completed T01: added the requested skeleton, human guides, orbit guide, register protocol, and operator-editable lists.
- Checked the required line limits, file contents, and scoped file inventory.

# 2026-07-28 — Kimi

- Completed T02: added checks/{secrets,protected-paths,naming,junk,slop-lint,register}.sh — POSIX sh, staged default mode + --all tree mode, 3-line RULE/WHY/FIX failures, no deps beyond git + coreutils (gitleaks optional-with-fallback in secrets.sh only).
- Verified: staged-mode decoys all blocked with exactly 3 lines + exit 1 (junk log file, .env, AWS-style key, private-key header, generic token, -final/_old/-v2/untitled/.bak names, spaces, uppercase dir, naked except, empty catch, bypass phrase); scripts pass their own scans when staged; protected-paths (sealed prefix) and register.sh --all (with/without day-file) verified in a throwaway repo; whole suite ~0.2s.
- naming.sh reads "ends with" against the extensionless stem, so `report-final.md` is caught — the spec's literal wording only caught extensionless names, which would have made the -old/-final/-v2/(1) tokens dead.
- Two --all failures predate T02 and are not fixable from the checks themselves: tracked `.DS_Store` (junk) and literal decoy secrets in `build/T07_redteam.md` (secrets). Rulings requested in build/PENDING.md.
- Accident, disclosed: a naming-decoy test (`printf > README.md`) overwrote T01's README.md, which was never committed, so the exact wording was unrecoverable. Reconstructed from the T01 spec (5 lines: what it is / who for / the two actions / pointers). Operator should review it.
- shellcheck is not installed on this machine, so that part of the contract is unverified; scripts are POSIX sh, `sh -n` clean, and tested against /bin/sh (bash 3.2) — one bash-3.2 parser quirk (quoted var + glob in a case pattern inside $()) was hit in protected-paths.sh and rewritten as a literal prefix-removal test.

# 2026-07-28 — Codex

- Completed T03: added `install.sh`, the marked pre-commit and post-commit shims, parallel `lefthook.yml`, and default-extending `.gitleaks.toml` with an `.env.example` allowlist.
- Pinned Lefthook 2.1.9 and Gitleaks 8.30.1 using official release checksum files; downloaded and locally verified the macOS arm64 artifacts before embedding their hashes.
- Verified: installer arms both hooks and installs both binaries; source syntax and config parse clean; fast runner, isolated post-commit register entry, root refusal, and forced fallback mode all pass.
- Kept Lefthook from auto-replacing the marked shim by using its pinned `--no-auto-install` option; a second installer run confirmed idempotence and preserved both markers.

# 2026-07-28 — Codex

- T04: added `.github/workflows/slopnet.yml` with the law, manifest, and register-audit jobs; CI calls the existing checks directly and uses only `actions/checkout`.
- T04: added `update-manifest.sh` with deterministic sorted-path generation, portable SHA-256 support, and a strict missing-machinery guard.
- Verified shell syntax, diff formatting, and all six checks in `--all` mode. The generator correctly stopped because T05's `doctor.sh` is not present; the blocker is recorded in `build/PENDING.md`, and no incomplete manifest was written.

# 2026-07-28 — Codex

- Completed T05: added read-only `doctor.sh` with the seven ordered checklist lines, fallback-mode handling, quiet manifest verification, CI/register checks, and optional GitHub branch-protection inspection.
- Generated `MANIFEST.sha256` with `./update-manifest.sh`; both `shasum -a 256 -c` and the six `checks/*.sh --all` checks pass.
- Verified the normal doctor run exits 0 with a visible `[??]` branch-protection caveat because GitHub CLI authentication is unavailable. The missing-hook acceptance variant was blocked by the environment's read-only `.git/hooks`; recorded in `build/PENDING.md`.

# 2026-07-28 — Codex

- Completed T06: assembled exactly four files under `adapters/claude-code/` — the README, settings, prompt logger, and protected-path guard.
- Pipe-tested both hooks from a temporary `.claude/` install. Prompt result: `## 15:46 — the human said` followed by `> adapter test`.
- Guard result: deny JSON with `permissionDecision: "deny"` and the reason that `sealed-example` is sealed by the operator. Settings JSON parses and the adapter folder contains exactly four files.

# 2026-07-28 — Codex

- Completed T07: added `build/redteam.sh`, which copies the template into a temporary Git workspace, installs the hooks, makes a legitimate baseline commit, and attempts all twenty attacks with cleanup on exit.
- The two bypass cases run the CI-layer secret and manifest checks after `--no-verify`; attack payloads are assembled from safe fragments so the red-team harness does not trip its own detectors.
- Final scorecard:

```text
BLOCKED 1 .DS_Store
BLOCKED 2 __pycache__/x.pyc
BLOCKED 3 debug.log
BLOCKED 4 .env secret
BLOCKED 5 AWS key
BLOCKED 6 private-key block
BLOCKED 7 notes copy.md
BLOCKED 8 untitled.txt
BLOCKED 9 New Folder/x.txt
BLOCKED 10 report_final_v2.md
BLOCKED 11 main.py.bak
BLOCKED 12 MyStuff/readme.md
BLOCKED 13 naked except
BLOCKED 14 empty catch
BLOCKED 15 shortcut phrase
BLOCKED 16 register auto-restore
BLOCKED 17 sealed path
BLOCKED 18 AWS key (CI-layer)
BLOCKED 19 manifest tamper (CI-layer)
BLOCKED 20 weird name (1).txt
SCORE: 20/20
```

## 2026-07-28 — Claude (Fable 5) — round cleanup
- Harvested T08 FINDINGS.md from the operator's slopnet-step-8 run
  (verdict: "a ten-year-old could easily set this up", 15 min, small model).
- Fixed install.sh root-detection (case-insensitive filesystem bug the
  operator hit). Defanged decoy secret literals in build/T07_redteam.md
  and build/PENDING.md. Wrote resolutions into PENDING.md.
- Regenerated MANIFEST.sha256; ran full checks suite --all; committed the
  whole prototype (T03–T08 work was built but never committed) and pushed.
