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
import signal
import socket
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request

CREW_FILE = ".slopnet/crew.json"
WAVES_FILE = "WAVES.md"
DEFAULT_AGENT_TIMEOUT = 900
LONG_PROMPT_BYTES = 100 * 1024
PROBE_JOB = (
    "Create a file named probe.txt containing the word ready. "
    "Do nothing else."
)

# How to make each agent do ONE job and stop. Verified on 2026-07-28 by
# reading each tool's own --help; jobs/J01_agent_adapters.md keeps this
# table honest. The auto-approve flags matter: without them an agent
# waits forever for a human to confirm each edit. That is safe here only
# because every attempt runs inside a throwaway git worktree.
KNOWN_AGENTS = {
    "claude": {
        "invocation": "{exe} {auto_approve} -p {prompt}",
        "auto_approve": "--dangerously-skip-permissions",
        "long_invocation": "{exe} {auto_approve} -p",
        "long_transport": "stdin",
        "probe": PROBE_JOB,
    },
    "codex": {
        "invocation": "{exe} exec {auto_approve} {prompt}",
        "auto_approve": "--dangerously-bypass-approvals-and-sandbox",
        "long_invocation": "{exe} exec {auto_approve} -",
        "long_transport": "stdin",
        "probe": PROBE_JOB,
    },
    "gemini": {
        "invocation": "{exe} {auto_approve} -p {prompt}",
        "auto_approve": "--yolo",
        "long_invocation": "{exe} {auto_approve}",
        "long_transport": "stdin",
        "probe": PROBE_JOB,
    },
    "grok": {
        "invocation": "{exe} {auto_approve} -p {prompt}",
        "auto_approve": "--permission-mode bypassPermissions",
        "long_invocation": (
            "{exe} {auto_approve} --prompt-file {prompt_file} "
            "--output-format plain"
        ),
        "long_transport": "file",
        "probe": PROBE_JOB,
    },
    "kimi": {
        "invocation": "{exe} {auto_approve} -p {prompt}",
        # Kimi 0.29.2 rejects --auto/--yolo together with --prompt. Its
        # installed prompt-mode implementation creates the headless session
        # with permission "auto", so -p alone is the unattended form.
        "auto_approve": "",
        "long_invocation": "{exe} {auto_approve} -p {prompt}",
        "long_transport": "file-reference",
        "probe": PROBE_JOB,
    },
    "hermes": {
        "invocation": "{exe} {auto_approve} -z {prompt}",
        # Hermes one-shot mode auto-bypasses approvals; its --help says
        # that explicitly, so adding a second guessed flag would be wrong.
        "auto_approve": "",
        "long_invocation": "{exe} {auto_approve} -z {prompt}",
        "long_transport": "file-reference",
        "probe": PROBE_JOB,
    },
    # Preserved for operators who already use it. Setup's real edit probe,
    # not this table, decides whether this invocation can receive work.
    "cursor-agent": {
        "invocation": "{exe} {auto_approve} --print {prompt}",
        "auto_approve": "",
        "long_invocation": "{exe} {auto_approve} --print {prompt}",
        "long_transport": "file-reference",
        "probe": PROBE_JOB,
    },
}

# Tools that look like coding agents but are NOT, so setup never offers
# them a coding job. Being wrong here wastes a whole run, so each entry
# says what the tool actually is.
NOT_CODERS = {
    "zai-cli": "a client for Z.AI's search/vision/web tools — it does not "
               "edit files in your project. Your zAI coding plan reaches the "
               "fleet a different way (see jobs/J02).",
}

# Some CLIs install outside the default PATH; look there too.
EXTRA_BINS = ["~/.kimi-code/bin", "~/.grok/bin", "~/.local/bin"]

