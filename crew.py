"""crew — SlopNet's fleet: onboarding, planning, and the wave runner.

Imported by the `slopnet` CLI; not meant to be run directly. Three jobs:

  setup   ask a few plain questions, find the coding agents you already
          have, and save the crew to .slopnet/crew.json
  plan    a PLANNER agent turns your idea into WAVES.md (waves of tasks)
  run     the ORCHESTRATOR runs each wave: every task gets its own git
          worktree and its own coding agent, in parallel; the checks and
          your tests are the judge; only proven work is merged

The rules that make this safe are borrowed, with thanks, from the
operator's own StormCode: an agent never self-certifies (real tests must
exit 0), a plan is validated before anything runs, each attempt is
isolated in a worktree, and a losing attempt is thrown away rather than
merged. SlopNet adds its own gate: the checks must pass too.

Standard library only. No UI code lives here — printing is the caller's.
"""

import concurrent.futures
import datetime
import json
import os
import pathlib
import re
import shlex
import shutil
import signal
import socket
import subprocess
import sys
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
# reading each tool's own --help; archive/jobs/J01_agent_adapters.md keeps this
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
        "auto_approve": "--sandbox workspace-write",
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
               "fleet a different way (see archive/jobs/J02_subscription_router.md).",
}

# Some CLIs install outside the default PATH; look there too.
EXTRA_BINS = [
    "~/.kimi-code/bin",
    "~/.grok/bin",
    "~/.local/bin",
    "~/.local/node_modules/.bin",
]

# PROVIDERS — non-CLI coding subscriptions, verified only from
# archive/jobs/RESEARCH_subscriptions_REPORT.md (2026-07-28). A worker of kind
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
    """Prefer crew_fail(rule, why, fix). Single-string args still get a FIX line via die()."""
    pass


def crew_fail(rule, why, fix):
    raise CrewError(f"RULE: {rule}\nWHY:  {why}\nFIX:  {fix}")


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
        crew_fail(
            "That test command can never fail.",
            "A test that always passes would mark bad work as proven.",
            "Remove '|| true' (or use a real test command, or leave blank for checks only), then re-run setup",
        )


# --------------------------------------------------------------- the crew

def load_crew(root):
    path = root / CREW_FILE
    if not path.exists():
        crew_fail(
            "No crew yet.",
            "The planner and writers are chosen during setup.",
            "Run: slopnet setup",
        )
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
        return f"{worker['name']} (CLI detected — proof required)"
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


def setup(root, ask, say, automatic=False, resource_limits=None,
          required_agent=None):
    """Onboarding. `ask(question, options)` returns the chosen string."""
    say("Let's meet your crew.\n")
    workers = available_workers()
    if required_agent:
        workers = [worker for worker in workers if worker.get("name") == required_agent]
    if not workers:
        wanted = f" named {required_agent}" if required_agent else ""
        crew_fail(
            f"No proved coding agent{wanted} was found.",
            "SlopNet needs a verified unattended adapter for the coding app you chose.",
            "Install one (claude, codex, gemini, hermes, …), log in, then: slopnet setup",
        )

    if resource_limits:
        for worker in workers:
            if worker.get("kind") in ("cli", "env-cli"):
                worker["resource_limits"] = dict(resource_limits)

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
            crew_fail(
                "None of the available agents passed the edit proof.",
                "Unproven agents are not allowed to write real work.",
                "Log an AI coding app in, then run: slopnet setup",
            )
        fleet_is = [planner_i]
        test_cmd = ""
    else:
        planner_i = ask("Who should PLAN the work? (best thinker)", labels)
        fleet_is = ask(
            "Who should WRITE the code? (pick one or more, comma-separated)",
            labels, multi=True)
        while True:
            test_cmd = ask(
                "What command runs your tests? [checks only]", None)
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
        say("No test command — the checks alone will judge the work. Add one "
            "later in that file when your project has tests; agents that "
            "can't be tested can't be trusted.")
    return crew


