# SlopNet — Safe Language Orientated Programming Network

The operator's law for new ideas:

> **The Orbit — new ideas are born in their own small repos that call the app; the trunk stays stable forever.**

New ideas are never built inside the main codebase. Each idea starts as its own small repository that calls the main app. It joins the main repo only after it proves itself. If it never does, it ends outside and harms nothing.

Why: the main repo stays ready to use. A half-built idea can wait without blocking anything. A small repo is small enough for a person or model to understand.

## The five rules of SlopNet

1. **Call, don't reach.** An idea repo talks to the main app through its HTTP API (web door) only, using the local development server by default: `http://127.0.0.1:8000`. It never imports main-repo internals or reads and writes the main repo's data folders.
2. **Every idea repo is registered below.** Agents in the main repo cannot see other repos. This registry is their window. No row, no repo.
3. **The operator names it.** This is the same naming rule as `AGENTS.md`.
4. **No production anything.** Idea repos use the local development server and their own throwaway keys in a gitignored `.env`. Never use the live app, real user data, or shared secrets.
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

1. Talk to the main app over HTTP only (local development server, default `http://127.0.0.1:8000`). Never import its internals or touch its files or data folders.
2. Never use live URLs, keys, or user data.
3. The operator names things. Do not rename anything.
4. Log every session in `LOG.md`: date — model — what changed — what is broken.
5. Keep it small enough to explain to a ten-year-old. If it stops fitting in your head, tell the operator instead of adding folders.
```