# PROVIDERS — non-CLI coding subscriptions, verified only from
# jobs/RESEARCH_subscriptions_REPORT.md (2026-07-28). A worker of kind
# env-cli runs an existing host CLI with extra env vars for that one
# invocation: never exported globally, never written to disk, never logged.
#
# "$NAME" means "read this from the operator's environment at run time",
# so tokens never live in a config file. Only report-confirmed values.
#
# Kimi is NOT listed here: it ships its own CLI (KNOWN_AGENTS) and the
# report confirms the coding plan covers that CLI. zAI ships no coding
# CLI; it is reached by pointing Claude Code at Z.AI's Anthropic-compatible
# endpoint (subscription covers that path as Coding Plan quota).
PROVIDERS = {
    "zai-glm": {
        "display_name": "zAI GLM Coding Plan",
        "kind": "env-cli",
        "host": "claude",
        "docs": "https://docs.z.ai/devpack/tool/claude",
        "env": {
            # Report §2: exact ANTHROPIC_BASE_URL for the GLM coding plan.
            "ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic",
            "ANTHROPIC_AUTH_TOKEN": "$ZAI_API_KEY",
            # Report §2: platform defaults (GLM-4.7 / GLM-4.5-Air).
            "ANTHROPIC_DEFAULT_OPUS_MODEL": "GLM-4.7",
            "ANTHROPIC_DEFAULT_SONNET_MODEL": "GLM-4.7",
            "ANTHROPIC_DEFAULT_HAIKU_MODEL": "GLM-4.5-Air",
        },
        "model": "GLM-4.7",
        "key_env": "ZAI_API_KEY",
        # Report: "GLM calls made in supported tools will strictly use your
        # Coding Plan quota. Once your plan's quota runs out, the system will
        # not deduct from your cash or account balance."
        "subscription_covers_terminal": True,
        "billing_caveat": None,
        "note": (
            "Z.AI's GLM models, driven through Claude Code. "
            "Uses your Coding Plan quota, not a separate cash/API balance."
        ),
    },
}

# Report §2 also documents an OpenAI-compatible coding endpoint for hosts
# that speak Chat Completions (not Claude Code). Kept for the providers
# section only — naked custom HTTP clients are not listed as supported
# tools, so we do not add a raw `api` worker for it.
ZAI_OPENAI_COMPAT_URL = "https://api.z.ai/api/coding/paas/v4"

# API providers, if someone would rather use a key than a logged-in CLI.
# Endpoints here are the vendor public APIs already known to the fleet;
# zAI's coding plan is NOT added as raw HTTP (see PROVIDERS / env-cli).
KNOWN_KEYS = {
    "ANTHROPIC_API_KEY": ("anthropic", "https://api.anthropic.com/v1/messages"),
    "OPENAI_API_KEY": ("openai", "https://api.openai.com/v1/chat/completions"),
    "GEMINI_API_KEY": ("openai", "https://generativelanguage.googleapis.com"
                                 "/v1beta/openai/chat/completions"),
    "MOONSHOT_API_KEY": ("openai", "https://api.moonshot.cn/v1/chat/completions"),
    "XAI_API_KEY": ("openai", "https://api.x.ai/v1/chat/completions"),
}

# Report §7 failure strings → short cause. Only patterns the report
# verified (or that already appear on this machine's live probes).
_FAILURE_CAUSES = (
    (re.compile(r"1113\s*Insufficient Balance", re.I),
     "insufficient balance (wrong endpoint or plan)"),
    (re.compile(r"No assistant message found", re.I),
     "endpoint/schema mismatch"),
    (re.compile(r"Rate limit reached", re.I), "rate limited"),
    (re.compile(r"Request rejected\s*\(429\)", re.I), "rate limited"),
    (re.compile(r"Server is temporarily limiting requests", re.I),
     "provider overloaded"),
    (re.compile(r"Authentication failed", re.I), "not logged in"),
    (re.compile(r"Authentication required|\bauth required\b", re.I),
     "not logged in"),
    (re.compile(r"401\s*\(?Unauthorized\)?", re.I), "not logged in"),
    (re.compile(r"OAuth session expired", re.I), "not logged in"),
    (re.compile(r"Failed to authenticate", re.I), "not logged in"),
    (re.compile(r"Please set an Auth method|no authentication method", re.I),
     "not logged in"),
    (re.compile(r"apiKeyHelper script is failing", re.I), "not logged in"),
)


class CrewError(Exception):
    pass


class CrewInterrupted(CrewError):
    pass


class RunInterrupted(KeyboardInterrupt):
    def __init__(self, done, failed):
        super().__init__("crew run interrupted")
        self.done = list(done)
        self.failed = list(failed)


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


def find_exe(name):
    """shutil.which, plus the folders CLI installers commonly use — a tool
    installed a minute ago may not be on PATH until the shell restarts."""
    exe = shutil.which(name)
    if exe:
        return exe
    for folder in EXTRA_BINS:
        candidate = pathlib.Path(folder).expanduser() / name
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def _render_invocation(template, exe, auto_approve):
    """Resolve executable/permission placeholders, leaving prompt transport
    placeholders for the runner."""
    import shlex
    return (template.replace("{exe}", shlex.quote(exe))
            .replace("{auto_approve}", auto_approve)).replace("  ", " ").strip()


