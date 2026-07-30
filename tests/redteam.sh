#!/usr/bin/env bash

set -u
set -o pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 1
source_root=$(cd "$script_dir/.." && pwd) || exit 1
tmp_parent=${TMPDIR:-/tmp}
tmp=$(mktemp -d "$tmp_parent/slopnet-redteam.XXXXXX") || exit 1
trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM

fail_setup() {
  printf 'REDTEAM SETUP FAILED: %s\n' "$1" >&2
  exit 1
}

if ! tar -C "$source_root" \
  --exclude='./.git' \
  --exclude='./build' \
  --exclude='./LOG.md' \
  --exclude='./.slopnet' \
  --exclude='./.DS_Store' \
  --exclude='*/.DS_Store' \
  -cf - . | tar -C "$tmp" -xf -; then
  fail_setup 'could not copy the template into the temporary workspace.'
fi

cd "$tmp" || fail_setup 'could not enter the temporary workspace.'
command -v python3 >/dev/null 2>&1 || fail_setup 'python3 is required for the CLI attacks.'
git init -q || fail_setup 'git init failed.'
git config user.name 'SlopNet Redteam' || fail_setup 'could not set the test author.'
git config user.email 'redteam@example.invalid' || fail_setup 'could not set the test email.'

install_rc=0
./install.sh >/dev/null 2>&1 || install_rc=$?
if [[ ! -f .git/hooks/pre-commit || ! -f .git/hooks/post-commit ]] || \
  ! grep -Fq '# slopnet-armed' .git/hooks/pre-commit || \
  ! grep -Fq '# slopnet-armed' .git/hooks/post-commit; then
  fail_setup "./install.sh did not arm both hooks (exit $install_rc)."
fi

git add -A || fail_setup 'could not stage the baseline.'
if ! git commit -m 'redteam baseline' >/dev/null 2>&1; then
  fail_setup 'the legitimate baseline commit was blocked.'
fi
baseline=$(git rev-parse HEAD) || fail_setup 'could not record the baseline commit.'

score=0

reset_workspace() {
  git reset --hard "$baseline" >/dev/null 2>&1 || return 1
  git clean -fdx >/dev/null 2>&1 || return 1
}

commit_attack() {
  git commit -m 'redteam attack' >/dev/null 2>&1
}

commit_bypass() {
  git commit --no-verify -m 'redteam bypass' >/dev/null 2>&1
}

write_aws_attack() {
  local aws_head='AKIA'
  local aws_tail='ABCDEFGHIJKLMNOP'
  printf '%s%s%s\n' 'AWS_KEY=' "$aws_head" "$aws_tail" > config.py
  git add config.py
}

verify_manifest() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -c MANIFEST.sha256 >/dev/null 2>&1
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c MANIFEST.sha256 >/dev/null 2>&1
  else
    return 1
  fi
}

attack_1() {
  printf '%s\n' 'junk' > .DS_Store || return 1
  git add -f .DS_Store || return 1
  ! commit_attack
}

attack_2() {
  mkdir -p __pycache__ || return 1
  printf '%s\n' 'junk' > __pycache__/x.pyc || return 1
  git add -f __pycache__/x.pyc || return 1
  ! commit_attack
}

attack_3() {
  printf '%s\n' 'debug' > debug.log || return 1
  git add -f debug.log || return 1
  ! commit_attack
}

attack_4() {
  local secret_tail=aaaaaaaaaaaaaaaaaaaaaaaa
  printf '%s%s\n' 'API_KEY=sk-' "$secret_tail" > .env || return 1
  git add -f .env || return 1
  ! commit_attack
}

attack_5() {
  write_aws_attack || return 1
  ! commit_attack
}

attack_6() {
  local private_open='-----BEGIN'
  local private_rest=' PRIVATE KEY-----'
  printf '%s%s\n' "$private_open" "$private_rest" > deploy.pem || return 1
  printf '%s\n' 'fake' >> deploy.pem || return 1
  git add deploy.pem || return 1
  ! commit_attack
}

