#!/usr/bin/env python3
"""UserPromptSubmit hook — appends every human prompt, verbatim and
timestamped, to register/YYYY-MM-DD.md. Never blocks: failures exit 0."""
import datetime, json, pathlib, sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
prompt = (data.get("prompt") or "").strip()
if not prompt:
    sys.exit(0)
root = pathlib.Path(__file__).resolve().parents[2]
register = root / "register"
try:
    register.mkdir(exist_ok=True)
    now = datetime.datetime.now()
    day = register / f"{now:%Y-%m-%d}.md"
    new = not day.exists()
    quoted = "> " + prompt.replace("\n", "\n> ")
    with day.open("a", encoding="utf-8") as fh:
        if new:
            fh.write(f"# Register — {now:%Y-%m-%d}\n")
        fh.write(f"\n## {now:%H:%M} — the human said\n\n{quoted}\n")
except Exception:
    pass
sys.exit(0)