def _cli_worker(name, exe, spec):
    return {
        "kind": "cli",
        "name": name,
        "command": _render_invocation(
            spec["invocation"], exe, spec["auto_approve"]),
        "auto_approve": spec["auto_approve"],
        "long_command": _render_invocation(
            spec["long_invocation"], exe, spec["auto_approve"]),
        "long_transport": spec["long_transport"],
        "probe": spec["probe"],
        "timeout": DEFAULT_AGENT_TIMEOUT,
    }


def _env_cli_worker(name, host_exe, host_spec, provider):
    """A host CLI plus per-invocation env overrides (kind env-cli)."""
    worker = _cli_worker(name, host_exe, host_spec)
    worker["kind"] = "env-cli"
    worker["env"] = dict(provider["env"])  # keeps $VAR form — never secrets
    worker["hosted_by"] = provider["host"]
    worker["model"] = provider.get("model") or ""
    worker["display_name"] = provider.get("display_name") or name
    worker["note"] = provider.get("note") or ""
    if provider.get("billing_caveat"):
        worker["billing_caveat"] = provider["billing_caveat"]
    return worker


def providers_catalog():
    """Serialisable providers section for crew.json — no secrets, only
    the $VAR indirection form and report-verified fields."""
    catalog = {}
    for name, spec in PROVIDERS.items():
        entry = {
            "display_name": spec["display_name"],
            "reach": spec["kind"],
            "host": spec.get("host"),
            "env": dict(spec["env"]),
            "model": spec.get("model") or "",
            "key_env": spec.get("key_env"),
            "subscription_covers_terminal": bool(
                spec.get("subscription_covers_terminal")),
            "docs": spec.get("docs") or "",
            "note": spec.get("note") or "",
        }
        if name == "zai-glm":
            entry["openai_compat_url"] = ZAI_OPENAI_COMPAT_URL
        if spec.get("billing_caveat"):
            entry["billing_caveat"] = spec["billing_caveat"]
        catalog[name] = entry
    return catalog


def _worker_label(worker):
    kind = worker.get("kind")
    if kind == "cli":
        return f"{worker['name']} (logged-in CLI)"
    if kind == "env-cli":
        host = worker.get("hosted_by") or "host CLI"
        return f"{worker['name']} (via {host}, env overrides)"
    if kind == "api":
        return f"{worker['name']} (API key)"
    return worker["name"]


def available_workers():
    """Everything on this machine that could do a job, CLIs first."""
    found = []
    for name, spec in KNOWN_AGENTS.items():
        exe = find_exe(name)
        if exe:
            found.append(_cli_worker(name, exe, spec))
    for env, (api, url) in KNOWN_KEYS.items():
        if os.environ.get(env):
            found.append({"kind": "api", "name": env.replace("_API_KEY", "").lower(),
                          "api": api, "url": url, "key_env": env, "model": "",
                          "probe": PROBE_JOB, "timeout": DEFAULT_AGENT_TIMEOUT})
    # env-cli providers (e.g. zAI via Claude): host CLI must exist, key
    # must be present, and the report must have confirmed terminal cover.
    for name, spec in PROVIDERS.items():
        if not spec.get("subscription_covers_terminal"):
            continue
        host = spec.get("host")
        host_exe = find_exe(host) if host else None
        key_var = spec.get("key_env") or ""
        if not host_exe or not key_var or not os.environ.get(key_var):
            continue
        if not (spec.get("env") or {}).get("ANTHROPIC_BASE_URL"):
            continue  # never invent an endpoint
        if host not in KNOWN_AGENTS:
            continue
        found.append(_env_cli_worker(name, host_exe, KNOWN_AGENTS[host], spec))
    return found


def missing_provider_hints():
    """Providers the report supports but this shell cannot run yet."""
    hints = []
    for name, spec in PROVIDERS.items():
        if not spec.get("subscription_covers_terminal"):
            continue
        host = spec.get("host")
        key_var = spec.get("key_env") or ""
        host_ok = bool(host and find_exe(host))
        key_ok = bool(key_var and os.environ.get(key_var))
        if host_ok and key_ok:
            continue
        if not host_ok and not key_ok:
            hints.append(
                f"{name} — install {host} and set {key_var} "
                f"({spec.get('note') or spec.get('display_name')})")
        elif not host_ok:
            hints.append(
                f"{name} — needs host CLI `{host}` installed "
                f"({spec.get('note') or ''})".rstrip())
        else:
            hints.append(
                f"{name} — set {key_var} in your shell "
                f"({spec.get('note') or ''})".rstrip())
    return hints


