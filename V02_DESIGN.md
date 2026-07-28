# v0.2 design — the `slopnet` CLI and the universal adapter

**Status:** Proposed — operator to approve before briefs are cut.
**Question this answers:** how does SlopNet wedge into every coding tool
(Claude Code, Codex, Cursor, Gemini CLI / Antigravity, Hermes, any IDE
or CLI) natively, without each tool having to change its practices?

---

## 1. Honest status of "integrations" today

| Platform | What actually exists |
|---|---|
| Claude Code | **Real adapter** — prompt auto-logging + protected-path guard hooks + slopnet-session skill. Proven in production. |
| Every AGENTS.md-reading tool (Codex, Cursor, Gemini CLI, Copilot, Hermes…) | **Native but advisory** — they read the law files; nothing enforces inside their loop. |
| OpenClaw | **Convention only** — WATCHMAN.md speaks its heartbeat format; no wiring shipped. |
| Hermes | **Plan only.** |
| Buzz | **Deliberately deferred** (team mode). |
| git + CI + rulesets | **The real, finished, universal layer** — every tool passes through commit and push, whoever made it. |

## 2. The wedge analysis — four depths, one verdict

A tool can only be universal at a layer every agent already passes
through. There are exactly four candidate layers:

1. **The files** (`AGENTS.md`, `SKILL.md`, `WATCHMAN.md`) — already
   universal, already shipped, forever advisory. The lingua franca, not
   the law.
2. **The chokepoints** (git hooks, CI, server rulesets) — already
   universal, already shipped, genuinely blocking. This *is* a universal
   adapter; it just speaks late (at commit), not during the
   conversation.
3. **The conversation** — the missing piece, and the answer is **MCP**.
   As of mid-2026 the Model Context Protocol is supported by essentially
   every major agent surface (Claude Code, Cursor, Codex, Gemini CLI,
   VS Code/Copilot, Antigravity, and the 40+ tools that companions like
   codebase-memory-mcp auto-configure). One MCP server makes SlopNet a
   **native tool inside every one of them** — no per-tool adapter code,
   no tool changing its practices. The tool sees callable functions;
   SlopNet's ritual becomes something an agent *does* rather than reads
   about.
4. **The middleman** (an API proxy between agent and LLM, SkillClaw's
   approach) — powerful and REJECTED for core. A proxy sees every
   token including credentials, adds latency to every call, needs
   per-tool base-URL surgery, and breaks whenever either side updates.
   Middlemen break; **ports get adopted.** SlopNet is a port. (A proxy
   can return later as an explicit opt-in companion, never core.)

**Verdict: SlopNet wedges in at depths 1+2 (done) and depth 3 (v0.2's
job), unified behind one CLI.**

## 3. The product: one `slopnet` command

A single-file, stdlib-only Python 3 CLI (`slopnet`) — no pip installs,
runs anywhere macOS/Linux ships python3, Go binary later if speed ever
demands it. Subcommands, each replacing a today-manual step:

| Command | Replaces / adds |
|---|---|
| `slopnet init` | install.sh + the entire manual Wave 0: arm hooks, fetch pinned binaries, first register file, and (with `--github`) create the repo, push, enable Actions, apply rulesets — the human types one command, ever |
| `slopnet doctor [--fix]` | doctor.sh; `--fix` re-arms hooks and applies rulesets via gh instead of nagging |
| `slopnet check` | run the six walls on demand (what agents call *before* wasting a commit attempt) |
| `slopnet sign "<what I did>"` | append a prose register entry — one line for humans, one call for agents |
| `slopnet orbit new <name>` | the SLOPNET.md recipe as one command: templates copied, registry row added, repo initialized |
| `slopnet adapt` | detect which tools are configured in this checkout (.claude/, .cursor/, codex, gemini…) and install the matching adapter configs — the codebase-memory-mcp auto-detect pattern |
| `slopnet mcp` | **the universal adapter**: serve SlopNet over MCP (stdio) |
| `slopnet watch` | optional live filesystem watchman between commits |

### The MCP server's surface (kept deliberately small)

