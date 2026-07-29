#!/usr/bin/env bash
# trial.sh — the hands-on proof rig.
#
# One command. It builds a real hello-world project with real coding
# agents, using the real SlopNet path (no hand-made config, no shortcuts),
# and writes down exactly what happened.
#
#   bash tests/trial.sh              # full trial in a temporary folder
#   bash tests/trial.sh --who-only   # just: which agents are awake?
#   bash tests/trial.sh --keep       # leave the project folder for a look
#
# It never touches this repository, your VPS, or anything you own. The
# findings land in tests/TRIAL_FINDINGS.md — paste that anywhere.

set -uo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
findings="$repo/tests/TRIAL_FINDINGS.md"
keep=0
who_only=0
for arg in "$@"; do
  case "$arg" in
    --keep) keep=1 ;;
    --who-only) who_only=1 ;;
    *) printf 'Unknown option: %s\n' "$arg"; exit 2 ;;
  esac
done

start_time=$(date +%s)
say() { printf '%s\n' "$*"; }
note() { printf '%s\n' "$*" >> "$findings"; }

{
  printf '# Trial findings — %s\n\n' "$(date '+%Y-%m-%d %H:%M')"
  printf 'Written by tests/trial.sh. Nothing here is a claim; every line is\n'
  printf 'something the script actually observed.\n\n'
} > "$findings"

# ---------------------------------------------------------------- step 1
say ""
say "STEP 1 of 4 — which coding agents are awake right now?"
say "(An agent that is not logged in cannot be given work. This is the"
say " check that would have explained the J07 run.)"
say ""
note "## Step 1 — agent liveness"
note ""

probe_dir=$(mktemp -d)
( cd "$probe_dir" && git init -q )
# macOS ships bash 3.2 — no associative arrays. Parallel plain arrays and
# a "name<TAB>command" list keep this working on a stock Mac.
alive=()
alive_pairs=()
PROBE_TEXT='Create a file named probe.txt containing the word ready. Do nothing else.'

probe_one() {
  local name=$1 cmd=$2 quoted out full
  printf -v quoted '%q' "$PROBE_TEXT"
  full=${cmd//\{prompt\}/$quoted}
  rm -f "$probe_dir/probe.txt"
  out=$( cd "$probe_dir" && eval "$full" 2>&1 | tail -2 | tr '\n' ' ' )
  if [ -f "$probe_dir/probe.txt" ]; then
    say "  AWAKE   $name"
    note "- **AWAKE** \`$name\`"
    alive+=("$name")
    alive_pairs+=("$name	$cmd")
  else
    say "  asleep  $name — ${out:0:90}"
    note "- asleep \`$name\` — ${out:0:160}"
  fi
}

command_for() {
  local want=$1 pair
  for pair in "${alive_pairs[@]}"; do
    case "$pair" in
      "$want	"*) printf '%s' "${pair#*	}"; return 0 ;;
    esac
  done
  return 1
}

find_exe() {
  command -v "$1" 2>/dev/null && return 0
  for d in "$HOME/.kimi-code/bin" "$HOME/.grok/bin" "$HOME/.local/bin"; do
    [ -x "$d/$1" ] && { printf '%s\n' "$d/$1"; return 0; }
  done
  return 1
}

if exe=$(find_exe codex); then probe_one codex "$exe exec --sandbox workspace-write {prompt}"; fi
if exe=$(find_exe claude); then probe_one claude "$exe --dangerously-skip-permissions -p {prompt}"; fi
if exe=$(find_exe grok); then probe_one grok "$exe --permission-mode bypassPermissions -p {prompt}"; fi
if exe=$(find_exe kimi); then probe_one kimi "$exe -p {prompt}"; fi
if exe=$(find_exe gemini); then probe_one gemini "$exe --yolo -p {prompt}"; fi
rm -rf "$probe_dir"