def _proof_fields(proven, reason):
    return {
        "proven": proven,
        "proven_on": datetime.date.today().isoformat(),
        "proof": reason,
    }


def _probe_worker(worker):
    """Ask a worker to make one exact edit in a disposable git repo."""
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix=f"slopnet-probe-{worker['name']}-") as raw:
        root = pathlib.Path(raw)
        proc = subprocess.run(
            ["git", "init", "-q"], cwd=root, capture_output=True, text=True)
        if proc.returncode != 0:
            return False, "could not create the throwaway probe repo", 0
        try:
            ask_worker(
                worker,
                worker.get("probe") or PROBE_JOB,
                cwd=str(root),
                timeout=_worker_timeout(worker),
            )
        except CrewError as exc:
            elapsed = max(0, int(time.monotonic() - started))
            return False, str(exc), elapsed
        elapsed = max(0, int(time.monotonic() - started))
        probe = root / "probe.txt"
        if not probe.exists():
            return False, "ran but changed nothing (probe.txt was not created)", elapsed
        try:
            content = probe.read_text(encoding="utf-8").strip()
        except (OSError, UnicodeError):
            return False, "created probe.txt but it could not be read", elapsed
        if content != "ready":
            return False, "created probe.txt with the wrong contents", elapsed
        return True, f"wrote the file in {elapsed}s", elapsed


def setup(root, ask, say, automatic=False):
    """Onboarding. `ask(question, options)` returns the chosen string."""
    say("Let's meet your crew.\n")
    workers = available_workers()
    if not workers:
        raise CrewError(
            "No coding agents found. Install one you already pay for "
            "(claude, codex, gemini, hermes) or set an API key like "
            "ANTHROPIC_API_KEY, then run `slopnet setup` again.")

    labels = [_worker_label(w) for w in workers]
    say("Found on this machine:")
    for worker, label in zip(workers, labels):
        say(f"  - {label}")
        # Billing surprise guard: one plain sentence before they pick.
        caveat = worker.get("billing_caveat")
        if caveat:
            say(f"      Billing: {caveat}")
        elif worker.get("kind") == "env-cli" and worker.get("note"):
            say(f"      {worker['note']}")
    for hint in missing_provider_hints():
        say(f"  - {hint}")
    for name, why in NOT_CODERS.items():
        if find_exe(name):
            say(f"  - {name} — NOT offered: {why}")
    say("")

    preproven = set()
    if automatic:
        say("No questions requested — proving agents in order and using the "
            "first one that can edit safely.")
        planner_i = None
        for i, worker in enumerate(workers):
            proven, reason, _ = _probe_worker(worker)
            worker.update(_proof_fields(proven, reason))
            preproven.add(i)
            mark = "[OK]" if proven else "[!!]"
            say(f"{mark} {worker['name']} — {reason}")
            if proven:
                planner_i = i
                break
        if planner_i is None:
            raise CrewError(
                "None of the available agents passed the edit proof. Log one "
                "in, then run `slopnet setup` again.")
        fleet_is = [planner_i]
        test_cmd = ""
    else:
        planner_i = ask("Who should PLAN the work? (best thinker)", labels)
        fleet_is = ask(
            "Who should WRITE the code? (pick one or more, comma-separated)",
            labels, multi=True)
        while True:
            test_cmd = ask(
                "What command runs your tests? [walls only]", None)
            try:
                refuse_fake_gate(test_cmd)
                break
            except CrewError as exc:
                say(str(exc))

    selected = [workers[planner_i]] + [workers[i] for i in fleet_is]
    unique = []
    seen = set()
    for worker in selected:
        identity = (worker["kind"], worker["name"])
        if identity not in seen:
            unique.append(worker)
            seen.add(identity)

    if not automatic:
        say("\nProving the selected agents in throwaway git repos:")
    for worker in unique:
        worker_i = workers.index(worker)
        if worker_i in preproven:
            continue
        proven, reason, _ = _probe_worker(worker)
        worker.update(_proof_fields(proven, reason))
        mark = "[OK]" if proven else "[!!]"
        say(f"{mark} {worker['name']} — {reason}")

    crew = {
        "planner": workers[planner_i],
        "fleet": [workers[i] for i in fleet_is],
        "test_command": (test_cmd or "").strip(),
        "max_parallel": 2,
        "created": datetime.date.today().isoformat(),
        # Report-verified non-CLI subscriptions (env forms only — no tokens).
        "providers": providers_catalog(),
    }
    path = save_crew(root, crew)
    say(f"\nCrew saved to {path.relative_to(root)}.")
    if not crew["test_command"]:
        say("No test command — the walls alone will judge the work. Add one "
            "later in that file when your project has tests; agents that "
            "can't be tested can't be trusted.")
    return crew


