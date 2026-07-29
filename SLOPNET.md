# SlopNet — Safe Language Orientated Programming Network

## VPS-first execution policy

SlopNet runs coding agents, tests, builds, worktrees, and persistent
services on the operator's private VPS. A person's Mac is a control surface
that reaches the VPS over SSH; it is not the place for autonomous agent
workloads or project secrets. Services remain private by default: an orbit
or user interface reaches a VPS-local service through an SSH tunnel unless
the operator deliberately exposes a reviewed public endpoint.

This is the MVP direction. The current code is being brought into line with
it; do not describe a local run as the finished SlopNet workflow.

## The beginner promise — the release test

SlopNet is for a person who wants software made, not a person who wants to
learn deployment, agent flags, credential files, Docker, or Git on the way.
The product is not ready to call beginner-ready until this path is real:

1. The person provides a private VPS and one coding subscription.
2. One guided setup checks the VPS, explains which optional tools it found,
   asks before installing anything, and opens each approved provider's normal
   login flow.
3. It stores credentials only on the VPS, confirms the selected CLI can make
   a harmless edit there, and plainly says what passed or what still needs the
   person's attention.
4. From then on, the person asks for work; agents, tests, worktrees, and
   services run on the VPS while the person receives a clear result and a
   safe way to inspect it.

This is a product requirement, not a claim about the present checkout. The
strict Docker gate is proved. The first guided Linux VPS setup reaches Codex
login but **REDACTED** blocks the non-root Linux sandbox required for safe writes;
it is not yet a general agent runtime or a beginner-ready release. Do not paper
over that gap with more integrations, a longer README, or a local-only
workaround. Every change must make the above path shorter, safer, or easier to
understand.

## MVP crew roles

SlopNet is the coding executor: it isolates work, runs tests and walls, and
decides what may merge. It does not become a general chat gateway or a second
memory store.

Hermes is the durable memory and human-conversation agent. Its project
memory should help a person and the crew retain context across sessions.

OpenClaw is the action and connector agent. It joins only through reviewed,
scoped integrations that add a capability Hermes does not already provide.

Buzz is the shared room: the signed human-and-agent coordination record for
tasks, approvals, patches, workflow results, and release evidence. Buzz is a
collaboration relay, not another coding executor or a replacement for
Hermes's private memory.

These are target roles, not a claim that the current checkout has connected
the four systems. Each integration must be proven on the VPS before it can
receive real work.

## Container boundary

Docker is a containment layer, not a magic quality stamp. It protects a VPS
from a process that misbehaves; it cannot prove that a feature is correct,
that a dependency is trustworthy, or that an agent understood a request.
SlopNet therefore keeps the walls, real tests, review and the register even
inside a container.

This checkout now ships one strict container gate: `Dockerfile` and
`compose.yml`. It runs SlopNet's walls in a non-root process with a read-only
root filesystem, no Linux capabilities, no new privileges, a small temporary
filesystem, CPU/memory/process limits, and no network. It never receives a
Docker socket, host networking, provider credentials, or privileged mode.
Run it on the VPS with `docker compose run --rm slopnet check --all` after
Docker Engine and its Compose plugin have been installed there.

The bind-mounted project must belong to the non-root container identity. The
tested first deployment owns the new `/opt/slopnet` checkout as numeric
UID/GID `10001:10001`; this changes only that workspace and does not create an
SSH user or alter root access. Do not solve an ownership mismatch by running
the gate as root. For another project, choose matching non-root IDs through
`SLOPNET_UID` and `SLOPNET_GID` instead.

The strict gate deliberately cannot be used for `slopnet go`: a coding agent
needs selected provider access and credentials, while the gate has neither.
The later agent-runtime design must earn that access through a separate,
reviewed proof: per-project workspace, non-root identity, only the required
credential passed at runtime, explicit egress, resource limits, and a real
build/test result. No generic skill, MCP server, or RAG database gets to
silently relax those boundaries.

GitHub Actions builds this image and scans the actual result for fixable high
and critical vulnerabilities. The base image and Actions are digest/SHA-pinned
so an upstream tag cannot silently replace the thing we test. Scanner findings
are evidence to fix or consciously triage, not permission to ship slop.

The operator's law for new ideas:

> **The Orbit — new ideas are born in their own small repos that call the app; the trunk stays stable forever.**

New ideas are never built inside the main codebase. Each idea starts as its own small repository that calls the main app. It joins the main repo only after it proves itself. If it never does, it ends outside and harms nothing.

Why: the main repo stays ready to use. A half-built idea can wait without blocking anything. A small repo is small enough for a person or model to understand.

## The five rules of SlopNet

1. **Call, don't reach.** An idea repo talks to the main app through its HTTP API (web door) only, using the VPS-local development server by default: `http://127.0.0.1:8000`. A Mac reaches that loopback address through SSH forwarding; an orbit never imports main-repo internals or reads and writes the main repo's data folders.
2. **Every idea repo is registered below.** Agents in the main repo cannot see other repos. This registry is their window. No row, no repo.
3. **The operator names it.** This is the same naming rule as `AGENTS.md`.
4. **No production anything.** Idea repos use the VPS-local development server and their own throwaway keys in a gitignored `.env`. Never use the live app, real user data, or shared secrets.
5. **Graduation is deliberate, never copy-paste.** Use the checklist below.

## Registry

| Name | Repo | What it is | Calls | Status | Last known good |
|---|---|---|---|---|---|

Statuses: **cooking** (being worked on) · **on ice** (parked and safe) · **graduated** (joined the main repo; the row stays as history) · **dead** (abandoned; archive the GitHub repo and never delete the row).

## Spinning up a new idea repo

1. The operator names it and adds a row above with status **cooking**.
2. Make the new GitHub repo. Copy the two templates below into `README.md` and `AGENTS.md`. Add a gitignored `.env` only when keys are needed.
3. Build it. Log every session in one `LOG.md`: date — who — what changed — what is broken.
4. Going quiet for a while? Set the row to **on ice**. Fill in Last known good with today's date and the main repo commit: `git rev-parse --short HEAD`.

## Graduation checklist

- [ ] The operator says “graduate it.” From here, this is a main-repo change and the main `AGENTS.md` rules apply.
- [ ] Define one connection point in the main repo: a named adapter (small bridge) with clear input and output.
- [ ] Connect the code through that front door only.
- [ ] Add its tests to the main suite and run the main checks successfully.
- [ ] Update `MAP.md` and any notes needed to explain the connection.
- [ ] Change the registry row to **graduated** and write a register entry.

## Template — idea-repo `README.md`

```markdown
# <name — operator-chosen>

One or two lines: what this idea is, in plain words.

Part of this SlopNet orbit (see `SLOPNET.md` in the main repo).
Status: cooking | on ice | graduated | dead
Calls: <which main-app APIs, for example POST /api/context>
Last known good: <date> against main-repo commit <short-sha>

## Run it
<the one or two commands>
```

## Template — idea-repo `AGENTS.md`

```markdown
# AGENTS.md — idea-repo rules (SlopNet)

This is an experiment orbiting the main repo. Rules:

1. Talk to the main app over HTTP only (VPS-local development server, default `http://127.0.0.1:8000`, reached from a Mac through SSH forwarding). Never import its internals or touch its files or data folders.
2. Never use live URLs, keys, or user data.
3. The operator names things. Do not rename anything.
4. Log every session in `LOG.md`: date — model — what changed — what is broken.
5. Keep it small enough to explain to a ten-year-old. If it stops fitting in your head, tell the operator instead of adding folders.
```
