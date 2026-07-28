# T09 — the bridge: **REDACTED** port plan

**Where: inside the **REDACTED** repo** (NOT slopnet). **Model:** large.
**Prerequisites — do not start without all three:** SlopNet v0.1 proven
(T07 = 20/20, T08 findings triaged) · the **REDACTED** **naming audit ruled**
(see `register/PENDING_OPERATOR.md` — v2.00 writes names into stone, so
verdicts must exist first) · operator says go.

## Context

**REDACTED** is a live writing app whose migration to a clean structure was
planned (`agent_touch/MASTER_PLAN.md`) and then PAUSED by the operator.
SlopNet has since been designed and built as the governance template —
and the plan changed shape: instead of restructuring in place, **REDACTED**
is **ported into a fresh repo created from the SlopNet template**:
`**REDACTED**` (operator-ruled name). The old repo becomes a read-only
reference and archive, never deleted.

## Your task

Produce **`**REDACTED**`** (**REDACTED** root) — the operational
plan for the port. You are REVISING an existing body of planning, not
starting fresh. Read, in order:

1. `MAP.md`, `AGENTS.md`, `SLOPNET.md` — the environment and its law.
2. `agent_touch/MASTER_PLAN.md` — the paused plan. Its §4 Rosetta table
   (old path → new home) and §7 rails (CI path filters, LOC gate,
   `**REDACTED**` pinning, `main.py` ordering invariants, the
   TRIAGE park rules) remain the hard-won substance — carry them
   forward. Its phase structure is superseded by the port-into-template
   shape.
3. The naming audit verdicts — apply the operator's ruled names
   everywhere; a name without a verdict is a blocker to list, not a
   choice for you to make.
4. `**REDACTED**/AGENTS.md`, `COMPATIBILITY.md`, `DEPENDENCIES.md` —
   contracts that must survive the port unbroken.

The plan must cover, concretely:

- **Repo birth:** **REDACTED** created from the slopnet template;
  doctor green and branch protection on BEFORE any product code arrives.
- **Port order:** features one at a time per the Rosetta table (pilot
  first — the master plan nominated `profile`), each ported feature
  arriving with its tests, its MAP.md row, and a register entry; the old
  repo untouched except for read access and archive moves.
- **The four standing hazards** (from the master plan, restated as port
  gates): live data re-homing (`**REDACTED**` pinned on the VPS
  before cutover); the dual-mount contracts; the `main.py` ordering
  invariants; the TRIAGE park — which ports ONLY via the recovery-epic
  copy-out rules, never as a bulk move.
- **Deploy cutover:** the systemd/nginx switch as a scheduled
  operator-run step with a rollback line.
- **Definition of done** for v2.00, including: old repo archived with
  provenance; `slopnet` registry rows updated; **REDACTED**'s own
  SLOPNET.md registry seeded with any still-orbiting ideas.

## Rules

- You are planning, not executing. No file moves, no renames, no repo
  creation — the deliverable is the plan document alone.
- Naming is operator-only; unresolved names are listed as blockers.
- Sign the **REDACTED** register before finishing; questions to
  `register/PENDING_OPERATOR.md`.

## Acceptance (operator reads)

The plan names its pilot feature, its port order, all four hazards with
their gates, the cutover + rollback step, and a checkable definition of
done — and contains not a single name the operator hasn't ruled.