# ------------------------------------------------------------- talking to a worker

def _worker_timeout(worker, override=None):
    raw = worker.get("timeout", DEFAULT_AGENT_TIMEOUT) if override is None else override
    try:
        timeout = float(raw)
    except (TypeError, ValueError):
        raise CrewError(f"{worker['name']} has an invalid timeout in {CREW_FILE}.")
    if timeout <= 0:
        raise CrewError(f"{worker['name']} has an invalid timeout in {CREW_FILE}.")
    return int(timeout) if timeout.is_integer() else timeout


def _short_failure(output, limit=240):
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    if not lines:
        return ""
    return lines[-1][:limit]


def classify_failure(output, returncode=None, http_code=None):
    """Map verified failure strings (report §7) to a short cause.

    Returns a plain phrase like 'not logged in' or 'rate limited'. Falls
    back to a short last-line snippet when nothing matches — never invents
    a diagnosis the report did not support.
    """
    text = output or ""
    for pattern, cause in _FAILURE_CAUSES:
        if pattern.search(text):
            return cause
    if http_code == 401:
        return "not logged in"
    if http_code == 429:
        return "rate limited"
    if http_code is not None:
        return f"HTTP {http_code}"
    detail = _short_failure(text)
    if detail:
        return detail
    if returncode is not None:
        return f"exited {returncode}"
    return "failed"


def _resolve_worker_env(worker):
    """Build a subprocess env for env-cli. Secrets stay in memory only."""
    if not worker.get("env"):
        return None
    env = os.environ.copy()
    for name, value in worker["env"].items():
        if value.startswith("$"):
            resolved = os.environ.get(value[1:], "")
            if not resolved:
                raise CrewError(
                    f"{worker['name']} needs {value[1:]} set in your shell. "
                    f"Add it, then run this again.")
            env[name] = resolved
        else:
            env[name] = value
    return env


def _stop_process(proc):
    if proc.poll() is not None:
        return
    try:
        if os.name == "posix":
            os.killpg(proc.pid, signal.SIGKILL)
        else:
            proc.kill()
    except ProcessLookupError:
        return


def _run_cli(worker, prompt, cwd, timeout, cancel_event=None):
    import shlex
    timeout = _worker_timeout(worker, timeout)
    prompt_path = None
    stdin = None
    if len(prompt.encode("utf-8")) > LONG_PROMPT_BYTES:
        if not cwd:
            raise CrewError("a working directory is required for a long agent prompt")
        with tempfile.NamedTemporaryFile(
                mode="w", encoding="utf-8", prefix=".slopnet-prompt-",
                suffix=".txt", delete=False) as handle:
            handle.write(prompt)
            prompt_path = pathlib.Path(handle.name)
        transport = worker.get("long_transport")
        cmd = worker.get("long_command", "")
        if transport == "stdin":
            stdin = prompt_path.read_text(encoding="utf-8")
        elif transport == "file":
            cmd = cmd.replace("{prompt_file}", shlex.quote(str(prompt_path)))
        elif transport == "file-reference":
            reference = (
                f"Read the complete task brief at {prompt_path}, then follow every "
                "instruction in it. Do not skip or truncate the file."
            )
            cmd = cmd.replace("{prompt}", shlex.quote(reference))
        else:
            prompt_path.unlink(missing_ok=True)
            raise CrewError(
                f"{worker['name']} has no safe long-prompt transport in {CREW_FILE}.")
    else:
        cmd = worker["command"].replace("{prompt}", shlex.quote(prompt))
    try:
        # env-cli / hosted brain: env vars for this one invocation only.
        # Never exported to the shell, never written to disk, never printed.
        env = _resolve_worker_env(worker)
        popen_options = {"start_new_session": True} if os.name == "posix" else {}
        proc = subprocess.Popen(
            cmd, shell=True, cwd=cwd, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, stdin=subprocess.PIPE, text=True, env=env,
            **popen_options)
        deadline = time.monotonic() + timeout
        pending_input = stdin
        try:
            while True:
                if cancel_event is not None and cancel_event.is_set():
                    _stop_process(proc)
                    proc.communicate()
                    raise CrewInterrupted("run interrupted")
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    _stop_process(proc)
                    proc.communicate()
                    raise CrewError(f"agent timed out after {timeout}s")
                try:
                    stdout, stderr = proc.communicate(
                        input=pending_input, timeout=min(0.25, remaining))
                    break
                except subprocess.TimeoutExpired:
                    pending_input = None
        except KeyboardInterrupt:
            _stop_process(proc)
            proc.communicate()
            raise
        output = stdout + stderr
        if proc.returncode != 0:
            raise CrewError(classify_failure(output, returncode=proc.returncode))
        # Agent CLIs commonly write progress (including an echoed copy of
        # the final answer) to stderr and the machine-readable answer to
        # stdout. Feeding both to the plan parser duplicates valid tasks.
        return stdout if stdout.strip() else stderr
    finally:
        if prompt_path is not None:
            prompt_path.unlink(missing_ok=True)


