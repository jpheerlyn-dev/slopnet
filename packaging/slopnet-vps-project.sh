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
cd "$project_root"
git init -q
# This is deliberately plan-only. The person must see WAVES.md and make the
# next explicit choice before a coding agent can touch a project file.
exec /opt/slopnet/slopnet plan "$idea"'
encoded_project=$(printf '%s' "$remote_project" | base64 | tr -d '\n')

if [ "$username" = "root" ]; then
  ssh -tt -i "$key_path" -p "$port" "$username@$host" "umask 077; printf %s '$encoded_project' | base64 -d > /tmp/slopnet-project-plan.sh && chown slopnet:slopnet /tmp/slopnet-project-plan.sh && chmod 700 /tmp/slopnet-project-plan.sh && runuser -u slopnet -- env HOME=/home/slopnet sh /tmp/slopnet-project-plan.sh '$name_b64' '$idea_b64' </dev/tty; status=\$?; rm -f -- /tmp/slopnet-project-plan.sh; exit \$status"
else
  ssh -tt -i "$key_path" -p "$port" "$username@$host" "umask 077; printf %s '$encoded_project' | base64 -d > /tmp/slopnet-project-plan.sh && sudo chown slopnet:slopnet /tmp/slopnet-project-plan.sh && sudo chmod 700 /tmp/slopnet-project-plan.sh && sudo -u slopnet env HOME=/home/slopnet sh /tmp/slopnet-project-plan.sh '$name_b64' '$idea_b64' </dev/tty; status=\$?; rm -f -- /tmp/slopnet-project-plan.sh; exit \$status"
fi

say "Project planning finished. Read the plan shown above before choosing whether agents should start coding."
read -r -p "Press Return to close this project window: "
