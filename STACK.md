# STACK.md — companions that level SlopNet up

SlopNet is the law. The tools below are optional companions that plug
into it — none are required, the walls work bare, and each can be added
one at a time. Licenses were checked against the projects' own pages on
2026-07-28; re-check before shipping code from any of them.

| Companion | What it adds | License | How it plugs in |
|---|---|---|---|
| **codebase-memory-mcp** (DeusData) | Whole-codebase structural memory over MCP — the agent *sees* the repo as a knowledge graph instead of grepping blind. Directly attacks "nothing is picked up unless an agent searches for it." | MIT | Run its installer (auto-configures Claude Code, Cursor and 40+ agents via `.mcp.json`); indexes live locally under `~/.cache/`. Read-only: it never edits your tree, so it needs no wall of its own. |
| **Hermes Agent** (Nous Research) | A Claude-Code-class open runtime with sandboxed execution (local/Docker/SSH). Another worker the walls govern. | MIT | Reads `AGENTS.md` natively today. A dedicated adapter (prompt auto-logging + protected-path guard, like `adapters/claude-code/`) is the v0.2 item. |
| **OpenClaw** | Heartbeat scheduling — the conversational watchman. | see its repo | Point its heartbeat at `WATCHMAN.md`; the `tasks:` block there uses the heartbeat convention. The deterministic watchman (`.github/workflows/watchman.yml`) stays on regardless. |
| **SkillClaw** (AMAP-ML) | Evolves reusable `SKILL.md` skills from your real sessions — a proxy that watches agent↔LLM traffic and distills what worked. | MIT | Sits as a local API proxy in front of any OpenAI-compatible endpoint; already integrates Hermes, OpenClaw, Claude Code, Codex. Skills it produces are the same format as `adapters/claude-code/skills/`. **Note:** it records session traffic by design — keep it pointed at local storage and out of production repos until you've read its data-handling docs. |
| **Buzz** (Block) | A signed-event workspace where humans and agents share rooms — every message, patch and approval is a cryptographically signed event with an audit trail. The register, at enterprise scale. | Apache-2.0 | Team mode only. Solo SlopNet does not need a Rust relay + Postgres; when a SlopNet repo grows a team, mirroring register entries as Buzz events is the natural graduation. |

## The order to adopt them (recommendation)

1. **codebase-memory-mcp** — biggest gain, zero risk, one install command.
2. **WATCHMAN.md wiring** — free with this commit (deterministic watchman
   is already on; add OpenClaw/Hermes scheduling only if you run them).
3. **Hermes adapter** — when v0.2 opens.
4. **SkillClaw** — once sessions are routine and worth distilling.
5. **Buzz** — the day there are two humans.

## The standing rule

Every companion is a **worker or a witness — never the law.** Companions
get governed by the walls like any other agent; nothing in this table
may edit `checks/`, bypass hooks, or write to the register's past. If a
companion and the law disagree, the law wins and the disagreement goes
to `register/PENDING_OPERATOR.md`.
