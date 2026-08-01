# SlopNet — handing over

Updated 2026-08-01 for `v0.9.45`, for whoever picks this up next.

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
IBM Granite model is the always-present assistant. Coding CLIs and terminal
tools run on the server and appear in that console. LazyDocker can be installed
and version checked, but SlopNet deliberately does not open it: the locked
runtime account does not receive the host's Docker socket.

## Build, run, test

```bash
bash packaging/build_app.sh          # builds and installs the .app
```

Probes are single files compiled against the sources. They are not a framework.
Terminal-input probes drive real readers through real PTYs; replay probes feed
the retained bytes from real programs into the console while a harmless child
keeps its PTY alive. UI and branding probes exercise their focused native code.

```bash
clang -fobjc-arc -Wall -Wextra -framework AppKit -framework CoreText -I packaging \
  tests/console_prompt_probe.m packaging/SlopNetConsole.m packaging/SlopNetBrand.m \
  -o /tmp/p && /tmp/p
```

The eleven Objective-C probes are `brand_striped_probe`, `console_colour_probe`,
`console_grow_probe`, `console_keys_probe`, `console_menu_probe`,
`console_prompt_probe`, `console_replay_probe`, `console_scroll_probe`,
`launcher_tool_probe`, `settings_resize_probe` and `wizard_step_probe`. The
keys probe also compiles `SlopNetEntryView.m`, because it drives the actual
typing box. The launcher probe uses `-DSLOPNET_NO_MAIN` and all app sources.
Also compile and run `tests/pty_probe.c`. The Python probes run directly:

```bash
python3 tests/crew_unit_probe.py
python3 tests/server_safety_probe.py
/tmp/refterm/bin/python tests/console_resize_oracle.py
```

Run the full gating form before a release:

```bash
for c in checks/*.sh; do sh "$c" --all || exit; done
```

The pre-commit hook runs the staged-file form without `--all`. That is a fast
commit boundary, not a substitute for the full release command above or for
the terminal and server probes.

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
python3 -m venv /tmp/refterm && /tmp/refterm/bin/pip install pyte==0.8.2
/tmp/refterm/bin/python tests/reference_screen.py tests/zellij_recording.bin 94 40
```

Compare against the console's own screen:

```bash
clang -fobjc-arc -framework AppKit -framework CoreText -I packaging \
  tests/console_picture.m packaging/SlopNetConsole.m packaging/SlopNetBrand.m -o /tmp/picture
