# SlopNet

SlopNet is a ready-to-use template for your code that automatically keeps messy or broken files out of your project while you let AI agents write software for you.

## A 30-Second Demo

```bash
git clone https://github.com/jpheerlyn-dev/slopnet.git my-app
cd my-app
./slopnet go "a small web page that shows today's weather" --yes
```

**What you'll see:**
```text
Using the existing crew: codex plans, 4 agent(s) write.
[planner] codex is thinking about: a small web page that shows today's weather...
[planner] WAVES.md: 1 waves, 1 tasks. Read it before you run it.

Using the plan in WAVES.md (--yes).
--- Wave 1 of 1 ---
  T1-request-operator-names  codex  working…
  T1-request-operator-names  codex  checking…
  T1-request-operator-names  codex  testing…
  T1-request-operator-names  codex  MERGED

Work report
Merged: T1-request-operator-names
Failed: nothing
Walls: green.
Next: git log --oneline --max-count=5
```

## Install

Start by checking that you have the required tools installed. Open Terminal on your Mac (press `Cmd + Space`, type `Terminal`, and hit Enter), then run these commands:

```bash
python3 --version
git --version
```
If your Mac asks to install developer tools, say yes, or run `xcode-select --install` to get them.

Once that is done, download SlopNet onto your machine and connect your AI subscription:
```bash
git clone https://github.com/jpheerlyn-dev/slopnet.git my-app
cd my-app
./slopnet setup
```

## Your First Project

Let's build a working program from scratch. In your terminal, inside the `my-app` folder you just downloaded, type:

```bash
./slopnet go "a small web page that shows today's weather"
```

SlopNet will write a step-by-step plan for your idea. Read the plan, press `Enter` to approve it, and watch as SlopNet creates the files for you!

## What Just Happened

**The crew**
SlopNet uses one AI to write a clear plan (saved as `WAVES.md`), and then uses several AI agents to write the actual code simultaneously based on that plan.

**The walls**
Before any code is saved to your computer, SlopNet runs strict checks (called walls) to block broken, messy, or secret-leaking files. 

**The register**
A log of every AI action is saved automatically in the `register/` directory. You can always see exactly who changed what and when.

## When Something Says No

If an AI makes a mistake, SlopNet will reject it and show you exactly why. This is the tool protecting you, not an error you broke!

```text
RULE: Thumbs.db are junk files that must never be committed.
WHY:  Junk files bloat the repo, leak local paths, and cause pointless conflicts.
FIX:  Unstage with git rm --cached <file>; .gitignore already ignores these.
```

## The Commands

| Command | What it does |
|---|---|
| `./slopnet setup` | Connects your AI subscriptions so SlopNet can use them. |
| `./slopnet plan "idea"` | Asks the AI to write a step-by-step plan (`WAVES.md`) for your idea. |
| `./slopnet run` | Tells the AI crew to start coding the steps in the plan. |
| `./slopnet go "idea"` | Plans and runs your idea all at once. |
| `./slopnet verify` | Asks an AI to review finished work before you call it done. |
| `./slopnet sign` | Logs that you checked the work and approved it. |
| `./slopnet init` | Sets up SlopNet rules in a fresh repository. |

## Using Your Own AI Subscriptions

SlopNet connects to your existing AI subscriptions. Here is how SlopNet runs them headlessly:

| Agent | Command | How SlopNet connects |
|---|---|---|
| Claude Code | `claude` | `--dangerously-skip-permissions` |
| Codex CLI | `codex exec` | Auto-sandbox bypass flag |
| Gemini CLI | `gemini` | `--yolo` |
| Grok Build | `grok` | `--permission-mode bypassPermissions` |
| Hermes | `hermes` | `-z` (one-shot mode) |

## For Grown-Ups / Teams

- **Rulesets**: You can add your own project-specific rules to `rulesets/` and SlopNet will enforce them on every AI attempt.
- **CI**: The walls run identically in GitHub Actions or your own CI environment.
- **The Countersign Rule**: Work is only considered "DONE" when a different agent verifies it (`./slopnet verify`) and leaves a countersign in the register. You can never countersign your own work.
- **Org-only Push-rules**: You can enforce rules on `git push`, but note that this caveat applies to GitHub Organizations.

## Honest Limits

SlopNet is a powerful tool, but it does not do everything:
- It **does not** judge whether your idea is good or useful.
- It **cannot** catch a bug that your automated tests don't check for.
- It **needs** an active AI subscription (like Claude or Gemini) to do the coding work.