def _run_api(worker, prompt, timeout, cancel_event=None):
    if cancel_event is not None and cancel_event.is_set():
        raise CrewInterrupted("run interrupted")
    timeout = _worker_timeout(worker, timeout)
    key = os.environ.get(worker["key_env"], "")
    if not key:
        raise CrewError("not logged in")
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
    except (TimeoutError, socket.timeout):
        raise CrewError(f"agent timed out after {timeout}s")
    except urllib.error.HTTPError as exc:
        body = ""
        try:
            body = exc.read().decode(errors="replace")
        except Exception:
            body = ""
        raise CrewError(classify_failure(body, http_code=exc.code))
    except urllib.error.URLError as exc:
        if isinstance(exc.reason, (TimeoutError, socket.timeout)):
            raise CrewError(f"agent timed out after {timeout}s")
        raise CrewError(f"{worker['name']} unreachable: {exc.reason}")
    except Exception as exc:
        raise CrewError(f"{worker['name']} unreachable: {exc}")
    if "content" in data:  # anthropic shape
        return "".join(part.get("text", "") for part in data["content"])
    return data["choices"][0]["message"]["content"]


def ask_worker(worker, prompt, cwd=None, timeout=None, cancel_event=None):
    """One job, one answer. Never trusted — always validated by the caller."""
    timeout = _worker_timeout(worker, timeout)
    if worker["kind"] in ("cli", "env-cli"):
        return _run_cli(worker, prompt, cwd, timeout, cancel_event)
    return _run_api(worker, prompt, timeout, cancel_event)


def require_proven(worker):
    if worker.get("proven") is True:
        return
    reason = worker.get("proof") or "no successful setup probe"
    raise CrewError(
        f"{worker['name']} is unproven: {reason}. "
        "Run `slopnet setup` before giving it real work.")


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
    require_proven(worker)
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


