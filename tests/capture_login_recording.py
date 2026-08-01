#!/usr/bin/env python3
"""Run `agy login` in a pty of a chosen width and keep every byte it writes.

The point is to find out whether the sign-in link Antigravity prints depends
on how wide it thinks the terminal is. SlopNet reads the link off that output,
so if the link itself changes with the width, that is worth knowing before
anything else is changed.
"""
import os
import pty
import re
import select
import struct
import sys
import termios
import fcntl
import time

cols = int(sys.argv[1])
seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 20.0

pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"
    os.environ["COLUMNS"] = str(cols)
    os.execvp("agy", ["agy", "login"])

fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, cols, 0, 0))

chunks = []
started = time.time()
sent = False
while time.time() - started < seconds:
    ready, _, _ = select.select([fd], [], [], 0.4)
    if ready:
        try:
            data = os.read(fd, 8192)
        except OSError:
            break
        if not data:
            break
        chunks.append(data)
    if not sent and time.time() - started > 3.0:
        os.write(fd, b"\r")          # take the highlighted option
        sent = True

os.kill(pid, 9)
raw = b"".join(chunks)
text = raw.decode("utf-8", "replace")
plain = re.sub(r"\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b\[[0-9;?<>=]*[@-~]|\x1b[78MDEHc=>]", "", text)

open("/tmp/agy_raw.bin", "wb").write(raw)
print("WIDTH", cols, "BYTES", len(raw))
rows = plain.replace("\r", "\n").split("\n")
for i, line in enumerate(rows):
    if line.strip():
        print("ROW %02d len=%3d |%s|" % (i, len(line), line))
