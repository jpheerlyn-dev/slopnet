# SlopNet — handing over

Written 2026-08-01, at `v0.9.44`, for whoever picks this up next.

## What it is, and who it is for

A Mac app that lets somebody with **no coding experience** build working
software using AI on their own private server. MIT licensed. The operator's own
framing, which is worth keeping in mind because it decides most arguments:

> I'm assuming most people are completely baffled about how to get started with
> this type of stuff… it could potentially have real benefit especially for
> folks in poorer countries.

The stated product idea is **managing servers using AI agents** — rapid
deployment for people who are not experts.

The shape: a Mac app with a left sidebar and one big console. The console is a
real terminal (a PTY) that runs things over SSH on the person's server. A local
IBM Granite model is the always-present assistant. Coding CLIs (Antigravity,
Claude Code, Codex, Grok) and terminal tools (Zellij, btop, LazyGit, Superfile,
LazyDocker, Delta) run on the server and appear in that console.

## Build, run, test

```bash
bash packaging/build_app.sh          # builds and installs the .app
```

Probes are single files compiled against the sources. They are not a framework;
each one runs a real program through a real PTY.

```bash
clang -fobjc-arc -Wall -Wextra -framework AppKit -framework CoreText -I packaging \
  tests/console_prompt_probe.m packaging/SlopNetConsole.m packaging/SlopNetBrand.m \
  -o /tmp/p && /tmp/p
```

Same pattern for `console_keys_probe`, `console_menu_probe`, `console_scroll_probe`,
`console_grow_probe`, `console_replay_probe`, `brand_striped_probe`. Two others
need different sources: `wizard_step_probe` wants `SlopNetWizard.m`, and
`crew_unit_probe.py` is `python3 tests/crew_unit_probe.py`.

Gating checks, which the pre-commit hook runs:

```bash
for c in checks/*.sh; do sh "$c" --all || echo "FAILED: $c"; done
```

Every change gets an entry in `register/<date>.md` — prose, what you changed,
what you proved, what you did not. `checks/register.sh` enforces that one exists.

## The verification discipline — read this before changing the console

This is the most valuable thing being handed over, and it was learned the
expensive way. Roughly a dozen releases went out where I was confident and
wrong, because I checked my work with tools that could not see the defect.

**Recordings, not fixtures.** `tests/*_recording.bin` are the exact bytes real
programs wrote to a pseudo-terminal on a real server — Antigravity signing in,
its colour picker, a chat exchange, `top`, Zellij. `tests/capture_login_recording.py`
makes new ones. Every fixture I invented by imagining what a program prints was
worthless; one of them passed with the fix removed.

**An oracle, not an opinion.** `tests/reference_screen.py` renders a recording
with `pyte`, a real terminal emulator.

```bash
python3 -m venv /tmp/refterm && /tmp/refterm/bin/pip install pyte
/tmp/refterm/bin/python tests/reference_screen.py tests/zellij_recording.bin 108 38
```

Compare against the console's own screen:

```bash
clang -fobjc-arc -framework AppKit -framework CoreText -I packaging \
  tests/console_picture.m packaging/SlopNetConsole.m packaging/SlopNetBrand.m -o /tmp/picture
PRINT_SCREEN=1 /tmp/picture tests/zellij_recording.bin /tmp/shot.png
```

Any difference is a fault in `SlopNetConsole`. Compare **screen against screen** —
`screenTextForTesting`, not `textForTesting`. Comparing a screen with a
scrollback produced confident nonsense twice.

**Chunk independence.** `console_replay_probe` replays each recording whole and
in 4096, 1024 and 137-byte pieces and requires identical screens. How bytes are
cut up is an accident of timing and must not change what is drawn. That single
invariant caught split escape sequences, split characters and a lost carry,
without anyone having to guess they existed.

**Look at pictures.** `console_picture.m` photographs the console. Whether block
characters tile is a question about pixels; text comparison cannot answer it.

## Where things live

- `packaging/SlopNetConsole.h/.m` — the PTY and the terminal emulator. Most of
  the difficulty is here.
- `packaging/SlopNetLauncher.m` — the window, the sidebar, the chat turn loop,
  the SSH plumbing, `SlopNetEntryView` (the typing box and its `keyDown:`).
- `packaging/SlopNetSettings.h/.m` — Settings, including the tools table with
  Install and Open buttons.
- `packaging/SlopNetBrand.h/.m` — panels, colours, the bundled colour font,
  provider marks.
- `packaging/SlopNetWizard.m` — the retro installer. The operator likes it; it
  stays.
- `packaging/tools.json` — the tools Settings offers. `install` runs on the
  server; `run` starts the tool in the console. **An empty `install` means
  nobody has verified that command.** Do not invent one; a wrong install command
  runs on somebody's server.
- `slopnet` — the Python CLI that lives on the server. Stdlib only.
- `packaging/slopnet-vps-*.sh` — onboarding and per-tool helpers.

