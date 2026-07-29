# SlopNet map

## Start here

| If you need to… | Read or run |
|---|---|
| understand the current VPS-first MVP | `SLOPNET.md` |
| use the existing local command path | `README.md` and `CREW.md` |
| see the job history and what is next | `jobs/OPERATORS.md` |
| see decisions, evidence, and unresolved operator choices | `register/` and `register/PENDING_OPERATOR.md` |
| understand the non-negotiable rules | `AGENTS.md` and `checks/` |

## The engine

| Part | Purpose |
|---|---|
| `slopnet` | command-line entry point: setup, plan, run, go, sign, verify, and doctor |
| `crew.py` | crew configuration, planning, parallel worktrees, and merge handling |
| `checks/` | the six repository walls; this is the law |
| `tests/` | behavioural tests and the red-team suite |
| `.githooks/` and `.github/workflows/` | local and GitHub enforcement |
| `register/` | chronological evidence and operator decisions |

## VPS container gate

`Dockerfile` and `compose.yml` provide one deliberately strict VPS gate for
the repository walls: non-root, read-only filesystem, no network, no Docker
socket, and bounded resources. It is a containment proof, not the future
credentialed coding-agent runtime. The tested VPS checkout is **REDACTED** at
`/opt/slopnet`; the full live proof is in `register/2026-07-29.md`.

## Ideas in orbit

New product ideas belong in their own operator-named orbit repositories.
Their rulebook and registry are in `SLOPNET.md`; do not add them to this
trunk before they earn graduation.
