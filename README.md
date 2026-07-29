# SlopNet

SlopNet is intended to make VPS-based AI software building easy. You describe
a small thing you want built; agents write the files on the VPS, and safety
checks (we call them **walls**) block messy or broken work from being kept.

## The simple promise — and the honest current status

The finished product should let a newcomer bring only a private VPS and one
AI coding subscription. One guided setup should ask permission before it
installs tools, take them through each provider's normal login, prove one
harmless edit on the VPS, and then keep all agent work, tests, and credentials
off their laptop.

**This checkout is not there yet.** One real VPS vertical slice is now proved:
on **REDACTED**, guided Linux setup kept credentials in the private non-root
runtime account and Codex completed a disposable workspace-only edit in 16
seconds. On Ubuntu 24.04, if AppArmor blocks that sandbox, setup asks before it
installs and loads Ubuntu's Bubblewrap-only profile; it does not turn off the
VPS-wide restriction. That profile gives `/usr/bin/bwrap` the setup permissions
it needs while its sandbox child loses capabilities. The strict Docker safety
gate is also proved.

That is evidence for one Codex path, not a release claim. It is not yet a
broad multi-provider runtime or a beginner-ready release, and the current Mac
control app still hands the detailed setup conversation to Terminal. The long
walkthrough later in this file is preserved as the historical local-development
route for contributors. It is not the product flow we should ask a new user to
follow or market as beginner-ready.

The current build priority is making that proved path pleasant inside the Mac
control app, then adding exactly one real project flow with tests. Only after
that should SlopNet broaden to more providers or Hermes, OpenClaw, and Buzz
integrations.

## VPS-first policy

SlopNet's execution home is a private VPS: coding agents, tests, builds,
worktrees, long-running services, and their credentials belong there. Your
Mac is the control screen, connected over SSH; it must not absorb an
agent's tool load or hold the project's running services.

This checkout is moving from its earlier local-first implementation to that
model. Until remote execution is enforced by the program, a local
`slopnet go` run is a development check, not the intended user workflow.

### Mac control app (early shell)

The source checkout can build a real Mac application with a Dock icon and a
small VPS connection screen:

```bash
./packaging/build_app.sh "$HOME/Applications"
```

Open `SlopNet.app` from your Applications folder. It asks whether you already
have a VPS, offers Hetzner, Contabo, and Hostinger links if you do not, then
collects only the host, SSH username, and port. It opens Terminal for the
normal SSH password prompt, creates a dedicated passphrase-protected SSH key,
adds it to the macOS Keychain when available, and begins the guided VPS setup.
It never receives or stores a VPS password. This is an early control shell, not
a promise that every VPS or coding CLI has passed the required proof.

The Terminal guide has three numbered steps: protect the connection key,
confirm the VPS, and prepare the VPS. You do not need to type an SSH command or
interpret Git output. If it stops, copy the final plain-English message rather
than the whole Terminal transcript.

When SlopNet asks whether to continue, type `y` only after its sentence says
exactly what it will change. That confirmation comes from the VPS itself and
protects you from accidental setup changes.

The first time you press **Connect and begin guided VPS setup**, macOS asks
whether SlopNet may control Terminal. Choose **Allow**: that permission is only
used to open a Terminal window for the setup you explicitly started. If you
previously chose not to allow it, open **System Settings → Privacy & Security →
Automation**, find SlopNet, and turn on Terminal.

Use **Test Terminal access** first if you want to check that permission before
you enter any VPS details. It opens only a harmless message in Terminal: no
connection, password prompt, or SSH key is involved.

### Container gate (available now)

SlopNet now has a locked-down Docker gate for the VPS. It runs the walls in
an offline, non-root container with a read-only operating system, no extra
Linux powers, no Docker socket and strict resource limits. Once Docker Engine
and its Compose plugin are installed on the VPS, stand in this folder there
and run:

```bash
docker compose run --rm slopnet check --all
```

After guided setup, the Docker gate should use the same locked runtime account
as SlopNet itself. The following is the tested **REDACTED** pattern; it does not
create an SSH user or change root access:

```bash
cd /opt/slopnet
SLOPNET_UID=$(id -u slopnet) SLOPNET_GID=$(id -g slopnet) \
  docker compose run --rm slopnet check --all
```

This lets the container stay non-root while Git treats its mounted project as
safe. Do not set `SLOPNET_UID` or `SLOPNET_GID` to `0`; a different workspace
needs its own non-root matching IDs instead.

This is intentionally a **gate**, not the AI coding room: the container has
no network and no provider logins, so it cannot run `slopnet go`. That keeps
the first container useful even before the separate, credentialed agent
runtime has been designed and proven. Every image is also built and scanned
for fixable high/critical vulnerabilities in GitHub Actions.

