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
