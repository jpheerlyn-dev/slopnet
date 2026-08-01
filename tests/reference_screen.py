#!/usr/bin/env python3
"""Render a recording with a known-good terminal emulator, for comparison.

This is the oracle. Feed it the same bytes at the same size as SlopNetConsole
and any difference is a fault in SlopNetConsole. It exists because two earlier
attempts to check the console's rendering by eye produced confident nonsense —
one compared a copy of the expected output with the cursor movements stripped
out of it, the other compared a screen against a scrollback.

    python3 -m venv /tmp/refterm && /tmp/refterm/bin/pip install pyte==0.8.2
    /tmp/refterm/bin/python tests/reference_screen.py recording.bin 94 40

An optional final byte count compares an exact point in a real recording.
Two more arguments resize that rendered screen for checking terminal geometry.
An optional ``continue`` argument then feeds the rest of the same recording,
so cursor movement after a real mid-stream resize can be compared too:

    reference_screen.py recording.bin 94 40 64344 40 40
    reference_screen.py tests/agy_chat_recording.bin 94 40 1014 40 40 continue

Pair it with:

    PRINT_SCREEN=1 /tmp/picture recording.bin /tmp/shot.png
"""
import sys
from importlib.metadata import PackageNotFoundError, version

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
    try:
        pyte_version = version("pyte")
    except PackageNotFoundError:
        pyte_version = "missing"
    if pyte_version != "0.8.2":
        print(f"terminal oracle requires pyte==0.8.2 (found {pyte_version})",
              file=sys.stderr)
        return 2
    if len(sys.argv) < 2:
        print("usage: reference_screen.py <recording.bin> [columns] [rows] "
              "[bytes [resize-columns resize-rows [continue]]]",
              file=sys.stderr)
        return 2
    columns = int(sys.argv[2]) if len(sys.argv) > 2 else 94
    rows = int(sys.argv[3]) if len(sys.argv) > 3 else 40

    screen = Tolerant(columns, rows)
    stream = pyte.ByteStream(screen)
    complete_recording = open(sys.argv[1], "rb").read()
    recording = complete_recording
    if len(sys.argv) > 4:
        recording = recording[: int(sys.argv[4])]
    stream.feed(recording)
    if len(sys.argv) > 6:
        # pyte stores untouched blank rows lazily. Materialise the display
        # before resizing so clipping a sparse screen cannot reveal stale rows
        # that a real terminal's blank cells had already covered.
        _ = screen.display
        screen.resize(lines=int(sys.argv[6]), columns=int(sys.argv[5]))
    if len(sys.argv) > 7 and sys.argv[7] == "continue":
        stream.feed(complete_recording[len(recording):])
    for line in screen.display:
        print(line.rstrip())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
