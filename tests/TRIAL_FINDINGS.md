# Trial findings — 2026-07-29 19:42

Written by tests/trial.sh. Nothing here is a claim; every line is
something the script actually observed.

## Step 1 — agent liveness

- **AWAKE** `codex`
- **AWAKE** `claude`
- **AWAKE** `grok`
- **AWAKE** `kimi`
- asleep `gemini` — Approval mode overridden to "default" because the current folder is not trusted. Please set an Auth method in your /Users/**REDACTED**/.gemini/settings.json or specify

4 awake: codex claude grok kimi

## Step 2 — real project, armed the real way

- folder: `/var/folders/tt/1rmv5zdj0pvb3nc47g3z7kyr0000gn/T/tmp.tPANIunz7p/hello-trial` (temporary)
- agent: `codex`

## Step 3 — the build

Request: _a python function that returns the string hello world, with a pytest test for it_

```
[planner] codex is thinking about: a python function that returns the string hello world, with ...
[planner] WAVES.md: 1 waves, 1 tasks. Read it before you run it.
Read WAVES.md. If it looks right: slopnet run
```

The plan it wrote:
```
# Waves

## Wave 1
### T1-create-hello-world-function
Files: hello.py, test_hello.py
Create `hello.py` with a Python function that returns the exact string `"hello world"`. Create `test_hello.py` with a pytest test for that function. We will know it worked when `python3 -m pytest -q` passes.
```

The run:
```
--- Wave 1 of 1 ---
  T1-create-hello-world-function  codex  working…
  T1-create-hello-world-function  codex  testing…
  T1-create-hello-world-function  codex  MERGED

Merged: 1   Failed: 0
```

## Step 4 — does it actually work?

- files built: `crew.py hello.py test_hello.py `
- test output:
```
.                                                                        [100%]
1 passed in 0.01s
```

**Verdict: WORKED — real files, real passing tests**

- total time: 75s
- human input needed after starting: none
- project folder: `/var/folders/tt/1rmv5zdj0pvb3nc47g3z7kyr0000gn/T/tmp.tPANIunz7p/hello-trial` (removed)
