# SlopNet

SlopNet is a starter project that lets an AI write code for you, while safety checks block messy or broken files from being saved.

## A 30-second demo

After install (and after you have met your crew once), this is the everyday path:

```bash
git clone https://github.com/jpheerlyn-dev/slopnet.git my-app
cd my-app
./slopnet go "a one-page HTML file named hello.html that says Hello, world"
```

**What you will see** (real run on 2026-07-29, Codex as planner and writer):

```text
Using the existing crew: codex plans, 1 agent(s) write.
[planner] codex is thinking about: a one-page HTML file named hello.html that says Hello, world...
[planner] WAVES.md: 1 waves, 1 tasks. Read it before you run it.

Here is the plan:
### T1-create-hello-page
Files: hello.html
Create a complete one-page HTML document that displays the text “Hello, world”. …

Run this? (y/n/edit) [y]
--- Wave 1 of 1 ---
  T1-create-hello-page  codex  working…
  T1-create-hello-page  codex  checking…
  T1-create-hello-page  codex  MERGED

Work report
Merged: T1-create-hello-page
Failed: nothing
Walls: green.
Next: git log --oneline --max-count=5
```

That run created `hello.html` with **Hello, world**. Open it in a browser to check.  
If you have never run setup, `./slopnet go "…"` starts the crew meeting first. That is normal.

## Install

### 1. Open Terminal on a Mac

Press **Cmd + Space**, type `Terminal`, press **Enter**.

### 2. Check for Python and Git

```bash
python3 --version
git --version
```

You want answers like `Python 3.12.0` and `git version 2.x`.  
If macOS offers developer tools, accept them. Or run `xcode-select --install`, then check again.

### 3. Install and log into one AI coding app

SlopNet does not write the code by itself. It drives an AI app you already pay for. Install **one** and **log in** so it works from Terminal (not only on a website):

| App | Program name |
|---|---|
| Claude Code | `claude` |
| Codex CLI | `codex` |
| Gemini CLI | `gemini` |
| Grok Build | `grok` |
| Kimi Code | `kimi` |
| Hermes | `hermes` |

A subscription alone is not enough. The app must be installed, on your PATH, and logged in. If setup says “not logged in” or “not proven,” finish login and run `./slopnet setup` again.

### 4. Download this project

```bash
git clone https://github.com/jpheerlyn-dev/slopnet.git my-app
cd my-app
```

`git clone` means “copy this project onto my computer.”  
`cd my-app` means “go into that folder.”

This folder **is** your project. It already includes the safety checks (the “walls”). You build features here. Side experiments that should stay separate can use `./slopnet orbit` later (see Grown-ups).

### 5. Run SlopNet from this folder (or from anywhere)

From inside `my-app`:

```bash
./slopnet doctor
```

The `./` means “run the `slopnet` program in this folder.”

To type `slopnet` without `./` **in this Terminal window only**:

```bash
export PATH="$(pwd):$PATH"
slopnet --version
```

That prints `slopnet 0.2`. Closing Terminal forgets PATH; run the export again next time, or add it to your shell startup file when ready.

## Your first project

Stay in the `my-app` folder.

### Meet your crew

```bash
./slopnet setup
```

SlopNet lists AI apps it found, asks who should **plan**, who should **write**, and what test command you use (press Enter for “walls only”). Then it proves agents can edit a file.

Real excerpt (2026-07-29, Codex for both roles — type `2` if Codex is option 2 on your list):

```text
Let's meet your crew.
Found on this machine:
  - claude (logged-in CLI)
  - codex (logged-in CLI)
  …

Who should PLAN the work? (best thinker) [1]
> 2
Who should WRITE the code? (pick one or more, comma-separated) [1]
> 2
What command runs your tests? [walls only]
>

Proving the selected agents in throwaway git repos:
[OK] codex — wrote the file in 7s

Crew saved to .slopnet/crew.json.
Next: slopnet plan "what you want built"
```

### Build something small

```bash
./slopnet go "a one-page HTML file named hello.html that says Hello, world"
```

Read the plan. Press **Enter** (or `y`) to run it. When you see `MERGED` and `Walls: green`:

```bash
open hello.html
```

`open` is the Mac command that opens a file in the usual app (your browser).

Real file from that session (shortened only for space; the full file is valid HTML):

```html
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Hello, world</title></head>
<body><main><h1>Hello, world</h1></main></body>
</html>
```

Try other short ideas the same way once this path works.

## What just happened

**The crew.** One AI writes a plan into `WAVES.md` (a short list of steps). Agents write code for those steps in private copies of the project so a bad try does not wreck your files.

**The walls.** Before new code is kept, fixed safety checks run. Broken, messy, or secret-leaking files are blocked. The walls decide; the AI does not grade its own work.

**The register.** A day log under `register/` records what ran. You can always look back at who did what.

## When something says no

That is the tool protecting you, not you “breaking” Terminal. Real check when a junk file was staged:

```text
[!!] junk.sh
RULE: Thumbs.db are junk files that must never be committed.
WHY:  Junk files bloat the repo, leak local paths, and cause pointless conflicts.
FIX:  Unstage with git rm --cached <file>; .gitignore already ignores these.
A wall said no — read its FIX line.
```

Read **RULE**, **WHY**, and **FIX**. Do the FIX. Then try again.

## The commands

Every command today. Use `./slopnet …` from your project folder (or `slopnet …` if you set PATH).

| Command | What it does |
|---|---|
| `./slopnet init` | Arms this folder: hooks, register, basic health. |
| `./slopnet doctor` | Health checklist. `--fix` repairs what it safely can. |
| `./slopnet check` | Runs the walls now (`--all` for the full set). |
| `./slopnet setup` | Finds your AI apps, proves them, saves the crew. |
| `./slopnet plan "idea"` | Writes a step-by-step plan to `WAVES.md`. |
| `./slopnet run` | Runs the plan: agents code, walls (and tests) judge. |
| `./slopnet go "idea"` | Setup if needed, plan, ask you, then run. |
| `./slopnet sign "note"` | Appends your note to today’s register file. |
| `./slopnet pending "question"` | Files a question for the human operator. |
| `./slopnet verify` | Re-runs proofs and countersigns the register (a **different** agent than the one who did the work). |
| `./slopnet orbit new NAME` | Starts a small side-idea repo next door (operator names it). |
| `./slopnet adapt` | Wires coding tools found in this checkout. |
| `./slopnet mcp` | Serves the same tools over MCP (for editors that speak MCP). |

## Using your own AI subscriptions

SlopNet only drives tools it can run in Terminal. Headless forms checked on this project:

| Agent | How SlopNet runs it |
|---|---|
| Claude Code | `claude --dangerously-skip-permissions -p "…"` |
| Codex CLI | `codex exec --dangerously-bypass-approvals-and-sandbox "…"` |
| Gemini CLI | `gemini --yolo -p "…"` |
| Grok Build | `grok --permission-mode bypassPermissions -p "…"` |
| Kimi Code | `kimi -p "…"` (prompt mode uses auto permission) |
| Hermes | `hermes -z "…"` (one-shot mode) |

**zAI GLM coding plan:** set `ZAI_API_KEY` in your shell. SlopNet can reach it through Claude Code as `zai-glm` (Coding Plan quota). See `CREW.md`. Tokens are never written into the repo.

You only need **one** proven agent. Run `./slopnet setup` after you log in.

## For grown-ups / teams

- **Rulesets:** project rules under `rulesets/` ride with the walls.
- **CI:** the same walls run in GitHub Actions (`.github/workflows/`).
- **Countersign:** work is done only when a *different* agent runs `./slopnet verify` and leaves a countersign in `register/`. Never countersign your own work.
- **Push protection:** requiring checks on `git push` is a GitHub **Organization** feature; personal repos may not get full push rulesets.
- **Orbit:** side ideas get their own small repos (`./slopnet orbit new NAME`) so the main project stays stable. Naming is the operator’s job.

## Honest limits

- SlopNet does **not** judge whether your idea is good.
- It **cannot** catch a bug your tests never look for. With no test command, only the walls judge.
- It **needs** a working AI coding login to write code.
- Short, concrete asks (file name + what it should show) work best.
