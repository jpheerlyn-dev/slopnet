"""crew — SlopNet's fleet: onboarding, planning, and the wave runner.

Imported by the `slopnet` CLI; not meant to be run directly. Three jobs:

  setup   ask a few plain questions, find the coding agents you already
          have, and save the crew to .slopnet/crew.json
  plan    a PLANNER agent turns your idea into WAVES.md (waves of tasks)
  run     the ORCHESTRATOR runs each wave: every task gets its own git
          worktree and its own coding agent, in parallel; the walls and
          your tests are the judge; only proven work is merged

The rules that make this safe are borrowed, with thanks, from the
operator's own StormCode: an agent never self-certifies (real tests must
exit 0), a plan is validated before anything runs, each attempt is
isolated in a worktree, and a losing attempt is thrown away rather than
merged. SlopNet adds its own gate: the walls must pass too.

Standard library only. No UI code lives here — printing is the caller's.
"""

import concurrent.futures
import datetime
import json
import os
import pathlib
import re
import shutil
import subprocess
import urllib.error
import urllib.request

CREW_FILE = ".slopnet/crew.json"
WAVES_FILE = "WAVES.md"

# Agents we know how to drive, and the flag that makes them do one
# non-interactive job. Onboarding only offers what you actually have.
KNOWN_AGENTS = {
    "claude": '{exe} --print {prompt}',
    "codex": '{exe} exec {prompt}',
    "gemini": '{exe} --prompt {prompt}',
    "hermes": '{exe} --print {prompt}',
    "cursor-agent": '{exe} --print {prompt}',
}

# API providers, if someone would rather use a key than a logged-in CLI.
KNOWN_KEYS = {
    "ANTHROPIC_API_KEY": ("anthropic", "https://api.anthropic.com/v1/messages"),
    "OPENAI_API_KEY": ("openai", "https://api.openai.com/v1/chat/completions"),
    "GEMINI_API_KEY": ("openai", "https://generativelanguage.googleapis.com"
                                 "/v1beta/openai/chat/completions"),
    "MOONSHOT_API_KEY": ("openai", "https://api.moonshot.cn/v1/chat/completions"),
    "XAI_API_KEY": ("openai", "https://api.x.ai/v1/chat/completions"),
}


class CrewError(Exception):
    pass


# A test command that always passes is worse than none: it launders bad
# work as proven. Borrowed from StormCode, which refuses these outright.
_FAKE_GATE = re.compile(r"^\s*(true|:|exit 0|echo\b[^&|;]*)\s*$|\|\|\s*(true|:|exit 0)\s*$")


def refuse_fake_gate(command):
    """Raise if a test command cannot actually fail."""
    if command and _FAKE_GATE.search(command.strip()):
        raise CrewError(
            "That test command can never fail, so it would mark bad work as "
            "proven. Remove the '|| true' (or use a real test command, or "
            "leave it blank to let the walls judge alone).")


# --------------------------------------------------------------- the crew

def load_crew(root):
    path = root / CREW_FILE
    if not path.exists():
        raise CrewError("No crew yet. Run `slopnet setup` first — it takes a minute.")
    return json.loads(path.read_text(encoding="utf-8"))


def save_crew(root, crew):
    path = root / CREW_FILE
    path.parent.mkdir(exist_ok=True)
    path.write_text(json.dumps(crew, indent=2) + "\n", encoding="utf-8")
    return path


def available_workers():
    """Everything on this machine that could do a job, CLIs first."""
    found = []
    for name, template in KNOWN_AGENTS.items():
        exe = shutil.which(name)
        if exe:
            found.append({"kind": "cli", "name": name, "command":
                          template.replace("{exe}", exe)})
    for env, (api, url) in KNOWN_KEYS.items():
        if os.environ.get(env):
            found.append({"kind": "api", "name": env.replace("_API_KEY", "").lower(),
                          "api": api, "url": url, "key_env": env, "model": ""})
    return found


