## Open

- [2026-07-29, Codex] The v0.9 Mac app cleanly separates local Granite chat, paid planning, and an explicit approved-build control, but a newly named VPS project still has no proven project-specific walls/runtime. Its plan is saved as a clean Git base; the approved-build helper refuses before any agent starts when that runtime is absent. Do not claim end-to-end multi-agent building from the Mac app until a small project template/runtime has passed a real VPS plan-and-run proof.

- [2026-07-29, Codex] Local-model benchmark conclusion needs a later, model-specific tool-call adapter proof: the corrected bounded VPS benchmark measured Granite 4.1 3B at 14.9 tokens/sec / 3.9 GiB peak RSS and SmolLM3 3B at 15.2 tokens/sec / 3.6 GiB. Its first action-shape scorer was invalid because llama.cpp echoed the prompt; a later bare-prompt Granite run started but did not promptly finish a function-shaped answer. Ministral 3B and Qwen3 4B did not complete this generic CLI harness and were manually stopped. Do not offer them as SlopNet presets or claim native tool calling until each has a dedicated chat template, parser, timeout test, and real action-denial proof.

- [2026-07-29, Codex] Real v0.6 local-helper attempt did not pass: on the prepared VPS, Linux reported global OOM and killed llama at anon-rss 23090432 kB (23 GiB); the VPS has 23 GiB RAM and no swap. No local helper configuration was written. v0.7 bounds the helper proof to a 4,096-token context with smaller batches and a timeout; repeat the user-approved live proof before claiming this path works.

- [2026-07-29, Codex] Actual push observation: GitHub allowed direct pushes to main while reporting ‘4 of 4 required status checks are expected.’ Required checks did not gate the pushes. Restore a non-bypassable pull-request/status-check path before release; current branch rules are not evidence of enforcement.

- [2026-07-29, Codex] Local helper onboarding is not implemented yet: official IBM Granite 4.1 8B GGUF Q4_K_M is a 5.35 GB Apache-2.0 download and official llama.cpp can serve it locally. Before adding an automatic installer, decide whether the app must show an explicit capacity and download-confirmation screen, then prove install/detection under the protected slopnet runtime account rather than a server login account.

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

- [2026-07-29, Codex] Live local-helper proof is pending: v0.6 builds an opt-in Llama.cpp/IBM Granite path, detects existing runtime state, asks twice before a model download, and requires a harmless `READY` reply before configuration. It has not yet been installed against a VPS from the released app. Do not claim its download or model inference is proved until that visible run is recorded.

## Ruled

- [2026-07-30, claude] Settled rather than escalated: coding agents now run under Bubblewrap with only their own worktree writable, so the three tools that bypass their permission prompts can no longer write outside the project regardless of their flags. Where no sandbox is available an unattended run is refused. Not yet proved on a live server.

- [2026-07-30, claude] Settled rather than escalated: the VPS bootstrap now checks out a pinned release instead of the moving default branch, and refuses rather than falling back. A signed release is the next step up from this; pinning removes the accidental-drift risk today.

- [2026-07-29, Codex] Resolved with a real VPS proof: the first Granite attempt hit a global OOM at 23.09 GiB RSS on a 23 GiB, no-swap host. v0.7 forced the optional helper to `-c 4096 -b 512 -ub 256 --no-warmup` with a timeout. Its cached, offline live command then returned `READY` with `MODEL_PROOF_EXIT=0`; no listening port was started. The model is CPU-only on this VPS and generated at about 0.6 tokens/sec, so retain its deliberately narrow request-draft role.

- [2026-07-29, Codex] Resolved in source, not yet a live-host claim: the local-helper onboarding decision is an explicit capacity-and-download-confirmation screen. It validates a public `owner/model:quant` Hugging Face identifier, runs Llama.cpp and the GGUF only as the private `slopnet` account, stores only the chosen identifier in that account, opens no model port, and makes a person approve an offline request draft before it reaches the paid planner. v0.6 source acceptance passed; the separate live proof remains open above.

- [2026-07-29, Codex] Resolved: the tested VPS initially blocked the non-root Bubblewrap sandbox with AppArmor. With the operator-approved Ubuntu `apparmor-profiles` and `apparmor-utils` packages, SlopNet loaded Ubuntu's executable-specific `bwrap-userns-restrict` profile and kept `kernel.apparmor_restrict_unprivileged_userns=1`. The upstream profile grants `/usr/bin/bwrap` the setup permissions it needs, then stacks its child into a capability-denying profile. The real non-writing probe was `bwrap --unshare-user --ro-bind / / -- /bin/true`, which returned 0. Guided setup then confirmed private Codex credentials and completed the disposable edit proof in 16 seconds. SSH, password access, firewall, Docker configuration, and the global restriction were not changed.

- [2026-07-29, operator] Authorized Docker Engine plus the Compose plugin on the tested VPS. Preserve the existing root/password SSH policy; install from Docker's official Ubuntu repository, then prove SlopNet's container gate and record the actual output.

- [2026-07-28, operator] Approved sending the disposable J03 acceptance prompt and scratch-repository contents to OpenAI Codex. The real run then merged `T1-print-current-date`, passed its pytest and all walls, reused the crew and unchanged plan on the second run, and left a clean tree with no worktree or branch leftovers after Ctrl-C.
- [2026-07-29, Grok J05 redo] Prior Codex J05 confusions (overlapping walkthroughs, no template vs checkout, setup vs existing-crew sample, subscription-without-CLI-login) addressed in README rewrite; new peer confusions re-filed under Open.