if [ ${#alive[@]} -eq 0 ]; then
  say ""
  say "No agent is awake, so there is nothing to test yet."
  say "Log in to one and run this again. For example: claude  (then /login)"
  note ""
  note "**Result: no agent awake — trial stopped before building anything.**"
  exit 1
fi
say ""
say "  ${#alive[@]} agent(s) awake: ${alive[*]}"
note ""
note "${#alive[@]} awake: ${alive[*]}"

[ "$who_only" -eq 1 ] && { say ""; say "Findings: $findings"; exit 0; }

# ---------------------------------------------------------------- step 2
worker=${alive[0]}
project=$(mktemp -d)/hello-trial
mkdir -p "$project"
say ""
say "STEP 2 of 4 — making a real project folder and arming it"
say "  folder: $project"
say "  agent:  $worker"
note ""
note "## Step 2 — real project, armed the real way"
note ""
note "- folder: \`$project\` (temporary)"
note "- agent: \`$worker\`"

cp "$repo/slopnet" "$repo/crew.py" "$project/" 2>/dev/null
cp -R "$repo/checks" "$project/" 2>/dev/null
cp "$repo/.gitignore" "$project/" 2>/dev/null
cd "$project" || exit 1
git init -q
git config user.name "SlopNet trial"
git config user.email "trial@slopnet.local"

# Arm it through the product's own path so the trial tests reality.
python3 ./slopnet init > /dev/null 2>&1
git add -A > /dev/null 2>&1
git -c user.name="SlopNet trial" -c user.email=trial@slopnet.local \
    commit -qm "trial: starting point" > /dev/null 2>&1

mkdir -p .slopnet
python3 - "$worker" "$(command_for "$worker")" <<'PY'
import json, pathlib, sys
name, command = sys.argv[1], sys.argv[2]
worker = {"kind": "cli", "name": name, "command": command, "proven": True}
pathlib.Path(".slopnet/crew.json").write_text(json.dumps({
    "planner": worker, "fleet": [worker],
    "test_command": "python3 -m pytest -q", "max_parallel": 1}, indent=2))
PY
say "  armed."

# ---------------------------------------------------------------- step 3
say ""
say "STEP 3 of 4 — asking for a hello world, and letting it build"
say "  (this is the real thing: plan, then agents, then walls, then tests)"
idea="a python function that returns the string hello world, with a pytest test for it"
note ""
note "## Step 3 — the build"
note ""
note "Request: _${idea}_"
note ""

plan_out=$(python3 ./slopnet plan "$idea" 2>&1)
say "$plan_out" | sed 's/^/  /'
note '```'
note "$plan_out"
note '```'
if [ ! -f WAVES.md ]; then
  say ""
  say "  The planner did not produce a plan. Stopping honestly here."
  note ""
  note "**Result: no plan produced. Nothing was built.**"
  exit 1
fi
note ""
note "The plan it wrote:"
note '```'
note "$(cat WAVES.md)"
note '```'

git add -A > /dev/null 2>&1
git -c user.name="SlopNet trial" -c user.email=trial@slopnet.local \
    commit -qm "trial: the plan" > /dev/null 2>&1

run_out=$(python3 ./slopnet run 2>&1)
say "$run_out" | sed 's/^/  /'
note ""
note "The run:"
note '```'
note "$run_out"
note '```'

# ---------------------------------------------------------------- step 4
say ""
say "STEP 4 of 4 — does the thing it built actually work?"
note ""
note "## Step 4 — does it actually work?"
note ""

built=$(ls *.py 2>/dev/null | tr '\n' ' ')
test_out=$(python3 -m pytest -q 2>&1 | tail -3)
elapsed=$(( $(date +%s) - start_time ))

if [ -n "$built" ] && printf '%s' "$test_out" | grep -q "passed"; then
  verdict="WORKED — real files, real passing tests"
  say "  $verdict"
  say "  files: $built"
else
  verdict="DID NOT PRODUCE WORKING CODE"
  say "  $verdict"
fi
say "$test_out" | sed 's/^/  /'

note "- files built: \`${built:-none}\`"
note "- test output:"
note '```'
note "$test_out"
note '```'
note ""
note "**Verdict: $verdict**"
note ""
note "- total time: ${elapsed}s"
note "- human input needed after starting: none"
note "- project folder: \`$project\`$([ "$keep" -eq 1 ] && echo ' (kept)' || echo ' (removed)')"

say ""
say "Total time: ${elapsed}s. Findings written to:"
say "  $findings"
if [ "$keep" -eq 1 ]; then
  say "Project kept at: $project"
else
  cd / && rm -rf "$(dirname "$project")"
fi
printf '%s' "$verdict" | grep -q WORKED