def setup(root, ask, say):
    """Onboarding. `ask(question, options)` returns the chosen string."""
    say("Let's meet your crew.\n")
    workers = available_workers()
    if not workers:
        raise CrewError(
            "No coding agents found. Install one you already pay for "
            "(claude, codex, gemini, hermes) or set an API key like "
            "ANTHROPIC_API_KEY, then run `slopnet setup` again.")

    labels = [f"{w['name']} ({'logged-in CLI' if w['kind'] == 'cli' else 'API key'})"
              for w in workers]
    say("Found on this machine:")
    for label in labels:
        say(f"  - {label}")
    say("")

    planner_i = ask("Who should PLAN the work? (best thinker)", labels)
    fleet_is = ask("Who should WRITE the code? (pick one or more, comma-separated)",
                   labels, multi=True)
    while True:
        test_cmd = ask("What command runs your tests? (blank = walls only)", None)
        try:
            refuse_fake_gate(test_cmd)
            break
        except CrewError as exc:
            say(str(exc))

    crew = {
        "planner": workers[planner_i],
        "fleet": [workers[i] for i in fleet_is],
        "test_command": (test_cmd or "").strip(),
        "max_parallel": 2,
        "created": datetime.date.today().isoformat(),
    }
    path = save_crew(root, crew)
    say(f"\nCrew saved to {path.relative_to(root)}.")
    if not crew["test_command"]:
        say("No test command — the walls alone will judge the work. Add one "
            "later in that file when your project has tests; agents that "
            "can't be tested can't be trusted.")
    return crew


# ------------------------------------------------------------- talking to a worker

def _run_cli(worker, prompt, cwd, timeout):
    import shlex
    cmd = worker["command"].replace("{prompt}", shlex.quote(prompt))
    proc = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True,
                          text=True, timeout=timeout)
    return proc.stdout + proc.stderr


def _run_api(worker, prompt, timeout):
    key = os.environ.get(worker["key_env"], "")
    if not key:
        raise CrewError(f"{worker['key_env']} is not set in this shell.")
    model = worker.get("model") or ""
    if worker["api"] == "anthropic":
        body = {"model": model or "claude-sonnet-5", "max_tokens": 8192,
                "messages": [{"role": "user", "content": prompt}]}
        headers = {"x-api-key": key, "anthropic-version": "2023-06-01",
                   "content-type": "application/json"}
    else:
        body = {"model": model or "gpt-5", "messages":
                [{"role": "user", "content": prompt}]}
        headers = {"Authorization": f"Bearer {key}",
                   "content-type": "application/json"}
    req = urllib.request.Request(worker["url"], method="POST",
                                 data=json.dumps(body).encode(), headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode())
    except urllib.error.HTTPError as exc:
        raise CrewError(f"{worker['name']} refused the job: HTTP {exc.code}")
    except Exception as exc:
        raise CrewError(f"{worker['name']} unreachable: {exc}")
    if "content" in data:  # anthropic shape
        return "".join(part.get("text", "") for part in data["content"])
    return data["choices"][0]["message"]["content"]


def ask_worker(worker, prompt, cwd=None, timeout=900):
    """One job, one answer. Never trusted — always validated by the caller."""
    if worker["kind"] == "cli":
        return _run_cli(worker, prompt, cwd, timeout)
    return _run_api(worker, prompt, timeout)


# ------------------------------------------------------------------ planning

PLANNER_BRIEF = """You are the PLANNER for SlopNet, a careful multi-agent \
coding pipeline. Turn the idea below into waves of tasks and output ONE \
markdown document, nothing else.

Contract (deviation is rejected):
- Output ONLY the markdown below, no prose before or after.
- Format, exactly:

# Waves

## Wave 1
### T1-short-kebab-name
Files: path/one.py, path/two.py
What to do, in plain sentences. Name every file to create or edit and end
with how we will know it worked.

### T2-another-task
Files: path/three.py
...

## Wave 2
### T3-later-task
Files: path/four.py
...

Rules:
- Tasks in the SAME wave run AT THE SAME TIME, so they must never touch
  the same file. Put anything that depends on earlier work in a later wave.
- Every task ships its code AND its tests together, so the whole test suite
  passes after that task alone. Never split code from its tests.
- Task ids: T<number>-lowercase-hyphenated. Unique across all waves.
- Every task needs a "Files:" line listing the files it owns.
- Prefer fewer, larger, self-contained tasks. Two or three waves is plenty.
- Never rename anything that already exists. Never invent folder structures
  beyond what the task needs.
"""