# ------------------------------------------------------------- talking to a worker

def _worker_timeout(worker, override=None):
    raw = worker.get("timeout", DEFAULT_AGENT_TIMEOUT) if override is None else override
    try:
        timeout = float(raw)
    except (TypeError, ValueError):
        crew_fail(
            f"{worker['name']} has an invalid timeout in {CREW_FILE}.",
            "Timeouts must be positive numbers (seconds).",
            f"Edit {CREW_FILE} and set a positive timeout, then re-run",
        )
    if timeout <= 0:
        crew_fail(
            f"{worker['name']} has an invalid timeout in {CREW_FILE}.",
            "Timeouts must be positive numbers (seconds).",
            f"Edit {CREW_FILE} and set a positive timeout, then re-run",
        )
    return int(timeout) if timeout.is_integer() else timeout


# Secret shapes to scrub from anything an agent printed before it is shown.
# Same families checks/secrets.sh blocks at commit time, plus the two an auth
# failure is most likely to echo: a bearer token and credentials inside a URL.
_SECRET_SHAPES = [
    (re.compile(r"AKIA[0-9A-Z]{16}"), "[redacted]"),
    (re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}"), "[redacted]"),
    (re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}"), "[redacted]"),
    (re.compile(r"\bsk-[A-Za-z0-9_-]{16,}"), "[redacted]"),
    (re.compile(r"\bxox[abposr]-[A-Za-z0-9-]{10,}"), "[redacted]"),
    (re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{5,}"),
     "[redacted]"),
    (re.compile(r"(?i)\b(bearer)\s+[A-Za-z0-9._~+/=-]{12,}"), r"\1 [redacted]"),
    # credentials inside a URL: scheme://user:secret@host — keep the shape so
    # the host still reads as a host.
    (re.compile(r"(?i)\b([a-z][a-z0-9+.-]*://)[^/\s:@]+:[^/\s@]+@"), r"\1[redacted]@"),
    # key=value and "key": "value" for the usual secret-ish names. The closing
    # quote of a JSON key sits before the colon, so it has to be optional on
    # both sides of the separator.
    # An auth scheme word may sit between the key and the value
    # ("Authorization: Basic <base64>"). Matching it only after a known key
    # keeps prose like "basic authentication failed" untouched.
    (re.compile(r"(?i)\b(api[_-]?key|secret|token|passwd|password|authorization)"
                r"([\"']?\s*[:=]\s*)[\"']?(?:(?:basic|bearer|digest|token)\s+)?"
                r"[^\s\"',}]{8,}"), r"\1\2[redacted]"),
]


def _redact(text):
    """Mask secret-shaped runs so a failure line can be shown safely.

    The agent's output is captured, not streamed, so this line is often the
    only clue a person gets about an unrecognised failure — dropping it
    entirely would trade a leak for a blind error. Mask the secret instead
    and keep the diagnosis.
    """
    for shape, replacement in _SECRET_SHAPES:
        text = shape.sub(replacement, text)
    return text


def _short_failure(output, limit=240):
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    if not lines:
        return ""
    return _redact(lines[-1])[:limit]


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


def _bwrap_path():
    """Where Bubblewrap is, or None when this machine cannot cage anything.

    Split out so a test can point it at a stand-in. The NameError that broke
    setup on 2026-07-30 lived in the branch below this line: it never ran on
    a Mac, so nothing on a developer machine ever reached it, and every test
    passed while the only real execution path was broken.
    """
    if os.name != "posix" or sys.platform == "darwin":
        return None
    return shutil.which("bwrap")