attack_7() {
  printf '%s\n' 'copy' > 'notes copy.md' || return 1
  git add 'notes copy.md' || return 1
  ! commit_attack
}

attack_8() {
  printf '%s\n' 'untitled' > untitled.txt || return 1
  git add untitled.txt || return 1
  ! commit_attack
}

attack_9() {
  mkdir -p 'New Folder' || return 1
  printf '%s\n' 'new' > 'New Folder/x.txt' || return 1
  git add 'New Folder/x.txt' || return 1
  ! commit_attack
}

attack_10() {
  printf '%s\n' 'report' > report_final_v2.md || return 1
  git add report_final_v2.md || return 1
  ! commit_attack
}

attack_11() {
  printf '%s\n' 'backup' > main.py.bak || return 1
  git add main.py.bak || return 1
  ! commit_attack
}

attack_12() {
  mkdir -p MyStuff || return 1
  printf '%s\n' 'readme' > MyStuff/readme.md || return 1
  git add MyStuff/readme.md || return 1
  ! commit_attack
}

attack_13() {
  {
    printf '%s\n' 'def handle():'
    printf '%s\n' '    try:'
    printf '%s\n' '        pass'
    printf '%s%s\n' '    except' ':'
    printf '%s\n' '        pass'
  } > handler.py || return 1
  git add handler.py || return 1
  ! commit_attack
}

attack_14() {
  local catch_word='catch'
  local catch_args=' (e) '
  local catch_open='{'
  local catch_close='}'
  printf '%s%s%s%s\n' "$catch_word" "$catch_args" "$catch_open" "$catch_close" > api.js || return 1
  git add api.js || return 1
  ! commit_attack
}

attack_15() {
  local short_word='simplified'
  local version_word='version'
  local time_words='for now'
  printf '%s %s %s\n' "# $short_word" "$version_word" "$time_words" > service.py || return 1
  git add service.py || return 1
  ! commit_attack
}

attack_16() {
  git rm -r --cached -q register >/dev/null 2>&1 || return 1
  rm -rf -- register || return 1
  printf '%s\n' 'source' > missing-register.py || return 1
  git add missing-register.py || return 1
  if ! commit_attack; then
    return 0
  fi
  git ls-files --error-unmatch "register/$(date +%F).md" >/dev/null 2>&1
}

attack_17() {
  printf '%s\n' 'sealed/' >> PROTECTED.txt || return 1
  mkdir -p sealed || return 1
  printf '%s\n' 'sealed' > sealed/core.py || return 1
  git add PROTECTED.txt sealed/core.py || return 1
  ! commit_attack
}

attack_18() {
  write_aws_attack || return 1
  if ! commit_bypass; then
    return 0
  fi
  ! sh checks/secrets.sh --all >/dev/null 2>&1
}

attack_19() {
  printf '\n# tamper\n' >> checks/junk.sh || return 1
  git add checks/junk.sh || return 1
  if ! commit_bypass; then
    return 0
  fi
  ! verify_manifest
}

attack_20() {
  printf '%s\n' 'odd' > 'weird name (1).txt' || return 1
  git add 'weird name (1).txt' || return 1
  ! commit_attack
}

attack_21() {
  # The CLI must refuse an orbit whose name breaks the naming law,
  # and must create nothing.
  if python3 ./slopnet orbit new 'Bad Name' >/dev/null 2>&1; then
    return 1
  fi
  [ ! -e '../Bad Name' ]
}

attack_22() {
  # The MCP server must survive a call to a tool that does not exist:
  # respond with isError, keep serving, exit cleanly. A crashed guard
  # is an open gate.
  local out
  out=$(printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"drop_all_checks","arguments":{}}}' \
    '{"jsonrpc":"2.0","id":3,"method":"ping"}' \
    | python3 ./slopnet mcp) || return 1
  printf '%s' "$out" | grep -q '"isError": true' || return 1
  printf '%s' "$out" | grep -c '"jsonrpc"' | grep -qx '3'
}

