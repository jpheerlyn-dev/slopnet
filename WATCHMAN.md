# WATCHMAN.md — the rounds between commits

> **State: future operational reference.** Watchmen are not part of the
> current beginner MVP. They report only and must never be used as a reason to
> bypass the VPS setup and one-agent proof still required by `SLOPNET.md`.

The walls check every commit. The watchman checks the *silences* — the
things that go wrong between commits, or that nobody commits at all.

Two watchmen can do these rounds; they are the same rounds:

- **The deterministic watchman** — `.github/workflows/watchman.yml` runs
  daily on GitHub, no AI involved, and opens or updates a single issue
  titled "Watchman report" when something is wrong (and closes it when
  all is clear). This one is always on and costs nothing.
- **An agent watchman** — any scheduler that runs an agent periodically
  (OpenClaw's heartbeat, a Hermes schedule, plain cron) can be pointed
  at this file. The `tasks:` block below uses the heartbeat convention:
  each task has an interval; a due task is included in the wake-up, an
  empty round goes back to sleep.

```yaml
tasks:
  - name: walls-standing
    interval: 1d
    prompt: >
      From the repo root run every checks/*.sh with --all. Report any
      failure by quoting its RULE line. Do not fix anything.
  - name: machinery-untampered
    interval: 1d
    prompt: >
      Verify MANIFEST.sha256 (shasum -a 256 -c MANIFEST.sha256). A
      mismatch means the enforcement machinery changed without a
      manifest update — raise it, name the files, do not repair.
  - name: register-fresh
    interval: 1d
    prompt: >
      Find the date of the last commit. If register/<that-date>.md does
      not exist, raise it — work happened off the record.
  - name: questions-waiting
    interval: 3d
    prompt: >
      If register/PENDING_OPERATOR.md has anything under "## Open",
      remind the operator once, gently. Unanswered questions become
      agent guesses.
  - name: walls-on-the-server
    interval: 7d
    prompt: >
      Run rulesets/apply-rulesets.sh --check if the gh CLI is available.
      If no rulesets are active, remind the operator weekly — local
      hooks alone are a fence, not a wall.
```

**The one law of any watchman, human or machine: report, never repair.**
A watchman that quietly fixes what it finds is how silent breakage
starts — the failure class this whole project exists to end.