### Why the name?

In AI chat, “slop” often means low-quality generated junk. **SlopNet’s job is the opposite:** only work that passes the walls is allowed to stay. The name is a reminder of the problem; the walls are the fix.

### Who this guide is for

You do **not** need to know GitHub, “repos,” coding agents, or the Terminal already.  
This page assumes you can:

- turn on a computer  
- open a web browser  
- type on a keyboard  

That’s enough. Every new word is explained the first time it appears.

**The historical walkthrough below is a Mac-local development path.** It does
not control the VPS or meet the product promise above.

---

## Words we will use (read this once)

| Word | Plain meaning |
|---|---|
| **Folder** | A place that holds files, like a shoebox for documents. On a Mac, Finder shows folders. |
| **File** | One document on the computer (for example `hello.html`). |
| **Terminal** | A simple window where you type commands and press Enter. The computer answers with text. |
| **Command** | One line you type in Terminal. Example: `python3 --version`. |
| **Git** | A free tool that tracks changes to files. SlopNet uses it heavily. |
| **GitHub** | A website that stores project copies on the internet so you can download them. |
| **Clone** | “Download a full copy of a project onto my computer.” |
| **AI coding app** | A program you install and log into. It can edit project files when SlopNet asks it to. Not the same as only chatting on a website. |
| **Crew** | Your chosen AI apps for this project: who **plans**, who **writes** code. Saved after `./slopnet setup`. |
| **Walls** | Automatic safety checks. They can say **no** and tell you how to fix it. |
| **Plan / WAVES.md** | A short checklist the AI writes before coding. You read it and approve it. |
| **MERGED** | This attempt passed the walls and was kept in your project. Success for that step. |

You will almost always run SlopNet as:

```bash
./slopnet …
```

The `./` means “the program named `slopnet` **in this folder**.”  
Stay inside your project folder when you type these commands.

---

## Historical local-development path (not the beginner product)

This is evidence for the earlier local implementation. It can help a
contributor reproduce that route, but it keeps agents and credentials on the
Mac and therefore does not meet the VPS-first product policy above. Do **not**
present it to a newcomer as the finished SlopNet experience.

### Step 0 — Get an AI coding app ready

SlopNet does **not** invent code by itself. It drives an AI coding app **you** install and log into.

1. Pick **one** app you can install on your Mac (any one is enough to start):

   | App people use | Program name in Terminal |
   |---|---|
   | Claude Code | `claude` |
   | Codex (OpenAI) | `codex` |
   | Gemini CLI | `gemini` |
   | Grok Build | `grok` |
   | Kimi Code | `kimi` |
   | Hermes | `hermes` |

2. Install it using that product’s own install page (search the web for the name + “CLI install” or “Terminal install”).
3. **Log in** the way *that* app tells you (often a `login` command or a browser window).
4. Open Terminal (Step 1) and check the program answers. Example if you installed Codex:

   ```bash
   codex --version
   ```

   You should see a version line, not `command not found`.  
   A paid website subscription **alone** is not enough. Terminal must see the program.

If this step fails, fix the AI app first. SlopNet cannot help until one app is installed and logged in.

### Step 1 — Open Terminal on a Mac

1. Press **Command (⌘) + Space** together.  
2. Type `Terminal`.  
3. Press **Enter**.  

A window appears. That is Terminal. You type on the line that ends with a blinking cursor.

### Step 2 — Check two tools: Python and Git

Type this line, then press **Enter**:

```bash
python3 --version
```

You want a line like `Python 3.12.0`.  
**Python 3.9 or newer is fine.** If the number starts with 3 and is 9 or higher, continue.

Then:

```bash
git --version
```

You want a line like `git version 2.50.1`. Any modern 2.x is fine.

**If macOS shows a popup** about installing developer tools: click **Install** and wait until it finishes. Then run the two version commands again.

**If there is no popup and a command fails**, try:

```bash
xcode-select --install
```

Wait until that install finishes, then check the versions again.

### Step 3 — Download this project (clone)

Still in Terminal, type these three lines, one at a time, pressing **Enter** after each:

```bash
cd ~
git clone https://github.com/jpheerlyn-dev/slopnet.git my-app
cd my-app
```

What that means:

| Piece | Meaning |
|---|---|
| `cd ~` | Go to your home folder (a safe starting place). |
| `git clone … my-app` | Copy the SlopNet project from GitHub into a **new** folder named `my-app`. |
| `cd my-app` | Enter that folder. Your next commands apply here. |

If Terminal says the folder `my-app` already exists, pick another name:

