# J05 — the README a child can follow

> **State: completed historical brief.** Its Mac-local walkthrough is kept
> for evidence, but it is no longer the product onboarding route. The
> VPS-first beginner promise in `SLOPNET.md` governs future documentation.

**Where:** the `slopnet` repo, `README.md`. **Size:** medium.
**Best done after:** J03 (so the one-command path is real before it's
documented). **Rule that governs this whole job: never document
something that does not work yet.**

## Why this job exists

The repo is public. The current README is five lines — right for a
skeleton, wrong for a tool people are meant to pick up and use. It must
now teach a complete beginner, on their own Mac, with no prior git or
terminal knowledge, to build something.

## Who you are writing for

A curious twelve-year-old with a Mac, or an adult who has never opened
Terminal. They have one AI coding subscription. They do not know what a
repository, a commit, or a hook is, and they should not need to.

## Required shape

1. **One sentence** saying what SlopNet is, in words with no jargon.
2. **A 30-second demo** — the exact three lines they will type, and what
   they'll see. Real output, copied from a real run, not invented.
3. **Install** — every step, assuming nothing. Include: how to open
   Terminal on a Mac, how to check `python3` and `git` exist (and the
   one-line fix if they don't), and how to get `slopnet` onto their
   machine and runnable from anywhere.
4. **Your first project** — a complete worked example from empty folder
   to working program, with the real terminal output shown.
5. **What just happened** — a short, plain explanation of the walls, the
   register, and the crew. One short paragraph each. No lists of jargon.
6. **When something says no** — show a real RULE/WHY/FIX rejection and
   explain that this is the tool protecting them, not an error they broke.
7. **The commands** — a small table: command, what it does in one plain
   sentence. Every command that exists, nothing that doesn't.
8. **Using your own AI subscriptions** — which CLIs are supported and the
   one line that connects each (from J01's verified table).
9. **For grown-ups / teams** — one short section: rulesets, CI, the
   countersign rule, and the org-only push-rules caveat.
10. **Honest limits** — what SlopNet does *not* do (it does not judge
    whether your idea is good; it cannot catch a bug that your tests
    don't; it needs an AI subscription to do the coding work).

## Rules

- **Every command in the README must be run by you and its real output
  pasted.** If a command fails, fix the docs or the tool — never publish
  an aspirational example.
- Short sentences. Explain any word a beginner wouldn't know, in place,
  the first time it appears.
- No badges, no logos, no marketing voice, no emoji storm.
- Keep it under ~250 lines. If it grows past that, the tool is too
  complicated and that is a finding for `PENDING_OPERATOR.md`.
- Do not rename anything or invent new commands to make the docs neater.

## Acceptance

- Every command block in the README has been executed by you, in order,
  in a fresh temp directory, and the pasted output matches.
- Paste that whole session into the register.
- Then: hand the README to a *small, fast* model with no other context
  and this instruction: *"Follow this README exactly. Report every point
  where you were confused."* Put its confusions in
  `PENDING_OPERATOR.md`. Do not fix them silently — they are the
  operator's to triage.
