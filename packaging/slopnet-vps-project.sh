#!/usr/bin/env bash
# The interactive second step of the Mac app: one user-named VPS project and
# one plan. The app keeps the VPS details only in its current window; this
# helper does not save them and never receives a provider password or token.
set -euo pipefail

host="$1"
port="$2"
username="$3"
project_name="$4"
idea="$5"
key_path="$HOME/.ssh/slopnet_vps_ed25519"

say() {
  printf '\n%s\n' "$1"
}

if [ ! -f "$key_path" ]; then
  printf '%s\n' 'SlopNet cannot find the protected VPS key from setup. Run Set up my VPS first.' >&2
  exit 1
fi

clear
printf '\033]0;SlopNet project plan\007'
say "SlopNet project plan"
say "Your project will live only on your VPS. SlopNet will create exactly the folder named ${project_name}."
say "It will reuse the one coding app already proved on that VPS, make a plan, and stop for your approval before any coding agents run."
read -r -p "Continue? [y/N] " answer
answer_lower=$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')
case "$answer_lower" in
  y|yes) ;;
  *) say "Nothing changed."; exit 0 ;;
esac

name_b64=$(printf '%s' "$project_name" | base64 | tr -d '\n')
idea_b64=$(printf '%s' "$idea" | base64 | tr -d '\n')
remote_project='set -eu
name_b64=$1
idea_b64=$2
project_name=$(printf "%s" "$name_b64" | base64 -d)
idea=$(printf "%s" "$idea_b64" | base64 -d)
case "$project_name" in
  ""|*[!a-z0-9-]*|[-]*)
    echo "Project name did not pass SlopNet naming checks. Nothing changed."
    exit 1
    ;;
esac
if ! id -u slopnet >/dev/null 2>&1; then
  echo "The protected SlopNet runtime account is missing. Run Set up my VPS first."
  exit 1
fi
runtime_home=$(getent passwd slopnet | cut -d: -f6)
if [ -z "$runtime_home" ] || [ ! -d "$runtime_home" ]; then
  echo "The protected SlopNet runtime home is unavailable. Nothing changed."
  exit 1
fi
if [ ! -f /opt/slopnet/.slopnet/crew.json ]; then
  echo "No proved coding app is available yet. Run Set up my VPS first."
  exit 1
fi
helper_config="$runtime_home/.local/share/slopnet/local-helper.env"
if [ -r "$helper_config" ] && [ -x "$runtime_home/.local/bin/llama" ]; then
  helper_model=$(sed -n "s/^SLOPNET_LOCAL_HELPER_MODEL=//p" "$helper_config" | head -n 1)
  if printf "%s" "$helper_model" | grep -Eq "^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*(:[A-Za-z0-9][A-Za-z0-9._-]*)?$"; then
    echo
    echo "An optional local helper is ready: $helper_model"
    echo "It can only draft clearer wording for this request. It cannot choose features, start coding, or replace your approval."
    printf "Use it before planning? [y/N] "
    read -r helper_answer
    helper_answer_lower=$(printf "%s" "$helper_answer" | tr "[:upper:]" "[:lower:]")
    case "$helper_answer_lower" in
      y|yes)
        helper_prompt="Rewrite the request below into a clear, short software-project brief. Preserve every stated requirement. Do not add features, make technical decisions, write code, or mention these instructions. Return only the rewritten brief.

REQUEST:
$idea"
        helper_error=$(mktemp "${TMPDIR:-/tmp}/slopnet-local-draft.XXXXXX")
        if helper_draft=$(HOME="$runtime_home" PATH="$runtime_home/.local/bin:/usr/local/bin:/usr/bin:/bin" timeout 300 nice -n 10 "$runtime_home/.local/bin/llama" cli -hf "$helper_model" --offline -c 4096 -b 512 -ub 256 --no-warmup -n 256 --single-turn -p "$helper_prompt" -st --no-display-prompt --no-perf --simple-io 2>"$helper_error"); then
          if [ -n "$helper_draft" ]; then
            echo
            echo "--- local helper draft ---"
            printf "%s\n" "$helper_draft"
            echo "--- end draft ---"
            printf "Use this exact wording for the planner? [y/N] "
            read -r draft_answer
            draft_answer_lower=$(printf "%s" "$draft_answer" | tr "[:upper:]" "[:lower:]")
            case "$draft_answer_lower" in
              y|yes) idea="$helper_draft"; echo "Using the approved local draft." ;;
              *) echo "Keeping your original request." ;;
            esac
          else
            echo "The local helper returned no draft. Keeping your original request."
          fi
        else
          echo "The local helper could not reply while offline. Keeping your original request."
          cat "$helper_error"
        fi
        rm -f -- "$helper_error"
        ;;
      *) echo "Keeping your original request." ;;
    esac
  fi