def _attempt(root, task, worker, crew, base_branch, say, cancel_event=None,
             set_state=None):
    """One task, in its own worktree. Returns (ok, branch, note).

    `set_state`, when given, is told the task's plain-word state as it moves
    through the gates (working…, checking…, testing…). It is the only hook
    the live view has into the runner; all rendering stays with the caller,
    so the engine never moves a cursor.
    """
    tid = task["id"]
    branch = f"slopnet/{tid}"
    wt = pathlib.Path(root / ".slopnet" / "worktrees" / tid)
    _git(["worktree", "remove", "--force", str(wt)], root)
    _git(["branch", "-D", branch], root)
    code, out = _git(["worktree", "add", "-b", branch, str(wt), base_branch], root)
    if code != 0:
        return False, branch, f"could not make a workspace: {out}"

    try:
        if set_state:
            set_state("working…")
        prompt = WORKER_BRIEF + f"{tid}\n{task['body']}\n"
        try:
            ask_worker(worker, prompt, cwd=str(wt),
                       cancel_event=cancel_event)
        except CrewError as exc:
            return False, branch, str(exc)

        _git(["add", "-A"], wt)
        code, staged = _git(["diff", "--cached", "--name-only"], wt)
        if not staged.strip():
            return False, branch, "the agent changed nothing"

        # Gate 1 — the walls, judging the STAGED work. This must happen
        # BEFORE the commit: the checks read the staged diff, so checking
        # afterwards would find an empty stage and pass on anything.
        if set_state:
            set_state("checking…")
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
            if set_state:
                set_state("testing…")
            popen_options = (
                {"start_new_session": True} if os.name == "posix" else {})
            proc = subprocess.Popen(
                crew["test_command"], shell=True, cwd=wt,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                **popen_options)
            deadline = time.monotonic() + 1800
            while True:
                if cancel_event is not None and cancel_event.is_set():
                    _stop_process(proc)
                    proc.communicate()
                    raise CrewInterrupted("run interrupted")
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    _stop_process(proc)
                    proc.communicate()
                    return False, branch, "tests timed out after 1800s"
                try:
                    stdout, stderr = proc.communicate(
                        timeout=min(0.25, remaining))
                    break
                except subprocess.TimeoutExpired:
                    continue
            if proc.returncode != 0:
                tail = (stdout + stderr).strip().splitlines()[-3:]
                return False, branch, "tests failed: " + " / ".join(tail)
        return True, branch, "proven"
    finally:
        _git(["worktree", "remove", "--force", str(wt)], root)


def _cleanup_run(root, task_ids):
    """Remove only the runner's known disposable worktrees and branches."""
    for tid in task_ids:
        wt = pathlib.Path(root / ".slopnet" / "worktrees" / tid)
        _git(["worktree", "remove", "--force", str(wt)], root)
    _git(["worktree", "prune"], root)
    for tid in task_ids:
        _git(["branch", "-D", f"slopnet/{tid}"], root)


# ------------------------------------------------------------- live status
#
# The runner keeps the work; this object keeps the clock. It holds each
# task's plain-word state and pushes a plain snapshot through `emit` about
# once a second — so the clock keeps moving even while an agent is silent.
# It moves no cursor and writes no text: every byte of the display is the
# caller's job (the engine stays UI-free, inherited from StormCode).

class LiveStatus:
    """Per-task state + a ticking emit. UI-free: state only, never rendered."""

    def __init__(self, emit, interval=1.0):
        self._emit = emit
        self._interval = interval
        self._lock = threading.Lock()
        self._wave = 0
        self._wave_total = 0
        self._wave_started = time.monotonic()
        self._note = ""
        self._tasks = []
        self._index = {}
        self._stop = threading.Event()
        self._thread = None

    @staticmethod
    def _blank(tid, agent):
        now = time.monotonic()
        return {"id": tid, "agent": agent, "state": "waiting", "reason": "",
                "started": None, "last_event": now}

    def assign(self, tid, agent):
        with self._lock:
            if tid not in self._index:
                self._index[tid] = len(self._tasks)
                self._tasks.append(self._blank(tid, agent))
            else:
                self._tasks[self._index[tid]]["agent"] = agent

    def start_wave(self, number, total):
        with self._lock:
            self._wave = number
            self._wave_total = total
            self._wave_started = time.monotonic()
            self._tasks = []
            self._index = {}
            self._note = ""

    def set_state(self, tid, state, reason=""):
        now = time.monotonic()
        with self._lock:
            if tid not in self._index:
                self._index[tid] = len(self._tasks)
                self._tasks.append(self._blank(tid, ""))
            task = self._tasks[self._index[tid]]
            task["state"] = state
            task["reason"] = reason or ""
            task["last_event"] = now
            if task["started"] is None and state == "working…":
                task["started"] = now

    def set_note(self, note):
        with self._lock:
            self._note = note or ""

    def snapshot(self):
        with self._lock:
            return {
                "wave": self._wave,
                "wave_total": self._wave_total,
                "wave_started": self._wave_started,
                "note": self._note,
                "tasks": [dict(task) for task in self._tasks],
            }

    def start(self):
        def loop():
            while True:
                try:
                    self._emit(self.snapshot())
                except Exception:
                    pass
                if self._stop.wait(self._interval):
                    try:
                        self._emit(self.snapshot())
                    except Exception:
                        pass
                    return
        self._thread = threading.Thread(
            target=loop, name="slopnet-live-tick", daemon=True)
        self._thread.start()

    def stop(self):
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=2)
        self._thread = None


