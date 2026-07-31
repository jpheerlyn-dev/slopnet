#!/usr/bin/env python3
"""A menu that redraws itself in place, the way command-line tools do.

Antigravity's sign-in menu marched down the screen instead of redrawing,
leaving a trail of prompt markers and overwriting its own hint line. Guessing
which escape sequence it uses would only prove the guess, so this fixture
draws the same menu three ways — the three ways such a menu is normally
written — and console_menu_probe checks the console renders each of them as
one menu rather than a cascade.

Run by the probe, not by hand. Takes a style as its argument:

  up        move the cursor back up over the old frame and write the new one
  save      remember where the menu starts, come back to it each time
  screen    a full-screen program: its own screen, redrawn from the top
"""
import sys
import termios
import tty

STYLE = sys.argv[1] if len(sys.argv) > 1 else "up"
ITEMS = ["Google OAuth", "Use a Google Cloud project"]
LINES = len(ITEMS) + 1


def frame(selected):
    rows = ["\033[2KSelect login method:\r\n"]
    for i, item in enumerate(ITEMS):
        marker = "> " if i == selected else "  "
        rows.append("\033[2K%s%d. %s\r\n" % (marker, i + 1, item))
    return "".join(rows)


def draw(selected, first):
    if STYLE == "up":
        if not first:
            sys.stdout.write("\033[%dA" % LINES)
        sys.stdout.write(frame(selected))
    elif STYLE == "save":
        sys.stdout.write("\0337" if first else "\0338")
        sys.stdout.write(frame(selected))
    else:
        if first:
            sys.stdout.write("\033[?1049h")
        sys.stdout.write("\033[H\033[2J" + frame(selected))
    sys.stdout.flush()


fd = sys.stdin.fileno()
saved = termios.tcgetattr(fd)
try:
    tty.setraw(fd)
    selected = 0
    draw(selected, True)
    while True:
        keys = sys.stdin.read(3)
        if not keys or keys[0] in ("\r", "\n", "q"):
            break
        if keys.endswith("B"):
            selected = min(selected + 1, len(ITEMS) - 1)
        elif keys.endswith("A"):
            selected = max(selected - 1, 0)
        draw(selected, False)
finally:
    termios.tcsetattr(fd, termios.TCSADRAIN, saved)
    if STYLE == "screen":
        sys.stdout.write("\033[?1049l")
        sys.stdout.flush()
