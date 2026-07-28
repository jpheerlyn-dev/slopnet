#!/usr/bin/env python3
"""PreToolUse hook — denies edits to any path prefix listed in
PROTECTED.txt (repo root). Reading stays allowed; mutation is denied."""
import json, pathlib, re, sys

root = pathlib.Path(__file__).resolve().parents[2]
try:
    lines = (root / "PROTECTED.txt").read_text().splitlines()
except Exception:
    sys.exit(0)
prefixes = [l.strip().rstrip("/") for l in lines
            if l.strip() and not l.strip().startswith("#")]
if not prefixes:
    sys.exit(0)
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
tool = data.get("tool_name", "")
ti = data.get("tool_input") or {}
hit = None
if tool in ("Edit", "Write", "NotebookEdit"):
    path = str(ti.get("file_path", ""))
    hit = next((p for p in prefixes if p in path), None)
elif tool == "Bash":
    cmd = str(ti.get("command", ""))
    for p in prefixes:
        if p in cmd and re.search(
            r"\b(rm|mv|cp|tee|touch|chmod|chown|truncate|ln)\b|sed\s+-i"
            r"|>>?\s*\S*" + re.escape(p), cmd):
            hit = p
            break
if hit:
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            f"BLOCKED: '{hit}' is on PROTECTED.txt — sealed by the "
            "operator. Reading is allowed; changing it is not. If you "
            "believe you need this, write the request in "
            "register/PENDING_OPERATOR.md and stop.")}}))
sys.exit(0)