```bash
git clone https://github.com/jpheerlyn-dev/slopnet.git my-app2
cd my-app2
```

**What did you download?**  
A ready-made **project folder** that already includes SlopNet’s safety walls.  
You build *your* small programs **inside** this folder.  
(It is not only a tool sitting somewhere else on the Mac.)

### Step 4 — Quick health check

```bash
./slopnet doctor
```

You want several lines that start with `[OK]`.  
A line with `[??]` about GitHub branch protection is common on a personal laptop and does **not** block your first project.  
If almost everything is `[!!]` or the command is not found, make sure you typed `cd` into `my-app` first.

### Step 5 — Meet your crew (one-time per project)

```bash
./slopnet setup
```

SlopNet will:

1. List AI coding apps it can see on your Mac.  
2. Ask who should **plan** (think of steps).  
3. Ask who should **write** the files (can be the same app).  
4. Ask what command runs your tests — for your first try, just press **Enter** (“walls only”).  
5. Run a tiny proof that the app can create a file.

Type the **number** next to the app you installed.  
Example: if Codex is option `2`, type `2` and press Enter for planner, then `2` again for writer.

Real excerpt from a working session (2026-07-29):

```text
Let's meet your crew.
Found on this machine:
  - claude (CLI detected — proof required)
  - codex (CLI detected — proof required)
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
```

- `[OK]` means that app is **proven** for this project.  
- “CLI detected” only means SlopNet found the program. The proof still has
  to confirm its login and edit permission.
- If you see `[!!] … not logged in`, go back to Step 0, finish login, run `./slopnet setup` again.  
- The “throwaway” proof uses a temporary folder; it does not mess up `my-app`.

(If setup’s last line says “Next: slopnet plan …”, you can ignore that for now. This guide’s next step is `go`, which plans **and** runs.)

### Step 6 — Build a tiny real page

Stay in `my-app`. Type this **exact** line (you can copy and paste it):

```bash
./slopnet go "a one-page HTML file named hello.html that says Hello, world"
```

What happens:

1. The **planner** (one AI) writes a short plan into a file named `WAVES.md`.  
2. Terminal shows the plan. Read it.  
3. When you see `Run this? (y/n/edit) [y]`:  
   - press **Enter** (or type `y`) to run the plan  
   - type `n` to stop without building  
   - type `edit` only if you know how to edit a text file in Terminal  
4. The **writer** AI works. You may see words like `working…`, `checking…`, then `MERGED`.  
5. **Walls: green** means the safety checks passed.

Real output from that exact ask (2026-07-29, Codex as planner and writer):

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

**You do not have to run** the `git log` line. It is only a suggestion if you are curious about recent saves.

### Step 7 — Open what you built

On a Mac, still in `my-app`:

```bash
open hello.html
```

Your browser should show a page that says **Hello, world**.

Real file from that session:

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Hello, world</title>
</head>
<body>
  <main>
    <h1>Hello, world</h1>
  </main>