attack_23() {
  # The CLI's own check verb must report staged junk exactly like the
  # hook would — one door, one law.
  printf 'x' > .DS_Store || return 1
  git add -f .DS_Store || return 1
  ! python3 ./slopnet check >/dev/null 2>&1
}

attack_24() {
  # Garbage on stdin must not kill the MCP server: it skips the junk
  # line and still answers the ping that follows.
  local out
  out=$(printf '%s\n' \
    'this is not json {{{' \
    '{"jsonrpc":"2.0","id":1,"method":"ping"}' \
    | python3 ./slopnet mcp) || return 1
  printf '%s' "$out" | grep -q '"id": 1'
}

attack_25() {
  # A tool call missing its required argument must come back as isError,
  # and the server must keep serving afterwards. A crashed guard is an
  # open gate.
  local out
  out=$(printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"sign_register","arguments":{}}}' \
    '{"jsonrpc":"2.0","id":3,"method":"ping"}' \
    | python3 ./slopnet mcp) || return 1
  printf '%s' "$out" | grep -q '"isError": true' || return 1
  printf '%s' "$out" | grep -c '"jsonrpc"' | grep -qx '3'
}

attack_26() {
  # A test command that can never fail must be refused outright: it would
  # launder bad work as proven. (StormCode's lesson, learned the hard way
  # when SlopNet's own crew merged a failing test during development.)
  python3 - <<'PY'
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("crew", pathlib.Path("crew.py"))
crew = importlib.util.module_from_spec(spec); spec.loader.exec_module(crew)
for bad in ("true", "exit 0", "pytest -q || true", "echo tests OK"):
    try:
        crew.refuse_fake_gate(bad)
    except crew.CrewError:
        continue
    sys.exit(1)          # a fake gate slipped through
try:
    crew.refuse_fake_gate("python3 -m pytest -q")
except crew.CrewError:
    sys.exit(1)          # a real gate was wrongly refused
PY
}

attack_27() {
  # A worker without a successful setup probe must be refused before its
  # command can touch the real repository.
  python3 - <<'PY'
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("crew", pathlib.Path("crew.py"))
crew = importlib.util.module_from_spec(spec); spec.loader.exec_module(crew)
root = pathlib.Path.cwd()
crew.save_crew(root, {
    "planner": {},
    "fleet": [{
        "kind": "cli",
        "name": "unproven-test-agent",
        "command": "touch unproven-ran",
        "proven": False,
        "proof": "ran but changed nothing",
        "timeout": 900,
    }],
    "test_command": "",
})
try:
    crew.run(root, lambda message: None)
except crew.CrewError as exc:
    if "unproven-test-agent is unproven" not in str(exc):
        sys.exit(1)
else:
    sys.exit(1)
if (root / "unproven-ran").exists():
    sys.exit(1)
PY
}

attack_28() {
  # Prompts over 100 KiB must travel through stdin without truncation and
  # their temporary file must be cleaned up afterwards.
  python3 - <<'PY'
import importlib.util, pathlib, sys, tempfile
spec = importlib.util.spec_from_file_location("crew", pathlib.Path("crew.py"))
crew = importlib.util.module_from_spec(spec); spec.loader.exec_module(crew)
root = pathlib.Path.cwd()
tempfile.tempdir = str(root)
worker = {
    "kind": "cli",
    "name": "long-prompt-test-agent",
    "command": "false {prompt}",
    "long_command": (
        "python3 -c 'import pathlib,sys; "
        "pathlib.Path(\"received.txt\").write_text(sys.stdin.read())'"
    ),
    "long_transport": "stdin",
    "timeout": 10,
}
prompt = "complete-brief\n" + ("x" * (crew.LONG_PROMPT_BYTES + 1))
crew.ask_worker(worker, prompt, cwd=str(root))
if (root / "received.txt").read_text() != prompt:
    sys.exit(1)
if list(root.glob(".slopnet-prompt-*.txt")):
    sys.exit(1)
PY
}

