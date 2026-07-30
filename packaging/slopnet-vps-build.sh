#!/usr/bin/env bash
# The third and deliberately separate step of the Mac app: run a plan the
# person has already read and explicitly approved.  It cannot be reached from
# local-model chat or from first-run setup.
set -euo pipefail

if [ "$#" -ne 4 ]; then
  printf '%s\n' 'Usage: slopnet-vps-build.sh HOST PORT USER PROJECT_NAME' >&2
  exit 2
fi

host="$1"
port="$2"
username="$3"
project_name="$4"
key_path="$HOME/.ssh/slopnet_vps_ed25519"

if [ ! -f "$key_path" ]; then
  printf '%s\n' 'SlopNet cannot find the protected VPS key. Run Connect and prepare this server first.' >&2
  exit 1
fi
case "$project_name" in
  ""|*[!a-z0-9-]*|[-]*)
    printf '%s\n' 'Project name did not pass SlopNet naming checks. Nothing ran.' >&2
    exit 1
    ;;
esac

project_b64=$(printf '%s' "$project_name" | base64 | tr -d '\n')
remote_build='set -eu
project_b64=$1
project_name=$(printf "%s" "$project_b64" | base64 -d)
case "$project_name" in
  ""|*[!a-z0-9-]*|[-]*)
    echo "Project name did not pass SlopNet naming checks. Nothing ran."
    exit 1
    ;;
esac
if ! id -u slopnet >/dev/null 2>&1; then
  echo "The protected SlopNet runtime account is missing. Run Connect and prepare this server first."
  exit 1
fi
runtime_home=$(getent passwd slopnet | cut -d: -f6)
project_root="$runtime_home/projects/$project_name"
if [ ! -d "$project_root/.git" ] || [ ! -f "$project_root/WAVES.md" ]; then
  echo "There is no saved plan for this project. Make and read a plan before starting agents."
  exit 1
fi
if [ ! -f "$project_root/.slopnet/crew.json" ]; then
  echo "The project has no proved coding crew. Nothing ran."
  exit 1
fi
# A directory on its own proves nothing: an empty checks/ used to satisfy this
# gate, and the runner would then judge the agents against zero checks. Count
# the real scripts, and name the ones a project must carry.
missing=""
for required_check in junk naming secrets slop-lint; do
  [ -f "$project_root/checks/$required_check.sh" ] || missing="$missing $required_check.sh"
done
if [ -n "$missing" ]; then
  echo "RULE: This project is missing the checks that judge agent work:$missing"
  echo "WHY:  Coding agents may only keep work that something has judged. With no checks there is nothing to stop a secret, a junk file, or fake work being kept."
  echo "FIX:  Your plan is safe. Make a new project so SlopNet can install its checks, or restore checks/ from /opt/slopnet/checks. Nothing ran."
  exit 1
fi
cd "$project_root"
exec runuser -u slopnet -- env HOME="$runtime_home" \
  PATH="$runtime_home/.local/bin:$runtime_home/.local/node_modules/.bin:/usr/local/bin:/usr/bin:/bin" \
  /opt/slopnet/slopnet run'
encoded_build=$(printf '%s' "$remote_build" | base64 | tr -d '\n')

if [ "$username" = "root" ]; then
  ssh -tt -i "$key_path" -p "$port" "$username@$host" "umask 077; f=\$(mktemp /tmp/slopnet-XXXXXXXX) || exit 1; trap 'rm -f -- \"\$f\"' EXIT HUP INT TERM; printf %s '$encoded_build' | base64 -d > \"\$f\" && chmod 700 \"\$f\" && sh \"\$f\" '$project_b64' </dev/tty"
else
  ssh -tt -i "$key_path" -p "$port" "$username@$host" "umask 077; f=\$(mktemp /tmp/slopnet-XXXXXXXX) || exit 1; trap 'rm -f -- \"\$f\"' EXIT HUP INT TERM; printf %s '$encoded_build' | base64 -d > \"\$f\" && sudo chmod 700 \"\$f\" && sudo sh \"\$f\" '$project_b64' </dev/tty"
fi