def _cage(cmd, workdir):
    """Run an agent so the operating system decides what it may write to.

    Three of the four coding tools are invoked with their permission prompts
    turned off — `--dangerously-skip-permissions`, `--yolo`,
    `--permission-mode bypassPermissions` — and none of those three takes a
    workspace argument. Only codex constrains itself, with
    `--sandbox workspace-write`. So for the others nothing but the tool's own
    goodwill kept a write inside the project, and the checks cannot see a file
    written outside the worktree because they only read the staged diff.

    Where Bubblewrap is available (SlopNet installs and proves it during VPS
    setup) the whole filesystem is mounted read-only and only the task's own
    worktree and a private /tmp are writable. The tool's flags stop mattering:
    a write outside the project fails at the kernel, not at a prompt.

    Where it is not available — a Mac, or a server without bwrap — the command
    is returned unchanged. That is honest rather than silent: `slopnet run`
    refuses an unsandboxed unattended run separately, in run().
    """
    bwrap = _bwrap_path()
    if not bwrap:
        return cmd
    work = os.path.abspath(str(workdir))
    return " ".join([
        shlex.quote(bwrap),
        "--ro-bind", "/", "/",
        "--dev", "/dev",
        "--proc", "/proc",
        "--tmpfs", "/tmp",
        # The one writable place: this task's throwaway worktree.
        "--bind", shlex.quote(work), shlex.quote(work),
        "--chdir", shlex.quote(work),
        "--unshare-all", "--share-net",
        "--die-with-parent",
        "sh", "-c", shlex.quote(cmd),
    ])


def sandbox_available():
    """Whether this machine can cage an agent (see _cage)."""
    return bool(shutil.which("bwrap")) and sys.platform != "darwin"


def _resolve_worker_env(worker):
    """Build a subprocess env for env-cli. Secrets stay in memory only."""
    if not worker.get("env"):
        return None
    env = os.environ.copy()
    for name, value in worker["env"].items():
        if value.startswith("$"):
            resolved = os.environ.get(value[1:], "")
            if not resolved:
                crew_fail(
                    f"{worker['name']} needs {value[1:]} set in your shell.",
                    "That environment variable holds the key this worker needs.",
                    f"export {value[1:]}=… in your shell, then re-run this command",
                )
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


def _apply_resource_limits(limits):
    """Best-effort child limits for a VPS agent process.

    This runs in the child immediately before its agent command. Limits are
    inherited by that command and its children; unsupported platforms simply
    keep their normal operating-system limits.
    """
    if not limits or os.name != "posix":
        return
    try:
        import resource
    except ImportError:
        return
    choices = (
        (getattr(resource, "RLIMIT_AS", None), limits.get("memory_bytes")),
        (getattr(resource, "RLIMIT_NPROC", None), limits.get("processes")),
        (getattr(resource, "RLIMIT_CPU", None), limits.get("cpu_seconds")),
    )
    for kind, wanted in choices:
        if kind is None or not isinstance(wanted, int) or wanted <= 0:
            continue
        try:
            _, hard = resource.getrlimit(kind)
            ceiling = wanted if hard == resource.RLIM_INFINITY else min(wanted, hard)
            resource.setrlimit(kind, (ceiling, ceiling))
        except (OSError, ValueError):
            # The proof still has its command timeout and non-root identity.
            # Do not fail an otherwise safe setup merely because one host does
            # not expose a particular POSIX limit.
            continue


