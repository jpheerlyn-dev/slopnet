# T06 — `adapters/claude-code/` (proven source embedded below)

**Where:** the `slopnet` repo. **Model:** small–medium. **Depends on:** T01.

## Context

Adapters enforce SlopNet rules *earlier* than the commit for tools that
support it. This one is for Claude Code and is **already proven in
production** (the **REDACTED** project) — your job is faithful assembly, not
design. It provides: (a) automatic verbatim logging of every human prompt
into the register, (b) hard denial of edits to operator-protected paths.

## Deliverables

Create `adapters/claude-code/` containing exactly four files:

1. **`README.md`** (≤8 lines): "Copy this folder's contents into your
   project as `.claude/` (`cp -r adapters/claude-code/. .claude/`).
   Prompts then auto-log to `register/`; paths in `PROTECTED.txt` become
   un-editable for the agent. Keep `.claude/settings.local.json` out of
   git for personal overrides."
2. **`settings.json`**:
```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"${CLAUDE_PROJECT_DIR:-.}/.claude/hooks/log_prompt.py\"",
            "timeout": 10,
            "statusMessage": "Signing the register"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Edit|Write|NotebookEdit|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"${CLAUDE_PROJECT_DIR:-.}/.claude/hooks/guard_protected.py\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```
3. **`hooks/log_prompt.py`**:
```python
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
```
4. **`hooks/guard_protected.py`**:
```python
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
```

## Rules

- Assemble exactly as embedded; adjust nothing but obvious syntax errors
  (report any in `LOG.md`). Pipe-test both hooks before finishing:
  feed each a hand-made JSON payload on stdin and show the result in `LOG.md`.
- No new names. Log in `LOG.md`.

## Acceptance (operator runs these)

```bash
echo '{"prompt":"adapter test"}' | python3 adapters/claude-code/hooks/log_prompt.py && tail -3 "register/$(date +%F).md"
```
```bash
printf 'sealed-example/\n' > PROTECTED.txt && echo '{"tool_name":"Edit","tool_input":{"file_path":"sealed-example/x.py"}}' | python3 adapters/claude-code/hooks/guard_protected.py; git checkout -- PROTECTED.txt
```
(second command must print the deny JSON)
