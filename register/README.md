# The register

The record of what was done to this project and why. Keep it — the history is
the point. But it is a record, not a dumping ground.

## Rules

- One file per day: `YYYY-MM-DD.md`.
- A post-commit hook appends machine lines automatically.
- Humans and agents add prose entries as `## HH:MM — <who> did`.
- Never edit past entries. The one exception is redacting private data, and
  only when the operator asks for it.
- Put questions in `register/PENDING_OPERATOR.md`.

## What an entry is

**Prose. Around fifteen lines.** What changed, why, what is proved, what is
not. Somebody should be able to read a day of this project in a couple of
minutes.

**No pasted terminal output.** No command dumps, no file listings, no
directory trees, no screenshots of logs. Name the command you ran and what it
told you; do not paste what it printed.

This is not tidiness. On 2026-07-30 a server address, a home directory path
and a machine name reached GitHub, and every one of them arrived as pasted
agent output inside a register entry. 254 lines of this file's history were
raw terminal paste. The rule exists because ignoring it leaked real data.

## Where the evidence goes

`evidence/` — gitignored, stays on the operator's machine. Screenshots, raw
output, transcripts, timing runs.

An entry may name a file in there. It must never paste the contents.

## Redact before you write, not after

Never write an IP address, a `/Users/<name>` or `/home/<name>` path, a machine
name, a hostname or a token into a tracked file. Replace it with `**REDACTED**`
so the gap is visible.

Once it is committed and pushed it is public, and cleaning it means rewriting
history for everyone.

## Do not commit just to record a hook line

The post-commit hook writes its line after your commit, which leaves the tree
dirty. Leave it. It rides along with your next real commit.

Committing solely to capture that line makes the hook fire again and write
another one. Five of the twelve commits before this rule existed were exactly
that: paperwork about paperwork.