def _run_cli(worker, prompt, cwd, timeout, cancel_event=None):
    import shlex
    timeout = _worker_timeout(worker, timeout)
    prompt_path = None
    stdin = None
    if len(prompt.encode("utf-8")) > LONG_PROMPT_BYTES:
        if not cwd:
            crew_fail(
                "A working directory is required for a long agent prompt.",
                "Long prompts are written to a temp file inside the project.",
                "Re-run from inside your project folder",
            )
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
            crew_fail(
                f"{worker['name']} has no safe long-prompt transport in {CREW_FILE}.",
                "Long prompts need a file or stdin transport.",
                "Run: slopnet setup    to rebuild crew config",
            )
    else:
        cmd = worker["command"].replace("{prompt}", shlex.quote(prompt))
    cmd = _cage(cmd, cwd)
    try:
        # env-cli / hosted brain: env vars for this one invocation only.
        # Never exported to the shell, never written to disk, never printed.
        env = _resolve_worker_env(worker)
        popen_options = {"start_new_session": True} if os.name == "posix" else {}
        if worker.get("resource_limits") and os.name == "posix":
            limits = dict(worker["resource_limits"])
            popen_options["preexec_fn"] = lambda: _apply_resource_limits(limits)
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
            reason = classify_failure(output, returncode=proc.returncode)
            crew_fail(
                f"Agent failed: {reason}.",
                "The coding app exited without a successful edit.",
                "Fix login/quota/errors above, then re-run the same command",
            )
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
        crew_fail(
            "Not logged in.",
            "This API worker has no usable credentials.",
            "Set the required API key in your shell, then re-run",
        )
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
        reason = classify_failure(body, http_code=exc.code)
        crew_fail(
            f"Agent failed: {reason}.",
            "The HTTP API returned an error.",
            "Fix login/quota/network, then re-run",
        )
    except urllib.error.URLError as exc:
        if isinstance(exc.reason, (TimeoutError, socket.timeout)):
            raise CrewError(f"agent timed out after {timeout}s")
        crew_fail(
            f"{worker['name']} unreachable: {exc.reason}.",
            "The network call to the agent failed.",
            "Check network and credentials, then re-run",
        )
    except Exception as exc:
        crew_fail(
            f"{worker['name']} unreachable: {exc}.",
            "The network call to the agent failed.",
            "Check network and credentials, then re-run",
        )
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
    crew_fail(
        f"{worker['name']} is unproven: {reason}.",
        "Unproven agents are not allowed to write real work.",
        "Run: slopnet setup",
    )


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
                crew_fail(
                    f"Task {task_m.group(1)} sits outside any wave.",
                    "Every task must live under a ## Wave heading in WAVES.md.",
                    "Edit WAVES.md or re-run: slopnet plan \"your idea\"",
                )
            tid = task_m.group(1)
            if tid in seen:
                crew_fail(
                    f"Two tasks share the id {tid}.",
                    "Task ids must be unique in the plan.",
                    "Edit WAVES.md or re-run: slopnet plan \"your idea\"",
                )
            seen.add(tid)
            current.append({"id": tid, "body": []})
        elif current and line.strip():
            current[-1]["body"].append(line)
    for wave in waves:
        for task in wave:
            task["body"] = "\n".join(task["body"]).strip()
            files = re.search(r"^Files:\s*(.+)$", task["body"], re.MULTILINE)
            task["files"] = [f.strip() for f in files.group(1).split(",")] if files else []
            # "Files: none" is a task that cannot succeed: every attempt is
            # judged by what it changed, so a task that changes nothing is
            # always marked failed. Reject it while the plan is cheap to fix.
            placeholders = {"none", "n/a", "na", "-", "nothing", "tbd", "any"}
            if [f for f in task["files"] if f.lower() in placeholders]:
                crew_fail(
                    f"Task {task['id']} lists no real files (\"Files: "
                    f"{', '.join(task['files'])}\").",
                    "Work is judged by the files it changes, so a task that "
                    "changes nothing can never pass.",
                    "Give the task real file names, or ask for something that "
                    "creates or edits a file.")
            if not task["files"]:
                crew_fail(
                    f"Task {task['id']} has no 'Files:' line.",
                    "Each task must name the files it owns.",
                    "Edit WAVES.md or re-run: slopnet plan \"your idea\"",
                )
            # A task owns files INSIDE the project. The plan is written by a
            # model, so a path that climbs out of the project ("../"), starts
            # at the root, expands to a home directory, or reaches into .git
            # is refused here rather than handed to an agent as an
            # instruction. The sandbox is still the thing that stops a write;
            # this stops the plan from ever asking for one.
            escaped = [f for f in task["files"] if _escapes_project(f)]
            if escaped:
                crew_fail(
                    f"Task {task['id']} names files outside the project: "
                    + ", ".join(escaped) + ".",
                    "A task may only own paths inside the project, and never "
                    "the .git directory that records its history.",
                    "Use a path relative to the project, like src/app.py, then "
                    "re-run: slopnet plan \"your idea\"",
                )
            # The Files: line is not the only thing the agent reads. The task
            # body is handed to it verbatim as instructions, so a body that
            # says "copy ~/.ssh/config" escapes the project just as surely as
            # a Files: entry would — and only one of the coding tools runs
            # inside a workspace sandbox that would refuse it.
            reach = _body_reaches_outside(task["body"])
            if reach:
                crew_fail(
                    f"Task {task['id']} tells the agent to touch something "
                    f"outside the project: {reach}.",
                    "A task may only describe work inside its own project. "
                    "Reaching into a home directory, a system path, or the "
                    "history in .git is never part of building an app.",
                    "Reword the task to name only files inside the project, "
                    "then re-run: slopnet plan \"your idea\"",
                )
    waves = [w for w in waves if w]
    if not waves:
        crew_fail(
            "The plan contains no waves.",
            "There is nothing for the crew to run.",
            "Re-run: slopnet plan \"your idea\"",
        )
    for wave in waves:
        owned = [f for t in wave for f in t["files"]]
        clash = {f for f in owned if owned.count(f) > 1}
        if clash:
            crew_fail(
                "Two tasks in one wave both own: " + ", ".join(sorted(clash)) + ".",
                "Tasks in the same wave must not share files.",
                "Edit WAVES.md or re-run: slopnet plan \"your idea\"",
            )
    return waves