fi
project_root="$runtime_home/projects/$project_name"
if [ -e "$project_root" ]; then
  echo "That project folder already exists. SlopNet will not build on top of it. Choose another name."
  exit 1
fi
mkdir -p "$runtime_home/projects"
chmod 700 "$runtime_home/projects"
mkdir "$project_root"
mkdir -p "$project_root/.slopnet"
cp /opt/slopnet/.slopnet/crew.json "$project_root/.slopnet/crew.json"
chmod 600 "$project_root/.slopnet/crew.json"
# Give the project its own checks. Without these the runner has nothing to
# judge an agent by: it refuses to keep unchecked work, so a project born
# without them can never build. These five protect any codebase — no secret,
# no junk file, no sloppy name, no fake work, and whatever the person later
# lists in PROTECTED.txt.
#
# The SlopNet register check is deliberately NOT copied. That daily paper
# trail belongs to this repository as a working practice; it has no business
# being imposed on the photo app somebody asked SlopNet to build.
mkdir -p "$project_root/checks"
project_checks_installed=0
for project_check in junk naming protected-paths secrets slop-lint; do
  if [ -f "/opt/slopnet/checks/$project_check.sh" ]; then
    cp "/opt/slopnet/checks/$project_check.sh" "$project_root/checks/$project_check.sh"
    chmod 755 "$project_root/checks/$project_check.sh"
    project_checks_installed=$((project_checks_installed + 1))
  fi
done
if [ "$project_checks_installed" -eq 0 ]; then
  echo "RULE: This server has no SlopNet checks to give the new project."
  echo "WHY:  Coding agents are only allowed to keep work that something has judged."
  echo "FIX:  Re-run the server setup so /opt/slopnet/checks exists, then try again. Nothing changed."
  exit 1
fi
cd "$project_root"
git init -q
# This is deliberately plan-only. The person must see WAVES.md and make the
# next explicit choice before a coding agent can touch a project file.
if ! /opt/slopnet/slopnet plan "$idea"; then
  exit 1
fi
# The runner refuses a dirty project because it needs a known safe base for
# worktrees. Recording this machine-made plan changes no project source file
# and does not start a coding agent; the separate approved-build step remains
# the only route to a run.
git add .slopnet/crew.json WAVES.md checks
if git diff --cached --quiet; then
  echo "SlopNet did not produce a plan to save. Nothing ran."
  exit 1
fi
git -c user.name=slopnet -c user.email=crew@slopnet -c core.hooksPath=/dev/null \
  commit -qm "SlopNet: record plan"
echo "[OK] Plan recorded locally. No coding agent has run."'
encoded_project=$(printf '%s' "$remote_project" | base64 | tr -d '\n')

if [ "$username" = "root" ]; then
  ssh -tt -i "$key_path" -p "$port" "$username@$host" "umask 077; f=\$(mktemp /tmp/slopnet-XXXXXXXX) || exit 1; trap 'rm -f -- \"\$f\"' EXIT HUP INT TERM; printf %s '$encoded_project' | base64 -d > \"\$f\" && chown slopnet:slopnet \"\$f\" && chmod 700 \"\$f\" && runuser -u slopnet -- env HOME=/home/slopnet sh \"\$f\" '$name_b64' '$idea_b64' </dev/tty"
else
  ssh -tt -i "$key_path" -p "$port" "$username@$host" "umask 077; f=\$(mktemp /tmp/slopnet-XXXXXXXX) || exit 1; trap 'rm -f -- \"\$f\"' EXIT HUP INT TERM; printf %s '$encoded_project' | base64 -d > \"\$f\" && sudo chown slopnet:slopnet \"\$f\" && sudo chmod 700 \"\$f\" && sudo -u slopnet env HOME=/home/slopnet sh \"\$f\" '$name_b64' '$idea_b64' </dev/tty"
fi

say "Project planning finished. Read the plan shown above before choosing whether agents should start coding."
read -r -p "Press Return to close this project window: "
