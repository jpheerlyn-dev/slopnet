## Open

- [2026-07-29, Grok README upgrade] README is ~360+ lines after beginner-first rewrite (operator requested zero-knowledge onboarding). J05 soft guide was ~250; treat length as an operator call: keep deep onboarding, split a HUMANS.md later, or trim. Not silently shortened.
- [2026-07-29, Grok J05 redo] Peer (beginner follow of new README) confusions for operator triage — do not silent-fix without operator call:
  1. Demo sits before Install; unclear whether to run demo first.
  2. “Crew” / “met your crew” used before defined.
  3. First-time path: setup-then-go vs go-starts-setup still dual-explained.
  4. Sample names Codex; beginner may think that exact app is required.
  5. WAVES.md / “read it” / y|n|edit not fully explained at first sight.
  6. “Walls: green” before walls are taught; `git log` “Next:” looks mandatory.
  7. AI app table has no install links / which one a pure beginner should pick.
  8. PATH jargon for AI CLIs and for the optional `export PATH="$(pwd):$PATH"` line.
  9. Setup’s printed “Next: plan” vs README’s next step `go`.
  10. Clone into existing `my-app` not covered; “SlopNet vs my-app” identity still hard.
  11. No minimum Python version floor stated (only “like 3.12”).
  12. Doctor: what healthy looks like / whether failures block first project.
  Full Grok list was captured during the redo session on the operator machine.

- [2026-07-28, Codex] J01 live probe: Gemini is installed but unproven because no authentication method is configured. Please configure Gemini CLI authentication, then rerun `python3 ./slopnet setup`.
- [2026-07-28, Codex] J01 live probe: Claude is installed but unproven because its OAuth session expired and could not be refreshed. Please log Claude Code in, then rerun `python3 ./slopnet setup`.
- [2026-07-28, Grok J02] Report DO-NOT-ASSUME: Gemini CLI exact auto-approve flag and quota-error strings still not found in primary sources — left unclassified beyond generic non-zero exit.
- [2026-07-28, Grok J02] Report DO-NOT-ASSUME: Codex exact raw 429 string inside `codex exec` not found — only HTTP 429 classification for raw `api` workers is implemented.
- [2026-07-28, Grok J02] Report mentions optional zAI model `glm-5.2[1m]` + `CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000` for 1M context. Defaults stay at the platform's GLM-4.7 / GLM-4.5-Air; should the operator want glm-5.2 as the fleet default instead?
- [2026-07-28, Grok J02] Report documents OpenAI-compatible URL `https://api.z.ai/api/coding/paas/v4` for non-Claude hosts, but also says naked/custom clients that fail the supported-tool check can lose Coding Plan benefits. Stored in `providers.zai-glm.openai_compat_url` for reference only — no raw `api` worker was added. Confirm if you want a supported-host path (e.g. documented Cursor/Cline) wired later.
- [2026-07-28, Grok J02] Does the Kimi *coding plan* cover raw `MOONSHOT_API_KEY` HTTP use, or only the Kimi Code CLI / login-linked key? Report confirms CLI membership cover; API-credit boundary for naked HTTP was not verified, so no billing caveat was hard-coded on that `api` worker.

## Ruled

- [2026-07-28, operator] Approved sending the disposable J03 acceptance prompt and scratch-repository contents to OpenAI Codex. The real run then merged `T1-print-current-date`, passed its pytest and all walls, reused the crew and unchanged plan on the second run, and left a clean tree with no worktree or branch leftovers after Ctrl-C.
- [2026-07-29, Grok J05 redo] Prior Codex J05 confusions (overlapping walkthroughs, no template vs checkout, setup vs existing-crew sample, subscription-without-CLI-login) addressed in README rewrite; new peer confusions re-filed under Open.
