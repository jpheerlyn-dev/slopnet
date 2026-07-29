# SlopNet map

## Start here

| If you need to… | Read or run |
|---|---|
| understand the current VPS-first MVP | `SLOPNET.md` |
| understand the future newcomer path and its current gap | `SLOPNET.md`, then the opening of `README.md` |
| work on the historical local implementation | `CREW.md` and the historical section of `README.md` |
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
| `packaging/` | Mac control app, guided VPS helpers, and the optional local-model setup; all are bundled into `SlopNet.app` |

## VPS container gate

`Dockerfile` and `compose.yml` provide one deliberately strict VPS gate for
the repository walls: non-root, read-only filesystem, no network, no Docker
socket, and bounded resources. It is a containment proof, not the future
credentialed coding-agent runtime. The tested VPS checkout is at
`/opt/slopnet`; the full live proof is in `register/2026-07-29.md`.

## Historical material — preserve, do not dispatch by accident

| Material | What it is now |
|---|---|
| `archive/jobs/` | completed local-path briefs, J07 failure evidence, deferred J08, and subscription research |
| `archive/reference/` | retired v0.2 design, companion, and watchman references |

The active product path is deliberately small: one guided VPS setup and one
real subscribed CLI are now proved. Make that path pleasant in the Mac control
app, then schedule one real project flow before any J07 rerun.
`jobs/OPERATORS.md` is the complete current dashboard; it should be the only
file needed to understand the queue.

## Ideas in orbit

New product ideas belong in their own operator-named orbit repositories.
Their rulebook and registry are in `SLOPNET.md`; do not add them to this
trunk before they earn graduation.