TASK_RE = re.compile(r"^### (T\d+[a-z0-9-]*)\s*$", re.MULTILINE)
WAVE_RE = re.compile(r"^## Wave (\d+)\s*$", re.MULTILINE)


def parse_waves(text):
    """WAVES.md → [[task, ...], ...]. Raises on a broken plan."""
    waves, current, seen = [], None, set()
    for line in text.splitlines():
        wave_m = WAVE_RE.match(line)
        task_m = TASK_RE.match(line)
        if wave_m:
            current = []
            waves.append(current)
        elif task_m:
            if current is None:
                raise CrewError(f"task {task_m.group(1)} sits outside any wave")
            tid = task_m.group(1)
            if tid in seen:
                raise CrewError(f"two tasks share the id {tid}")
            seen.add(tid)
            current.append({"id": tid, "body": []})
        elif current and line.strip():
            current[-1]["body"].append(line)
    for wave in waves:
        for task in wave:
            task["body"] = "\n".join(task["body"]).strip()
            files = re.search(r"^Files:\s*(.+)$", task["body"], re.MULTILINE)
            task["files"] = [f.strip() for f in files.group(1).split(",")] if files else []
            if not task["files"]:
                raise CrewError(f"task {task['id']} has no 'Files:' line")
    waves = [w for w in waves if w]
    if not waves:
        raise CrewError("the plan contains no waves")
    for wave in waves:
        owned = [f for t in wave for f in t["files"]]
        clash = {f for f in owned if owned.count(f) > 1}
        if clash:
            raise CrewError("two tasks in one wave both own: " + ", ".join(sorted(clash)))
    return waves


def plan(root, idea, say):
    crew = load_crew(root)
    worker = crew["planner"]
    say(f"[planner] {worker['name']} is thinking about: {idea[:60]}...")
    prompt = f"{PLANNER_BRIEF}\n\n# The idea\n{idea}\n"
    if crew.get("test_command"):
        prompt += f"\n# The test command your tasks must keep passing\n{crew['test_command']}\n"

    errors = ""
    for attempt in (1, 2):
        reply = ask_worker(worker, prompt if attempt == 1 else
                           prompt + f"\n# Your last plan was rejected\n{errors}\n"
                                    "Emit the corrected markdown only.", cwd=str(root))
        body = reply[reply.find("# Waves"):] if "# Waves" in reply else reply
        try:
            waves = parse_waves(body)
        except CrewError as exc:
            errors = str(exc)
            say(f"[planner] plan rejected: {errors} (repair round {attempt})")
            continue
        (root / WAVES_FILE).write_text(body.strip() + "\n", encoding="utf-8")
        say(f"[planner] {WAVES_FILE}: {len(waves)} waves, "
            f"{sum(len(w) for w in waves)} tasks. Read it before you run it.")
        return waves
    raise CrewError(f"the planner could not produce a valid plan: {errors}")


# -------------------------------------------------------------- the wave runner

WORKER_BRIEF = """You are a coding agent working inside an isolated copy of \
a repository. Do the task below completely, editing files directly on disk.

House rules (breaking one fails your work):
- Only touch the files listed under Files:.
- Never rename anything. Never delete anything.
- No junk files, no .DS_Store, no secrets in code.
- Ship the code AND its tests together so the test suite passes.
- When you are done, stop. Do not explain at length.

# Your task
"""


def _git(args, cwd):
    proc = subprocess.run(["git"] + args, cwd=cwd, capture_output=True, text=True)
    return proc.returncode, (proc.stdout + proc.stderr).strip()