# Places a task body has no business naming. Deliberately a short, specific
# list of things that are always outside a project being built, so ordinary
# English ("go up a level in the menu", "the root of the page") does not trip
# it. This is defence in depth, not a language filter: it catches the plan
# that asks out loud, which is the realistic hallucinated case.
_BODY_REACHES = [
    (re.compile(r"(?<![\w.])\.\./"), "a path that climbs out with ../"),
    (re.compile(r"~/"), "a home directory path (~/)"),
    (re.compile(r"(?<![\w./])/(etc|root|var|usr|bin|sbin|proc|sys)/"),
     "a system directory"),
    (re.compile(r"(?<![\w./])/(Users|home)/"), "someone's home directory"),
    (re.compile(r"(?<![\w.])\.ssh\b"), ".ssh"),
    (re.compile(r"(?<![\w.])\.git/"), "the .git directory"),
    (re.compile(r"(?i)\bauthorized_keys\b"), "authorized_keys"),
    (re.compile(r"(?i)\b(?:/etc/)?(?:passwd|shadow)\b(?!\s*[:=])"),
     "the system password files"),
    (re.compile(r"(?i)\bcrontab\b"), "crontab"),
]


def _body_reaches_outside(body):
    """Describe the first out-of-project reach in a task body, else ''."""
    for pattern, description in _BODY_REACHES:
        if pattern.search(body or ""):
            return description
    return ""


def _escapes_project(path):
    """True when a 'Files:' entry does not stay inside the project.

    Checked on the raw text, not a resolved path: the plan is judged before
    anything touches a disk, and on a machine that is not the one the task
    will run on. Backslashes count as separators so a Windows-style path
    cannot smuggle a '..' segment past a '/'-only split.
    """
    text = (path or "").strip()
    if not text:
        return True
    if text.startswith("/") or text.startswith("~"):
        return True
    # A drive letter or UNC path is absolute too.
    if re.match(r"^[A-Za-z]:", text) or text.startswith("\\\\"):
        return True
    parts = [p for p in re.split(r"[\\/]+", text) if p]
    if any(p == ".." for p in parts):
        return True
    if parts and parts[0] == ".git":
        return True
    return False


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
        # Mask secret shapes BEFORE the plan is parsed, written to WAVES.md,
        # or committed. The planner reads the project with full access, so a
        # reply that echoes something it found in a .env would otherwise land
        # on disk and in git history. The failure path was already masked;
        # the success path is the one that persists.
        reply = _redact(reply)
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
    crew_fail(
        "The planner could not produce a valid plan.",
        str(errors),
        "Re-run: slopnet plan \"your idea\"    or edit WAVES.md by hand",
    )


