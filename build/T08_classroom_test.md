# T08 — the classroom test (fresh eyes, small model on purpose)

**Where:** a FRESH checkout of the `slopnet` repo, ideally a different
machine or clean temp dir. **Model: deliberately small/fast** — if a small
model succeeds unaided, red line 1 has evidence. **Depends on:** Waves 1–2
complete, T07 at 20/20.

## Your task (read nothing but what the repo tells you to)

You are a beginner setting up a brand-new project with SlopNet. Do NOT
read `build/` — pretend it doesn't exist. Follow only what `README.md`
and the files it points to tell you:

1. Simulate "Use this template": copy the repo (minus `.git` and `build/`)
   into a new folder, `git init`, first commit.
2. Follow README's instructions exactly as written. Where it says run
   something, run it. Where you are confused, STOP and write the
   confusion down before figuring it out.
3. Run `./doctor.sh` and follow whatever it tells you (skip the GitHub
   branch-protection click if there's no remote — note that you
   understood the instruction anyway, or didn't).
4. Build a tiny toy app (one `hello` script, one line of docs in MAP.md)
   through at least three commits, letting the machinery do its thing.
5. Spin up one toy orbit repo by following `SLOPNET.md`'s recipe alone.
6. Deliberately do one naughty thing (commit a `.DS_Store` or an
   `untitled.txt`) and record what the rejection message felt like:
   did the three lines tell you exactly what to do next?

## Deliverable

**`build/FINDINGS.md`** — honest, chronological:
- every moment of confusion, verbatim ("I didn't know what X meant");
- every instruction that worked exactly as written;
- the rejection-message experience from step 6;
- total time; and a one-line verdict: could a ten-year-old have done this?

## Rules

- Do not fix anything you find — record it. Fixing is v0.2's job, and a
  tester who repairs the track invalidates the test.
- Log the session in `LOG.md` as usual.

## Acceptance (operator reads, not runs)

`build/FINDINGS.md` exists, is honest (confusions listed, not smoothed
over), and its verdict line is defensible. Every confusion becomes a
numbered v0.2 item — the operator triages them, nobody else.
