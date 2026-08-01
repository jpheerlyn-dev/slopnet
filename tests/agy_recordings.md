# Recordings of real programs

Every byte Antigravity CLI 1.1.9 wrote to a pseudo-terminal 94 columns wide on
a Linux server. The first is `agy login`, up to the point where it shows a
sign-in link and waits for a code. The second is the colour scheme picker shown
on first run after signing in — a full-screen frame with a menu beside a live
preview, redrawn on every keypress. Captured by `capture_login_recording.py`,
which is kept beside them so they can be remade when the CLI changes.

It exists because four attempts at this bug were verified against fixtures
invented from a guess at what the program prints, and one of those fixtures
passed with the fix removed — it was not reproducing the failure at all. This
is the real output, so `console_replay_probe` checks the console against what
Antigravity does rather than against what I assumed it does.

The probe replays each whole and in 4096, 1024 and 137-byte pieces, and checks
two things: that the address picked out is the one the program printed, and
that the screen drawn is the same whichever way the bytes are cut up.

Both mattered. The address used to depend on where a read landed — three of the
four sizes gave a different, broken one, because a link was read the moment
part of it appeared. And an escape sequence split across two reads used to lose
its ESC, so "[19;34H" was printed as text while the cursor move it asked for
never happened, and every frame after it landed somewhere wrong.

How the bytes are cut up is an accident of timing. It must not change what is
drawn, and that invariant is worth more than any assertion about a particular
screen: it catches anything the parser fails to carry from one read to the
next, without needing to know in advance what that might be.

Nothing here is private. The request is one the capture itself created, the
client id belongs to Google's own application and is public by design, and the
challenge and state are single-use values from a sign-in nobody completed. The
server address does not appear.


## top_recording.bin

Eight seconds of `top` on the same server, at the same width. It is here
because it is an ordinary full-screen program of the kind the whole tool list
is made of — btop, lazydocker, superfile, lazygit, zellij — and none of the
Antigravity recordings exercise what those do: a screen addressed by row
number, repainted several times a second, with the cursor put back to the top
between frames.

It found something within a minute of being replayed. `ESC ( B` names a
character set and is two characters long; this console read the bracket and
printed the B, so every row of `top` came out peppered with stray Bs. Anything
built on ncurses emits that sequence constantly, so it would have marked every
tool on the list.

## zellij_recording.bin

Twelve seconds of Zellij 0.44.3 on the same server. It is the multiplexer the
operator chose for running several tools at once, so it is the program this
console most has to get right, and it is the most demanding one on the list:
six hundred absolute cursor moves, a scrolling region, mouse reporting, its own
screen, and questions asked of the terminal.

It rendered as a completely blank screen. Zellij wraps nearly everything it
draws in hyperlinks, and a hyperlink ends with ESC backslash rather than a
bell; this console looked only for the bell, so the search ran off the end and
swallowed the lot. Sixty-four kilobytes arrived and one character was drawn.

Checked against `reference_screen.py` rather than by eye: thirty-six of its
thirty-eight rows now match a known-good terminal exactly. The two that differ
are the bottom row, where Zellij puts its shortcut bar and this console still
has the pane frame — an off-by-one at the last row, not yet found.