def _attempt(root, task, worker, crew, base_branch, say):
    """One task, in its own worktree. Returns (ok, branch, note)."""
    tid = task["id"]
    branch = f"slopnet/{tid}"
    wt = pathlib.Path(root / ".slopnet" / "worktrees" / tid)
    _git(["worktree", "remove", "--force", str(wt)], root)
    _git(["branch", "-D", branch], root)
    code, out = _git(["worktree", "add", "-b", branch, str(wt), base_branch], root)
    if code != 0:
        return False, branch, f"could not make a workspace: {out}"

    try:
        prompt = WORKER_BRIEF + f"{tid}\n{task['body']}\n"
        try:
            ask_worker(worker, prompt, cwd=str(wt))
        except CrewError as exc:
            return False, branch, str(exc)

        _git(["add", "-A"], wt)
        code, staged = _git(["diff", "--cached", "--name-only"], wt)
        if not staged.strip():
            return False, branch, "the agent changed nothing"

        # Gate 1 — the walls, judging the STAGED work. This must happen
        # BEFORE the commit: the checks read the staged diff, so checking
        # afterwards would find an empty stage and pass on anything.
        for check in sorted((root / "checks").glob("*.sh")):
            proc = subprocess.run(["sh", str(check)], cwd=wt,
                                  capture_output=True, text=True)
            if proc.returncode != 0:
                first = (proc.stdout + proc.stderr).strip().splitlines()
                return False, branch, f"wall said no: {first[0] if first else check.name}"

        code, out = _git(["-c", "user.name=slopnet", "-c", "user.email=crew@slopnet",
                          "commit", "-m", f"{tid}: {worker['name']}"], wt)
        if code != 0:
            return False, branch, f"could not record the work: {out.splitlines()[0] if out else ''}"

        # Gate 2 — the project's own tests. An agent never self-certifies.
        if crew.get("test_command"):
            proc = subprocess.run(crew["test_command"], shell=True, cwd=wt,
                                  capture_output=True, text=True, timeout=1800)
            if proc.returncode != 0:
                tail = (proc.stdout + proc.stderr).strip().splitlines()[-3:]
                return False, branch, "tests failed: " + " / ".join(tail)
        return True, branch, "proven"
    finally:
        _git(["worktree", "remove", "--force", str(wt)], root)


def run(root, say, only_wave=None):
    crew = load_crew(root)
    waves_path = root / WAVES_FILE
    if not waves_path.exists():
        raise CrewError(f"No {WAVES_FILE} yet. Run `slopnet plan \"your idea\"` first.")
    waves = parse_waves(waves_path.read_text(encoding="utf-8"))
    fleet = crew["fleet"]
    if not fleet:
        raise CrewError("Your crew has nobody to write code. Run `slopnet setup`.")
    refuse_fake_gate(crew.get("test_command", ""))

    code, dirty = _git(["status", "--porcelain"], root)
    if dirty.strip():
        raise CrewError("Commit or stash your changes first — the crew works "
                        "from a clean tree so nothing of yours can be lost.")
    _, base_branch = _git(["rev-parse", "--abbrev-ref", "HEAD"], root)

    done, failed = [], []
    for number, wave in enumerate(waves, start=1):
        if only_wave and number != only_wave:
            continue
        say(f"\n=== Wave {number}: {len(wave)} task(s) ===")
        limit = max(1, int(crew.get("max_parallel", 2)))
        with concurrent.futures.ThreadPoolExecutor(max_workers=limit) as pool:
            futures = {}
            for i, task in enumerate(wave):
                worker = fleet[i % len(fleet)]
                say(f"  {task['id']} → {worker['name']}")
                futures[pool.submit(_attempt, root, task, worker, crew,
                                    base_branch, say)] = task
            results = []
            for future in concurrent.futures.as_completed(futures):
                task = futures[future]
                try:
                    ok, branch, note = future.result()
                except Exception as exc:
                    ok, branch, note = False, None, f"crashed: {exc}"
                results.append((task, ok, branch, note))

        # Merge serially — proven work only, losing branches discarded.
        for task, ok, branch, note in sorted(results, key=lambda r: r[0]["id"]):
            if ok:
                code, out = _git(["merge", "--no-ff", branch, "-m",
                                  f"{task['id']}: proven by the crew"], root)
                if code == 0:
                    say(f"  [MERGED] {task['id']} — {note}")
                    done.append(task["id"])
                else:
                    say(f"  [CONFLICT] {task['id']} — left on branch {branch}")
                    failed.append((task["id"], "merge conflict"))
                    continue
            else:
                say(f"  [FAILED] {task['id']} — {note}")
                failed.append((task["id"], note))
            _git(["branch", "-D", branch], root)
        if failed and any(f for f in failed):
            say("  (later waves may depend on the failed work — check before continuing)")
    return done, failed