PRINT_SCREEN=1 /tmp/picture tests/zellij_recording.bin /tmp/shot.png 94 40
```

Any difference is a fault in `SlopNetConsole`. Compare **screen against screen** —
`screenTextForTesting`, not `textForTesting`. Comparing a screen with a
scrollback produced confident nonsense twice.

The retained recordings were made at **94 columns by 40 rows**. Replaying them
at 108×38 created the old 36-of-38 Zellij result by forcing row-40 output into
a 38-row screen. It was a bad experiment, not a live bottom-row fault. Use the
capture geometry in `tests/agy_recordings.md`, or make a new real recording at
the new geometry. `console_resize_oracle.py` starts at 94×40 and compares
deliberate width and height shrink operations with pyte.

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
- `packaging/SlopNetLauncher.m` — the window, the sidebar, the chat turn loop
  and the SSH plumbing.
- `packaging/SlopNetEntryView.h/.m` — the typing box and its `keyDown:`.
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

The earlier Linux server setup and local Granite guide were exercised on one
Ubuntu server. The v0.9.45 setup code now refuses unmarked name collisions,
installs a root-owned tagged checkout, and hands only the crew choice to the
locked runtime account; its exact embedded shells and fail-closed boundaries
have local executable probes, but this revised fresh-install path has not yet
been run end to end on an empty second server. Antigravity sign-in and
interactive chat have real recordings, but Antigravity is not yet a proved
unattended SlopNet build worker. At the recordings' real 94×40 geometry, `top`
and all 40 Zellij rows match pyte exactly.

Zellij, btop, LazyGit, Superfile, LazyDocker and Delta have SHA-256-pinned,
staged, exact-version-checked x86-64 Linux recipes proved on the configured
Ubuntu server. Their six exact `--version` shapes were read back there after
the byte digests were recorded.
The interactive tools except LazyDocker were opened there; Delta rendered a
diff. LazyDocker remains install/version-check only because granting Docker's
socket would cross the locked-account boundary.

## The immediate problem — resolved in v0.9.45

`SlopNetEntryView` now enters raw input whenever the child owns the alternate
screen. Every non-Command key goes straight to the PTY: ordinary characters,
arrows, Escape, Tab, Return and `Ctrl+A` through `Ctrl+Z` control bytes. The
typing box does not accumulate those characters. Outside the alternate screen,
the old line path remains: ordinary typing is buffered, Return sends the whole
line, and prompts can still collect passwords and confirmations.

`console_keys_probe` drives the real entry view and two real PTY readers. It
proves exact `0x07 0x70` delivery for Ctrl-G then `p` in raw mode, and proves
that the ordinary reader still receives a complete submitted line. Browser
sign-in keeps that entry view as first responder, and clearing or advancing a
sign-in also clears its old page/code controls. Keep both input halves whenever
this code changes.

## Open problems, worked in order

1. **Raw input mode — done.** See above.
2. **Five install commands — done for one platform.** btop 1.4.7, LazyGit
   0.63.1, Superfile 1.6.0, LazyDocker 0.25.2 and Delta 0.19.2 were downloaded
   from their official versioned assets, checked against the proved SHA-256,
   staged privately, executed for an exact version check, and only then moved
   into place on x86-64 Ubuntu. Zellij uses the same pattern. No recipe follows
   `latest` or pipes a download to a shell.
   LazyDocker was not opened and has no Open command, for the Docker-socket
   reason above.
3. **Zellij bottom row — the diagnosis was false.** The recording is 94×40 and
   both the baseline and current console match pyte 40/40 at that size. The old
   36/38 claim came from replaying it at 108×38. Cursor addressing is now
   clamped to the measured last cell, but describe that as terminal robustness,
   not as a live Zellij-row fix.
4. **A way out — done.** An interactive tool shows **Back to Granite**; choosing
   it stops the local SSH terminal and restores the composer after the child
   callback. Zellij is started with `--on-force-close detach`, so closing the
   Mac-side SSH connection leaves the named server session available to attach
   again. A real server attach, detach and reattach was proved.
5. **Granite always reachable — done for every launch path.** Granite is a
   permanent sidebar action. Settings tools and commands typed with `$` use the
   same interactive lifecycle. It is visible but deliberately disabled while
   protected setup, installation, planning, building or a Granite reply owns
   the terminal; those operations are not silently abortable.
6. **No full cell grid — bounded, not solved.** Addressed screens now remember
   measured columns and rows, clip right-edge cells on a shrink, keep the
   bottom of a height shrink, bound cursors, and send SIGWINCH only when the
   measured geometry changes. The four resize-oracle recordings match pyte
   after both 94×40→40×40 and 94×40→94×15. A fifth real chat recording also
   matches when it is resized mid-stream and the remaining captured cursor
   commands arrive afterwards. The representation is still strings, not
   a true cell grid: wide and combining glyphs, reflow after resize, growth
   after a dynamic SIGWINCH redraw, and exact UTF-16-index-versus-cell-width
   behaviour remain unproved.
7. **Robustness across servers — hardened, still deliberately narrow.** Setup,
   helpers, Settings tools and uninstall require Linux, a dedicated SSH key
   pair with its own local identity receipt, a dedicated proved known-hosts
   file, protected root-owned account/install/release receipts, the expected
   runtime home, and the exact app release. Runtime receipts bind UID, private
   GID, password lock, nologin shell, home device and inode; install receipts
   bind device, inode, release and commit. Privileged remote wrappers use
   absolute system commands and create the script under root rather than
   executing a login-user-owned temporary file. The release build injects the
   verified full commit from the exact tag namespace into the bundled
   installer, so a later moved tag is refused. Setup will not adopt a
   same-named account, install folder, key, unknown receipt directory or home.
   Project planning is staged under a private temporary name and published only
   after its plan commit succeeds. The build is then bound to that exact clean
   project commit. It also requires an exact protected `approved-build-v1`
   receipt for this release and commit before any coding agent can run;
   v0.9.45 deliberately has no live proof receipt, so that button fails closed.

   The live proof is still one x86-64 Ubuntu server. The v2 identity-receipt
   setup has not replaced the legacy receipts on that server: deliberately,
   there is no name-only automatic migration. It needs manual inspection and
   fresh preparation before this release's helpers will run there.
   ARM/Raspberry Pi, other distributions, other cloud providers and several
   simultaneous servers are not proved. The revised fresh-clone, local-key and
   v2-receipt setup has not been run from an empty second server. The UI states
   the platform limits; this handoff records the unproved fresh-install path.
   The Llama.cpp and provider-owned
   installers are still mutable upstream scripts rather than version-pinned
   binary assets.
   Antigravity is interactive-only until its unattended one-job invocation has
   a real edit proof. Re-preparing a server intentionally clears the mutable
   global crew choice, so a coding app must be proved again before a new plan;
   provider credentials and existing projects remain in the private runtime
   home.

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
