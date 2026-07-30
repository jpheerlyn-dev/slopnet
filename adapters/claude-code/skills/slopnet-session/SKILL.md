---
name: slopnet-session
description: SlopNet session ritual for any repo governed by SlopNet — read the register and pending questions before working, obey FIX lines when a check blocks you, sign the register and verify the checks before finishing. Use at the start and end of every working session in a SlopNet repo.
---

# The SlopNet session ritual

## When you start

1. Read `register/<today>.md` and the most recent earlier day-file —
   that is what happened before you arrived.
2. Read `register/PENDING_OPERATOR.md`. If your task depends on anything
   under "## Open", stop and say so. Never answer an open question by
   guessing.

## While you work

- Never rename anything — folders, files, features, concepts. Naming
  belongs to the operator. Need a name? Add a NAME-PENDING entry to
  `register/PENDING_OPERATOR.md` and use a plain description meanwhile.
- New ideas are built in orbit repos (see `SLOPNET.md`), never in this
  trunk.
- When a check blocks your commit it prints three lines: RULE, WHY, FIX.
  Do what FIX says. Never bypass with `--no-verify`, never edit anything
  in `checks/` to make a failure go away, never delete a test to pass it.

## Before your final message

1. Append to `register/<today>.md`:
   `## HH:MM — <your model name> did` — files touched · commands run ·
   what changed · what is left undone.
2. If you changed anything, run `./doctor.sh` and report its output
   honestly — including the lines you wish were green.
3. Anything you could not resolve goes to `register/PENDING_OPERATOR.md`.
   Then stop. An honest unfinished session beats a confident broken one.

## When you are the verifier

If you were asked to check another agent's work: run `slopnet verify`
(or the MCP `verify` tool) and let the countersign speak. Report FAIL
lines exactly as printed. Never verify your own work, and never soften
a verdict — the countersign is the whole point of having a second
pair of eyes.