## What works

Server setup from scratch; the local Granite guide; sign-in to Antigravity
carried through to a working chat; `top` and Zellij rendering correctly (36 of
Zellij's 38 rows match the oracle exactly); tools installable and startable from
Settings.

## The immediate problem

**A full-screen program opens but cannot be driven.** The operator can start
Zellij and nothing they press controls it.

The cause is in `SlopNetEntryView keyDown:` in `packaging/SlopNetLauncher.m`.
Only arrows, Escape, Tab, Enter-when-the-box-is-empty and **Ctrl-C** reach the
program. Every other control key falls through to `default: send = NO`. Zellij's
entire keybinding system is Ctrl-based — `Ctrl+g` to unlock, then `p`, `t`, `n`,
`h`, `s`, `o`, `q` — so none of it arrives. Ordinary characters go into the
typing box and are only sent as a whole line on Return, which is wrong for
anything reading keys as they come.

What it wants is a **raw input mode**: while a program has taken the alternate
screen, every keystroke goes straight to the PTY and the typing box steps aside.
The console already tracks that state — `onAlternateScreen` in
`SlopNetConsole.m` — so the trigger exists. Control keys map to their control
codes (`Ctrl+g` is 0x07, `Ctrl+a` is 0x01, and so on: letter minus 0x60).

Do not lose the line-based path. Sudo passwords, yes/no answers and questions to
Granite all depend on it, and `console_keys_probe` has a case for each kind of
reader. Both must keep passing.

## Open problems, in the order I would take them

1. **Raw input mode**, above. Nothing else about running tools matters until a
   person can drive one.
2. **The five unverified install commands** in `tools.json` — btop, LazyGit,
   Superfile, LazyDocker, Delta. Their release assets carry version numbers in
   the filename or use other archive formats, so each needs looking up and
   running once on a server before it ships. Zellij's is verified and is the
   pattern to follow.
3. **Zellij's bottom row.** 36 of 38 rows match the oracle; the last row should
   hold Zellij's shortcut bar and holds the pane frame instead. An off-by-one at
   the last row, not yet found.
4. **A way out of a running tool.** The prompt bar still says "Setting up
   Antigravity. Answer anything it asks below" with a "Skip this one" button
   long after setting up has finished. There is a Stop button, but nothing that
   reads as "close this and go back to Granite".
5. **Granite always reachable.** The operator's requirement is that a CLI tool
   must not take over the whole app. They chose **Zellij on the server** as the
   multiplexer over tabs in the app. Granite has to stay one action away
   whatever is running.
6. **No cell grid.** The console models the screen as an array of lines with a
   maintained origin, not a grid of cells. It gets `top` and Zellij right, but a
   program that depends on the screen being exactly as wide and tall as it was
   told will find edges.
7. **Robustness across servers.** The operator plans to test single-board
   computers, local servers and other cloud providers. Everything so far has
   been proved against one Ubuntu host.

## Traps that already caught me

- **Verifying colour work with the colour stripped out.** Seven false "fixed"
  claims came from `sed -E 's/\x1b\[[0-9;]*m//g'` dumps.
- **`[SlopNetBrand colorFontActive]` reads the font from the main bundle.** A
  bare test binary has no bundle, so probes silently exercised the plain-text
  fallback instead of the real path.
- **Piping `git commit` through `grep`.** It hides failures. Two releases were
  tagged on the wrong commit and shipped without their fix. Verify the tag
  contains the change *before* pushing: `git show <tag>:path | grep …`.
- **`initWithBytes:encoding:` does not reliably fail on a truncated tail.** It
  drops the partial character and returns the rest, which silently corrupts
  every later read. `wholeCharacterBytes` in `SlopNetConsole.m` exists for this.
- **The operator's passing remarks are usually the diagnosis.** "Enter works but
  arrows don't" was application cursor key mode. "It looks fine for a split
  second then breaks" was a line feed resetting the column. Both were worth more
  than a day of my own looking.

## Decisions already made — do not re-litigate

- **No split panes.** "Keep the chat UI with left side panel — the chat terminal
  IS the hacker terminal."
- **Zellij on the server** does the multiplexing, not tabs in the app.
- **Foundations before features.**
- The wizard installer stays. RiveScript as a knowledge wizard, branded as one
  character with Granite, is agreed in principle and not built.
- Settings is the control panel Granite will eventually be allowed to operate.
  Granite has memory and can read the terminal; it has **no** ability to act
  yet, deliberately.
- Never print the server address on screen. Masked field with a reveal button.
- Say "Server", not "VPS".

## Style

Comments explain **why**, especially where the reason is not obvious from the
code — several in `SlopNetConsole.m` record what broke and how it was proved, so
the next person does not repeat it. Match the surrounding density. The operator
dislikes invented interface copy and filler; write what is true and stop.