</body>
</html>
```

If that worked: you have finished the first-time path.  
Try another short idea the same way:

```bash
./slopnet go "a file named notes.txt that contains three short todo items"
```

Use **short, concrete** asks: name the file and say what it should contain.

---

## Historical local everyday use

You already have the `my-app` folder and a saved crew. Next time:

1. Open Terminal.  
2. Go into the project:

   ```bash
   cd ~/my-app
   ```

   (Use `my-app2` or whatever folder name you chose.)

3. Ask for the next thing:

   ```bash
   ./slopnet go "your short idea here"
   ```

4. Read the plan, press **Enter** to approve, wait for `MERGED` and `Walls: green`.

You do **not** need to clone again.  
You do **not** need setup again unless you want different AI apps or an app stopped being logged in.

**Brand-new clone on another computer:** start again from Step 0.  
On a **fresh** clone, `./slopnet go "…"` will run setup for you if no crew exists yet. That is normal. The first-time steps above still help you understand each question.

---

## What the historical local path did

**The crew.**  
One AI writes a plan (`WAVES.md`). One or more AIs write files for those steps. They work in private copies of the project first, so a bad try does not immediately wreck your main files.

**The walls.**  
Before work is kept, fixed safety checks run. Messy files, secrets, and other forbidden junk are blocked. The walls decide; the AI does **not** grade its own work.

**The register.**  
Under `register/` is a day-by-day log of what ran. You can open those text files later to see history.

---

## When something says no

A red or `[!!]` message is often the walls **protecting** you, not you “breaking” the computer.

Real example when a junk file was staged on purpose:

```text
[!!] junk.sh
RULE: Thumbs.db are junk files that must never be committed.
WHY:  Junk files bloat the repo, leak local paths, and cause pointless conflicts.
FIX:  Unstage with git rm --cached <file>; .gitignore already ignores these.
A wall said no — read its FIX line.
```

Read three lines every time:

1. **RULE** — what was refused  
2. **WHY** — why it matters  
3. **FIX** — what to type or do next  

Do the FIX, then try your command again.

---

## Local implementation commands

Every SlopNet command today.  
Run them from inside your project folder as `./slopnet …`.

| Command | What it does |
|---|---|
| `./slopnet init` | Arms this folder (hooks, log folder, basic health). |
| `./slopnet doctor` | Health checklist. Add `--fix` to repair what it safely can. |
| `./slopnet check` | Runs the walls now. Add `--all` for the full set. |
| `./slopnet setup` | Finds AI apps, proves them, saves your crew. |
| `./slopnet plan "idea"` | Writes a step-by-step plan only (`WAVES.md`). |
| `./slopnet run` | Runs an existing plan: agents code, walls (and tests) judge. |
| `./slopnet go "idea"` | Setup if needed, plan, ask you, then run. |
| `./slopnet sign "note"` | Adds your note to today’s log in `register/`. |
| `./slopnet pending "question"` | Files a question for the human project owner. |
| `./slopnet verify` | Re-runs proofs and countersigns the log (use a **different** AI than the one that did the work). |
| `./slopnet orbit new NAME` | Starts a small side-idea project next door (the human picks the name). |
| `./slopnet adapt` | Connects coding tools found in this folder. |
| `./slopnet mcp` | Serves the same tools over MCP (for editors that speak that protocol). |

---

## Historical local subscription setup

SlopNet only drives tools it can start from Terminal.  
These are the unattended forms this project was checked with (the long flags let the AI edit files without clicking “allow” every time):

| App | How SlopNet runs it |
|---|---|
| Claude Code | `claude --dangerously-skip-permissions -p "…"` |
| Codex | `codex exec --sandbox workspace-write "…"` |
| Gemini CLI | `gemini --yolo -p "…"` |
| Grok Build | `grok --permission-mode bypassPermissions -p "…"` |
| Kimi Code | `kimi -p "…"` |
| Hermes | `hermes -z "…"` |

**zAI GLM coding plan:** set `ZAI_API_KEY` in your shell environment. SlopNet can reach it through Claude Code as worker `zai-glm`. Details live in `CREW.md`. Tokens are never written into project files.

You only need **one** proven app. Run `./slopnet setup` after you log in.

---

## Historical local use on other computers

| You use | Notes |
|---|---|
| **Mac** | Follow the main guide. `open hello.html` opens the browser. |
| **Linux** | Same `git clone` and `./slopnet` flow if `python3` and `git` exist. Open the page with `xdg-open hello.html` (or double-click the file in your file manager). |
| **Windows** | Use Git Bash or WSL so `python3`, `git`, and `./slopnet` behave like this guide. Open `hello.html` with File Explorer or `start hello.html` in Command Prompt. Install a Windows build of your AI coding app and confirm it runs in that same Terminal. |

If a platform-specific install step is missing, that is a documentation gap — file it with `./slopnet pending "…"`.

---

## For teams and advanced use

- **Rulesets:** extra project rules can live under `rulesets/` and run with the walls.  
- **CI:** the same walls can run in GitHub Actions (see `.github/workflows/`).  
- **Countersign rule:** work counts as done only when a *different* agent runs `./slopnet verify` and leaves a countersign in `register/`. Nobody countersigns their own work.  
- **Push protection:** forcing checks on `git push` is mainly a GitHub **Organization** feature; a personal repo may not get full push rules.  
- **Orbit:** experimental side ideas get their **own** small project (`./slopnet orbit new NAME`) so the main folder stays stable. Only the human operator chooses names.

---

## Honest limits

- SlopNet does **not** decide whether your idea is good or useful.  
- It **cannot** catch a bug that nobody wrote a test for. With “walls only,” only the safety checks judge.  
- It **needs** a working AI coding login. No login means no crew.  
- Short, concrete asks work best: name the file and say what should be inside.  
- Sample output above came from **Codex** on one machine. Your app names and timing will differ; look for `MERGED` and `Walls: green`, not identical wording.

---

## Optional later: type `slopnet` without `./`

You can ignore this forever and keep using `./slopnet`.

If you want the shorter form **in the current Terminal window only**:

```bash
export PATH="$(pwd):$PATH"
slopnet --version
```

That should print `slopnet 0.2`.  
Closing Terminal forgets this. Making it permanent means editing a shell startup file (for example `~/.zshrc` on many Macs). Only do that when you are comfortable editing settings files.
