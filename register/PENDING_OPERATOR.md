## Open

- [2026-07-28, Codex] J01 live probe: Gemini is installed but unproven because no authentication method is configured. Please configure Gemini CLI authentication, then rerun `python3 ./slopnet setup`.

- [2026-07-28, Codex] J01 live probe: Claude is installed but unproven because its OAuth session expired and could not be refreshed. Please log Claude Code in, then rerun `python3 ./slopnet setup`.

- [2026-07-28, Grok J02] Report DO-NOT-ASSUME: Gemini CLI exact auto-approve flag and quota-error strings still not found in primary sources — left unclassified beyond generic non-zero exit.

- [2026-07-28, Grok J02] Report DO-NOT-ASSUME: Codex exact raw 429 string inside `codex exec` not found — only HTTP 429 classification for raw `api` workers is implemented.

- [2026-07-28, Grok J02] Report mentions optional zAI model `glm-5.2[1m]` + `CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000` for 1M context. Defaults stay at the platform's GLM-4.7 / GLM-4.5-Air; should the operator want glm-5.2 as the fleet default instead?

- [2026-07-28, Grok J02] Report documents OpenAI-compatible URL `https://api.z.ai/api/coding/paas/v4` for non-Claude hosts, but also says naked/custom clients that fail the supported-tool check can lose Coding Plan benefits. Stored in `providers.zai-glm.openai_compat_url` for reference only — no raw `api` worker was added. Confirm if you want a supported-host path (e.g. documented Cursor/Cline) wired later.

- [2026-07-28, Grok J02] Does the Kimi *coding plan* cover raw `MOONSHOT_API_KEY` HTTP use, or only the Kimi Code CLI / login-linked key? Report confirms CLI membership cover; API-credit boundary for naked HTTP was not verified, so no billing caveat was hard-coded on that `api` worker.
## Ruled