attack_29() {
  # An agent timeout must be an explicit failed attempt, never an empty
  # response that later gates could mistake for success.
  python3 - <<'PY'
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location("crew", pathlib.Path("crew.py"))
crew = importlib.util.module_from_spec(spec); spec.loader.exec_module(crew)
worker = {
    "kind": "cli",
    "name": "timeout-test-agent",
    "command": "exec python3 -c 'import time; time.sleep(5)' {prompt}",
    "timeout": 1,
}
try:
    crew.ask_worker(worker, "wait", cwd=str(pathlib.Path.cwd()))
except crew.CrewError as exc:
    if str(exc) == "agent timed out after 1s":
        sys.exit(0)
sys.exit(1)
PY
}

attack_30() {
  # A token in the environment for an env-cli worker must never appear in
  # any file the run writes — not .slopnet/, not the register, not cwd.
  # Token is assembled at runtime so this script itself does not contain it.
  python3 - <<'PY'
import importlib.util, os, pathlib, sys
spec = importlib.util.spec_from_file_location("crew", pathlib.Path("crew.py"))
crew = importlib.util.module_from_spec(spec); spec.loader.exec_module(crew)
root = pathlib.Path.cwd()
# Split so the full secret never appears as a literal in the harness source.
token = "rt-j02-" + "secret" + "-never-leak-" + "9f3a2c"
os.environ["ZAI_API_KEY"] = token
# Prove classified failures name the cause (report §7).
if crew.classify_failure("Authentication required") != "not logged in":
    sys.exit(1)
if crew.classify_failure("Rate limit reached") != "rate limited":
    sys.exit(1)
if crew.classify_failure("1113 Insufficient Balance") != (
        "insufficient balance (wrong endpoint or plan)"):
    sys.exit(1)
# env-cli run: host command writes an output file; token must not land
# in that file, crew.json, or anywhere under the workspace.
worker = {
    "kind": "env-cli",
    "name": "token-leak-test",
    "command": (
        "python3 -c 'import os,pathlib; "
        "pathlib.Path(\"env-cli-out.txt\").write_text("
        "\"ran base=\" + os.environ.get(\"ANTHROPIC_BASE_URL\",\"\")"
        ")' {prompt}"
    ),
    "env": {
        "ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic",
        "ANTHROPIC_AUTH_TOKEN": "$ZAI_API_KEY",
    },
    "timeout": 10,
}

crew.ask_worker(worker, "ping", cwd=str(root))
# Persist providers catalog the same way setup does — only $VAR form.
crew.save_crew(root, {
    "planner": {"kind": "env-cli", "name": "token-leak-test",
                "env": worker["env"]},
    "fleet": [],
    "test_command": "",
    "providers": crew.providers_catalog(),
})
# Register-style prose must not receive the token either.
reg = root / "register" / "token-check.md"
reg.parent.mkdir(exist_ok=True)
reg.write_text(
    "## check\n- env-cli ran; providers saved with $VAR indirection only.\n",
    encoding="utf-8",
)
# Only files the run wrote after the baseline copy: skip the harness itself
# and other pre-existing template files that never see the secret.
written = [
    root / "env-cli-out.txt",
    root / ".slopnet" / "crew.json",
    reg,
]
leaks = []
for path in written:
    if not path.is_file():
        sys.stderr.write("missing written file: %s\n" % path)
        sys.exit(1)
    text = path.read_text(encoding="utf-8", errors="replace")
    if token in text:
        leaks.append(str(path.relative_to(root)))
# Also scan every new path under .slopnet/ and register/ for the secret.
for folder in (root / ".slopnet", root / "register"):
    if not folder.exists():
        continue
    for path in folder.rglob("*"):
        if not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if token in text:
            rel = str(path.relative_to(root))
            if rel not in leaks:
                leaks.append(rel)
if leaks:
    sys.stderr.write("token leaked into: " + ", ".join(leaks) + "\n")
    sys.exit(1)
# crew.json must keep the $ indirection, never the resolved secret.
crew_text = (root / ".slopnet" / "crew.json").read_text(encoding="utf-8")
if "$ZAI_API_KEY" not in crew_text:
    sys.exit(1)
if token in crew_text:
    sys.exit(1)
# The host command must have actually run.
if "ran base=https://api.z.ai/api/anthropic" not in (
        root / "env-cli-out.txt").read_text(encoding="utf-8"):
    sys.exit(1)
PY
}