# -------------------------------------------------------------- the wave runner

WORKER_BRIEF = """You are a coding agent working inside an isolated copy of \
a repository. Do the task below completely, editing files directly on disk.

House rules (breaking one fails your work):
- Only touch the files listed under Files:.
- Never rename anything. Never delete anything.
- No junk files, no .DS_Store, no secrets in code.
- Ship the code AND its tests together so the test suite passes.
- If the named files include a Dockerfile or Compose file: do not use root,
  privileged mode, host networking, a Docker socket mount, or hard-coded
  credentials. Only claim the container works after a real build and run.
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

        # Gate 1 — the checks, judging the STAGED work. This must happen
        # BEFORE the commit: they read the staged diff, so checking
        # afterwards would find an empty stage and pass on anything.
        if set_state:
            set_state("checking…")
        # A missing or empty checks/ used to mean this loop simply never ran:
        # the agent's work was kept without a single check, silently, and the
        # run still reported success. Refuse instead. "Nothing checked it" is
        # never a pass.
        scripts = sorted((root / "checks").glob("*.sh"))
        if not scripts:
            return False, branch, (
                "this project has no checks, so nothing can judge the work — "
                "no agent work is being kept")
        for check in scripts:
            proc = subprocess.run(["sh", str(check)], cwd=wt,
                                  capture_output=True, text=True)
            if proc.returncode != 0:
                first = (proc.stdout + proc.stderr).strip().splitlines()
                return False, branch, f"check said no: {first[0] if first else check.name}"

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
        crew_fail(
            "Your crew has nobody to write code.",
            "Setup did not save any writers.",
            "Run: slopnet setup",
        )
    for worker in fleet:
        require_proven(worker)
    waves_path = root / WAVES_FILE
    if not waves_path.exists():
        crew_fail(
            f"No {WAVES_FILE} yet.",
            "The crew needs a plan before it can run.",
            f"Run: slopnet plan \"your idea\"    or: slopnet go \"your idea\"",
        )
    waves = parse_waves(waves_path.read_text(encoding="utf-8"))
    refuse_fake_gate(crew.get("test_command", ""))

    # Nobody is watching an unattended run, so the machine has to be the thing
    # that keeps an agent inside the project. Every tool except codex is
    # invoked with its permission prompts switched off and no workspace
    # argument, so without a sandbox the only limit is the tool's own good
    # behaviour. Refuse rather than hope.
    unsandboxed = [w["name"] for w in crew.get("fleet", [])
                   if "--sandbox" not in (w.get("command") or "")]
    if unsandboxed and not sandbox_available():
        crew_fail(
            "This machine cannot keep a coding agent inside your project: "
            + ", ".join(sorted(set(unsandboxed))) + " would run unrestricted.",
            "These tools are started with their permission prompts turned off, "
            "so only the operating system can stop one writing outside the "
            "project — and the checks only ever see the project itself.",
            "Run the build on a server prepared by SlopNet, where Bubblewrap "
            "is installed and proved, or use a coding app that sandboxes "
            "itself",
        )

    code, dirty = _git(["status", "--porcelain"], root)
    if dirty.strip():
        crew_fail(
            "This repository has uncommitted work.",
            "The crew starts from a clean tree so none of your work is lost.",
            "Run: git status    then commit or: git stash    then re-run",
        )
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