def _make_set_state(live, tid):
    """Bind a task id to LiveStatus.set_state, or return None when no live
    view is attached (so _attempt's calls simply vanish)."""
    if live is None:
        return None

    def set_state(state, reason=""):
        live.set_state(tid, state, reason)
    return set_state


def run(root, say, only_wave=None, emit=None):
    crew = load_crew(root)
    fleet = crew["fleet"]
    if not fleet:
        raise CrewError("Your crew has nobody to write code. Run `slopnet setup`.")
    for worker in fleet:
        require_proven(worker)
    waves_path = root / WAVES_FILE
    if not waves_path.exists():
        raise CrewError(f"No {WAVES_FILE} yet. Run `slopnet plan \"your idea\"` first.")
    waves = parse_waves(waves_path.read_text(encoding="utf-8"))
    refuse_fake_gate(crew.get("test_command", ""))

    code, dirty = _git(["status", "--porcelain"], root)
    if dirty.strip():
        raise CrewError("Commit or stash your changes first — the crew works "
                        "from a clean tree so nothing of yours can be lost.")
    _, base_branch = _git(["rev-parse", "--abbrev-ref", "HEAD"], root)

    # A live view is entirely optional. When `emit` is given, the runner
    # reports state through it (and stays silent about the lines the live
    # block already shows); without it, behaviour is exactly as before.
    live = LiveStatus(emit) if emit else None
    if live is not None:
        live.start()

    def announce(message):
        # The lines the live block already renders are not printed twice.
        if live is not None:
            return
        say(message)

    done, failed = [], []
    cancel_event = threading.Event()
    task_ids = [task["id"] for wave in waves for task in wave]
    try:
        for number, wave in enumerate(waves, start=1):
            if only_wave and number != only_wave:
                continue
            if live is not None:
                live.start_wave(number, len(waves))
            announce(f"\n=== Wave {number}: {len(wave)} task(s) ===")
            limit = max(1, int(crew.get("max_parallel", 2)))
            pool = concurrent.futures.ThreadPoolExecutor(max_workers=limit)
            futures = {}
            try:
                for i, task in enumerate(wave):
                    worker = fleet[i % len(fleet)]
                    if live is not None:
                        live.assign(task["id"], worker["name"])
                    announce(f"  {task['id']} → {worker['name']}")
                    set_state = _make_set_state(live, task["id"])
                    future = pool.submit(
                        _attempt, root, task, worker, crew, base_branch, say,
                        cancel_event, set_state)
                    futures[future] = task
                results = []
                for future in concurrent.futures.as_completed(futures):
                    task = futures[future]
                    try:
                        ok, branch, note = future.result()
                    except Exception as exc:
                        ok, branch, note = False, None, f"crashed: {exc}"
                    # Show a failure the moment it happens, not only at merge.
                    if live is not None and not ok:
                        live.set_state(task["id"], "FAILED", note)
                    results.append((task, ok, branch, note))
            except KeyboardInterrupt:
                cancel_event.set()
                for future in futures:
                    future.cancel()
                pool.shutdown(wait=True, cancel_futures=True)
                raise
            else:
                pool.shutdown(wait=True)

            # Merge serially — proven work only, losing branches discarded.
            for task, ok, branch, note in sorted(
                    results, key=lambda result: result[0]["id"]):
                if ok:
                    code, out = _git(["merge", "--no-ff", branch, "-m",
                                      f"{task['id']}: proven by the crew"], root)
                    if code == 0:
                        if live is not None:
                            live.set_state(task["id"], "MERGED")
                        announce(f"  [MERGED] {task['id']} — {note}")
                        done.append(task["id"])
                    else:
                        _git(["merge", "--abort"], root)
                        if live is not None:
                            live.set_state(task["id"], "FAILED", "merge conflict")
                        announce(f"  [CONFLICT] {task['id']} — left on branch {branch}")
                        failed.append((task["id"], "merge conflict"))
                        continue
                else:
                    announce(f"  [FAILED] {task['id']} — {note}")
                    failed.append((task["id"], note))
                _git(["branch", "-D", branch], root)
            if failed:
                note_text = ("later waves may depend on the failed work — "
                             "check before continuing")
                if live is not None:
                    live.set_note(note_text)
                announce("  (" + note_text + ")")
    except KeyboardInterrupt:
        cancel_event.set()
        _git(["merge", "--abort"], root)
        _cleanup_run(root, task_ids)
        raise RunInterrupted(done, failed)
    finally:
        if live is not None:
            live.stop()
    return done, failed
