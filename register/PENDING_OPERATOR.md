## Open

- [2026-07-29, Codex] Core MVP gap: the first guided VPS setup and private Codex edit proof now pass on a tested VPS. SlopNet is still not beginner-ready: the Mac app hands the detail to Terminal, the proof covers one provider only, no first user project flow has passed, and the credentialed agent runtime has not earned a scoped-egress design. Do not substitute more providers or integrations for those product steps.

- [2026-07-29, Codex] Privacy remediation needs an operator decision: the current product files are being made generic and no tracked key, password, token, IP address, or crew configuration was found. Older tracked register and archive material still contains legacy test-machine labels and local-account paths, and GitHub history retains every previous commit. Removing that material from GitHub requires a history rewrite and force-push, which can disrupt existing clones. Do not perform that destructive operation without the operator's explicit approval.

- [2026-07-29, Codex] Docker installation on the tested VPS reported a newer kernel available (running 6.8.0-124-generic; expected 6.8.0-136-generic). Docker is active and the SlopNet gate passed; no reboot was performed. Please choose a maintenance window if you want the kernel upgrade activated.

- [2026-07-29, jpheerlyn-dev] J07 real-world fleet run: all six detected coding CLIs failed their required proof (Claude and Gemini were reported logged in but said not logged in; Codex and Hermes hit local permission errors; Grok printed only }; Kimi pointed outside the project). J07 forbids repairs. Should these be scheduled as the v0.3 backlog and should the operator authorise a new full-fleet rerun only after the environment is repaired?

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

- [2026-07-29, Codex] Resolved: the tested VPS initially blocked the non-root Bubblewrap sandbox with AppArmor. With the operator-approved Ubuntu `apparmor-profiles` and `apparmor-utils` packages, SlopNet loaded Ubuntu's executable-specific `bwrap-userns-restrict` profile and kept `kernel.apparmor_restrict_unprivileged_userns=1`. The upstream profile grants `/usr/bin/bwrap` the setup permissions it needs, then stacks its child into a capability-denying profile. The real non-writing probe was `bwrap --unshare-user --ro-bind / / -- /bin/true`, which returned 0. Guided setup then confirmed private Codex credentials and completed the disposable edit proof in 16 seconds. SSH, password access, firewall, Docker configuration, and the global restriction were not changed.

- [2026-07-29, operator] Authorized Docker Engine plus the Compose plugin on the tested VPS. Preserve the existing root/password SSH policy; install from Docker's official Ubuntu repository, then prove SlopNet's container gate and record the actual output.

- [2026-07-28, operator] Approved sending the disposable J03 acceptance prompt and scratch-repository contents to OpenAI Codex. The real run then merged `T1-print-current-date`, passed its pytest and all walls, reused the crew and unchanged plan on the second run, and left a clean tree with no worktree or branch leftovers after Ctrl-C.
- [2026-07-29, Grok J05 redo] Prior Codex J05 confusions (overlapping walkthroughs, no template vs checkout, setup vs existing-crew sample, subscription-without-CLI-login) addressed in README rewrite; new peer confusions re-filed under Open.