Tools: `session_start` (returns today's register + open PENDING items —
the ritual's reading half, delivered as data) · `sign_register(text)` ·
`check(staged|all)` (walls on demand, RULE/WHY/FIX verbatim) ·
`pending_add(question)` · `doctor()`.
Resources: the law files (AGENTS.md, SLOPNET.md, WATCHMAN.md) exposed
read-only so tools can surface them natively.

One server, every tool. The Hermes "integration," the Gemini
"integration," the Cursor "integration" all collapse into: *run
`slopnet adapt`, which writes the six lines of MCP config each tool
expects.* The per-tool adapter folder pattern survives only where a tool
offers real enforcement hooks (Claude Code today; others as they grow
hook systems).

## 4. What "native" means per tool, after v0.2

| Tool | Files (advisory) | Conversation (MCP) | Enforcement |
|---|---|---|---|
| Claude Code | CLAUDE.md/AGENTS.md | `slopnet mcp` | hooks adapter (today) + git/CI/rulesets |
| Codex / Gemini CLI / Cursor / Antigravity / VS Code | AGENTS.md (+ tool-specific rules files written by `slopnet adapt`) | `slopnet mcp` | git/CI/rulesets |
| Hermes | AGENTS.md | `slopnet mcp` | git/CI/rulesets; hook adapter if/when Hermes exposes hooks |
| OpenClaw | AGENTS.md + WATCHMAN.md heartbeat | `slopnet mcp` | git/CI/rulesets |
| Buzz (team mode, later) | — | register→signed-events bridge | its own signed audit layer |
| A tool that ships next month | AGENTS.md | MCP (it will support it) | git/CI/rulesets — it cannot opt out |

That last row is the whole argument: the design needs no knowledge of
future tools, because it only stands on layers no tool can skip.

## 5. Red-line check

- **Ten-year-old simple:** the human's entire surface shrinks to
  `slopnet init` and reading what the watchman says. Everything else is
  agents talking to a port.
- **Swamp-impossible:** unchanged — MCP adds convenience, never replaces
  the chokepoints. An agent that ignores the MCP server entirely still
  hits the same walls.
- **CEO-grade:** stdlib-only, no telemetry, MIT; MCP is the
  industry-standard port, not a bet on any vendor; the proxy rejection
  keeps credentials untouched.

## 6. Build shape (when the operator approves)

Briefs cut per the v0.2 doctrine — **the human never runs commands**:
every brief's acceptance is a script the building agent runs and a
*second* agent re-runs and countersigns in the register. Rough cut:
V01 CLI core (init/doctor/check/sign) → V02 orbit + adapt → V03 MCP
server → V04 second-agent verification harness → V05 red-team the CLI
itself (including an MCP-level attack round). T09 (**REDACTED**)
stays parked behind the naming audit, unchanged.

**Progress note (2026-07-28, same day):** V01–V03 were built directly
by the operator's session agent rather than dispatched — the `slopnet`
CLI at repo root now ships init / doctor[--fix] / check[--all] / sign /
pending / orbit new / adapt / mcp, all scratch-tested (init→check→sign→
pending→orbit→adapt plus a full piped MCP session: initialize,
tools/list, tools/call).

**Progress note 2 (2026-07-28, evening):** V04 and V05 shipped.
V04 = `slopnet verify` + the MCP `verify` tool: re-runs walls, manifest,
doctor, and (CLI-only) the full red-team, then writes a COUNTERSIGN
entry to the register with per-proof PASS/FAIL and the commit sha —
AGENTS.md rule 7 now requires a countersign from a *different* agent
before work is DONE. V05 = the red-team extended to 25 attacks with an
MCP fuzz round (garbage stdin, missing required arguments — the server
must answer isError and keep serving). v0.2 is feature-complete; what
remains before calling SlopNet "complete" is operator-side: raise the
server wall (apply rulesets + branch protection), take the template
public when ready, and a v0.3 list (fake-gate sniffer, protected-path
globs, Hermes hook adapter if Hermes grows hooks).

## 7. Harvested from StormCode (the operator's own orchestrator)

StormCode (~/Desktop/stormcode) is a working multi-agent pipeline —
planner → plan.yaml → scheduler → implementer-in-worktree → tests-as-
oracle → reviewer gate → merge — with live-proven runs. It independently
converged on SlopNet's philosophy, which is strong evidence for both.
Taken into SlopNet now or next:

- **Engine/UI separation** (StormCode's engine has zero UI imports) —
  adopted as a stated rule in the CLI's docstring.
- **Refuse fake gates:** StormCode refuses a live run if the test
  command looks like an always-pass stub (`exit 0`, `echo OK`). Steal
  for v0.3: a doctor line that sniffs stub test-gates.
- **Protected-path globs** in its gates.py — v0.3 upgrade path for
  PROTECTED.txt from prefixes to globs.
- **Plan contract validation** (unique ids, real deps, acyclic, one
  repair round, "a bad plan never executes") — the blueprint for
  SlopNet wave-briefs when multi-agent dispatch arrives.
- **Relationship:** StormCode is the factory, SlopNet is the law. A
  StormCode swarm working inside a SlopNet repo already hits the walls
  at every merge; wiring StormCode's `gates.test_command` to
  `slopnet check --all` + tests makes the marriage explicit. StormCode
  joins STACK.md as a worker companion.
