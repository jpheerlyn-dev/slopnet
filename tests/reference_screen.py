#!/usr/bin/env python3
"""Render a recording with a known-good terminal emulator, for comparison.

This is the oracle. Feed it the same bytes at the same size as SlopNetConsole
and any difference is a fault in SlopNetConsole. It exists because two earlier
attempts to check the console's rendering by eye produced confident nonsense —
one compared a copy of the expected output with the cursor movements stripped
out of it, the other compared a screen against a scrollback.

    python3 -m venv /tmp/refterm && /tmp/refterm/bin/pip install pyte
    /tmp/refterm/bin/python tests/reference_screen.py recording.bin 108 38

Pair it with:

    PRINT_SCREEN=1 /tmp/picture recording.bin /tmp/shot.png
"""
import sys

import pyte


class Tolerant(pyte.Screen):
    """Real programs send sequences pyte does not accept.

    Zellij asks the terminal about its colour scheme with a private device
    status report, and pyte raises rather than ignoring it. An oracle that
    falls over on the recording it is meant to judge is no use, so the few
    sequences it cannot take are absorbed here. They are all questions, none
    of which change what is on the screen.
    """

    def report_device_status(self, *args, **kwargs):
        return None

    def define_charset(self, *args, **kwargs):
        return None


def main():
    if len(sys.argv) < 2:
        print("usage: reference_screen.py <recording.bin> [columns] [rows]",
              file=sys.stderr)
        return 2
    columns = int(sys.argv[2]) if len(sys.argv) > 2 else 108
    rows = int(sys.argv[3]) if len(sys.argv) > 3 else 38

    screen = Tolerant(columns, rows)
    stream = pyte.ByteStream(screen)
    stream.feed(open(sys.argv[1], "rb").read())
    for line in screen.display:
        print(line.rstrip())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
