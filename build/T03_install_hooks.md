# T03 — `install.sh`, git-hook shims, `lefthook.yml`, `.gitleaks.toml`

**Where:** the `slopnet` repo. **Model:** medium–large. **Depends on:** T02.
**Read first:** `build/SLOPNET_DESIGN.md` §3 and §3.1.

## Deliverables

1. **`install.sh`** — bash, zero dependencies beyond git/curl, idempotent
   (safe to re-run), never touches anything outside the repo:
   - Refuse politely if not run from a git repo root.
   - Copy `hooks/pre-commit` and `hooks/post-commit` into `.git/hooks/`
     (chmod +x). Each installed shim must contain the marker comment
     `# slopnet-armed` (doctor.sh greps for it).
   - Try to fetch **pinned** `lefthook` and `gitleaks` release binaries
     for the current OS/arch into `.slopnet/bin/` — versions and their
     sha256 sums are variables at the top of the script; verify the
     sha256 after download; on ANY failure (offline, bad sum) print one
     calm line ("Running in fallback mode — slower, same protection.")
     and write the flag file `.slopnet/fallback`.
   - Finish by running `./doctor.sh` if it exists (T05), else print
     "Armed. Run ./doctor.sh after Wave 1 completes."
2. **`hooks/pre-commit`** — POSIX sh shim: if `.slopnet/bin/lefthook`
   exists and `.slopnet/fallback` does not → `exec .slopnet/bin/lefthook
   run pre-commit`; otherwise loop `for c in checks/*.sh; do sh "$c" ||
   exit 1; done`.
3. **`hooks/post-commit`** — the register's automatic floor. Append to
   `register/$(date +%F).md` (create with header if missing):
   `- [HH:MM] commit <short-sha> by <author-name>: "<subject>" (<N> files)`.
   Must ALWAYS exit 0 — a logging failure may never block work.
4. **`lefthook.yml`** — pre-commit section running the six checks in
   parallel, each as `sh checks/<name>.sh`.
5. **`.gitleaks.toml`** — start from gitleaks' default ruleset behavior
   (empty/minimal config relying on built-in rules is fine) plus an
   allowlist entry for `.env.example`. Keep it under 30 lines.

## Rules

- Pin real, current lefthook/gitleaks release versions and compute the
  sha256 values from the actual downloads; do not invent sums. If you
  cannot reach the network, leave the variables with `TODO-PIN` values,
  say so in `LOG.md`, and add a PENDING item — do not fake it.
- No new names, no extra files. Log in `LOG.md`.

## Acceptance (operator runs these)

```bash
./install.sh && grep -l slopnet-armed .git/hooks/pre-commit .git/hooks/post-commit
```
```bash
touch "bad name.txt" && git add "bad name.txt" && git commit -m test; git reset -q; rm "bad name.txt"
```
(the commit must be BLOCKED by naming.sh with the three-line block)
```bash
git commit --allow-empty -m "hook probe" && tail -2 "register/$(date +%F).md" && git reset -q --soft HEAD~1
```
(the register file must show the auto-appended machine line)