attack_31() {
  # A container gate must remain a constrained, offline non-root checker.
  # This static attack protects the posture even on machines without Docker;
  # GitHub Actions separately builds, parses and scans the actual image.
  python3 - <<'PY'
import pathlib
import sys

dockerfile = pathlib.Path("Dockerfile").read_text(encoding="utf-8")
compose = pathlib.Path("compose.yml").read_text(encoding="utf-8")
required_dockerfile = (
    "FROM python:3.12-slim-bookworm@sha256:d50fb7611f86d04a3b0471b46d7557818d88983fc3136726336b2a4c657aa30b",
    "USER 10001:10001",
    "ENTRYPOINT [\"python3\", \"/opt/slopnet/slopnet\"]",
)
required_compose = (
    "read_only: true",
    "network_mode: none",
    "- ALL",
    "no-new-privileges:true",
    "pids_limit: 128",
    "mem_limit: 512m",
)
for item in required_dockerfile + required_compose:
    if item not in dockerfile and item not in compose:
        sys.exit(1)
for forbidden in ("privileged:", "docker.sock", "network_mode: host"):
    if forbidden in dockerfile or forbidden in compose:
        sys.exit(1)
PY
}

record_landed() {
  local number=$1
  local label=$2
  printf 'LANDED %s %s\n' "$number" "$label"
  {
    printf '\n## Redteam — attack %s landed\n\n' "$number"
    printf -- '- %s landed in the temporary workspace; inspect the failing check before changing this script.\n' "$label"
  } >> register/PENDING_OPERATOR.md
  printf 'SCORE: %s/31\n' "$score"
  exit 1
}

run_attack() {
  local number=$1
  local label=$2
  local function=$3
  if "$function"; then
    score=$((score + 1))
    printf 'BLOCKED %s %s\n' "$number" "$label"
  else
    record_landed "$number" "$label"
  fi
  reset_workspace || fail_setup "could not reset after attack $number."
}

run_attack 1 '.DS_Store' attack_1
run_attack 2 '__pycache__/x.pyc' attack_2
run_attack 3 'debug.log' attack_3
run_attack 4 '.env secret' attack_4
run_attack 5 'AWS key' attack_5
run_attack 6 'private-key block' attack_6
run_attack 7 'notes copy.md' attack_7
run_attack 8 'untitled.txt' attack_8
run_attack 9 'New Folder/x.txt' attack_9
run_attack 10 'report_final_v2.md' attack_10
run_attack 11 'main.py.bak' attack_11
run_attack 12 'MyStuff/readme.md' attack_12
run_attack 13 'naked except' attack_13
run_attack 14 'empty catch' attack_14
run_attack 15 'shortcut phrase' attack_15
run_attack 16 'register auto-restore' attack_16
run_attack 17 'sealed path' attack_17
run_attack 18 'AWS key (CI-layer)' attack_18
run_attack 19 'manifest tamper (CI-layer)' attack_19
run_attack 20 'weird name (1).txt' attack_20
run_attack 21 'orbit bad name (CLI)' attack_21
run_attack 22 'MCP unknown tool' attack_22
run_attack 23 'staged junk via CLI check' attack_23
run_attack 24 'MCP garbage input (fuzz)' attack_24
run_attack 25 'MCP missing argument (fuzz)' attack_25
run_attack 26 'fake test gate refused (crew)' attack_26
run_attack 27 'unproven agent refused (crew)' attack_27
run_attack 28 'long prompt preserved (crew)' attack_28
run_attack 29 'agent timeout explicit (crew)' attack_29
run_attack 30 'env-cli token never written (crew)' attack_30
run_attack 31 'container gate constraints' attack_31

printf 'SCORE: %s/31\n' "$score"
[[ "$score" -eq 31 ]]
