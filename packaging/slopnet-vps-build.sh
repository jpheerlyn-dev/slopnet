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
if [ ! -d "$project_root/checks" ]; then
  echo "RULE: This project has no proved SlopNet runner yet."
  echo "WHY:  The current planner can make and save a plan, but a new project does not yet carry the project-specific walls the multi-agent runner needs."
  echo "FIX:  Keep the approved plan. Build and prove the per-project runner before asking agents to edit this project. Nothing ran."
  exit 1
fi
cd "$project_root"
exec runuser -u slopnet -- env HOME="$runtime_home" \
  PATH="$runtime_home/.local/bin:$runtime_home/.local/node_modules/.bin:/usr/local/bin:/usr/bin:/bin" \
  /opt/slopnet/slopnet run'
encoded_build=$(printf '%s' "$remote_build" | base64 | tr -d '\n')

if [ "$username" = "root" ]; then
  ssh -tt -i "$key_path" -p "$port" "$username@$host" "umask 077; printf %s '$encoded_build' | base64 -d > /tmp/slopnet-approved-build.sh && chmod 700 /tmp/slopnet-approved-build.sh && sh /tmp/slopnet-approved-build.sh '$project_b64' </dev/tty; status=\$?; rm -f -- /tmp/slopnet-approved-build.sh; exit \$status"
else
  ssh -tt -i "$key_path" -p "$port" "$username@$host" "umask 077; printf %s '$encoded_build' | base64 -d > /tmp/slopnet-approved-build.sh && sudo chmod 700 /tmp/slopnet-approved-build.sh && sudo sh /tmp/slopnet-approved-build.sh '$project_b64' </dev/tty; status=\$?; rm -f -- /tmp/slopnet-approved-build.sh; exit \$status"
fi
