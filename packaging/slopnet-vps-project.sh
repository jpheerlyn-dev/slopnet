#!/usr/bin/env bash
# The interactive second step of the Mac app: one user-named server project and
# one plan. The app keeps the server details only in its current window; this
# helper does not save them and never receives a provider password or token.
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

if [ "$#" -ne 6 ]; then
  printf '%s\n' 'Usage: slopnet-vps-project.sh HOST PORT USER PROJECT_NAME IDEA RELEASE' >&2
  exit 2
fi

host="$1"
port="$2"
username="$3"
project_name="$4"
idea="$5"
release="$6"
key_path="$HOME/.ssh/slopnet_vps_ed25519"
known_hosts_path="$HOME/.ssh/slopnet_vps_known_hosts"
\n+if ! [[ "$host" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$ ]] ||
   ! [[ "$username" =~ ^[A-Za-z_][A-Za-z0-9_-]{0,31}$ ]] ||
   ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
  printf '%s\n' 'The server address, login name or port is invalid. Nothing connected.' >&2
  exit 2
fi
proof_helper="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/slopnet-local-ssh-proof.sh"
[ -f "$proof_helper" ] && [ ! -L "$proof_helper" ] || { printf '%s\n' 'The local SSH proof helper is missing.' >&2; exit 1; }
source "$proof_helper"
slopnet_require_local_ssh

say() {
  printf '\n%s\n' "$1"
}

if [ ! -f "$key_path" ]; then
  printf '%s\n' 'SlopNet cannot find the protected server key from setup. Run Set up my server first.' >&2
  exit 1
fi
if ! [[ "$release" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf '%s\n' 'This copy of SlopNet has an invalid server release pin. Download it again.' >&2
  exit 2
fi

clear
printf '\033]0;SlopNet project plan\007'
say "SlopNet project plan"
say "Your project will live only on your server. SlopNet will create exactly the folder named ${project_name}."
say "It will reuse the one coding app already proved on that server, make a plan, and stop for your approval before any coding agents run."
read -r -p "Continue? [y/N] " answer
answer_lower=$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')
case "$answer_lower" in
  y|yes) ;;
  *) say "Nothing changed."; exit 3 ;;
esac

name_b64=$(printf '%s' "$project_name" | base64 | tr -d '\n')
idea_b64=$(printf '%s' "$idea" | base64 | tr -d '\n')
remote_project='set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
name_b64=$1
idea_b64=$2
release=$3
project_name=$(printf "%s" "$name_b64" | base64 -d)
idea=$(printf "%s" "$idea_b64" | base64 -d)
refuse_install() {
  echo "RULE: $1"
  echo "WHY:  Planning must not execute an unknown, writable or stale SlopNet install."
  echo "FIX:  Prepare this server with the current SlopNet app, then try again. Nothing changed."
  exit 1
}
safe_marker() {
  marker=$1
  expected=$2
  [ -d /var/lib/slopnet ] && [ ! -L /var/lib/slopnet ] || return 1
  [ "$(stat -c %u /var/lib/slopnet)" = 0 ] || return 1
  [ -z "$(find /var/lib/slopnet -maxdepth 0 -perm /022 -print -quit)" ] || return 1
  [ -f "$marker" ] && [ ! -L "$marker" ] || return 1
  [ "$(stat -c %u "$marker")" = 0 ] || return 1
  [ -z "$(find "$marker" -maxdepth 0 -perm /022 -print -quit)" ] || return 1
  [ "$(cat "$marker")" = "$expected" ] || return 1
}
runtime_receipt() {
  uid=$(id -u slopnet 2>/dev/null) || return 1
  gid=$(id -g slopnet 2>/dev/null) || return 1
  home=$(getent passwd slopnet | cut -d: -f6)
  shell=$(getent passwd slopnet | cut -d: -f7)
  [ "$uid" -ne 0 ] && [ "$home" = /home/slopnet ] && \
    [ "$shell" = /usr/sbin/nologin ] || return 1
  [ -d "$home" ] && [ ! -L "$home" ] && [ "$(stat -c %u "$home")" = "$uid" ] || return 1
  [ "$(stat -c %a "$home")" = 700 ] && [ "$(getent group "$gid" | cut -d: -f1)" = slopnet ] || return 1
  [ "$(id -G slopnet)" = "$gid" ] || return 1
  password_state=$(passwd -S slopnet 2>/dev/null | awk "{print \$2}")
  [ "$password_state" = L ] || [ "$password_state" = LK ] || return 1
  printf "kind=runtime-account-v2\nname=slopnet\nuid=%s\ngid=%s\nhome=/home/slopnet\nshell=/usr/sbin/nologin\nhome_dev=%s\nhome_ino=%s" \
    "$uid" "$gid" "$(stat -c %d "$home")" "$(stat -c %i "$home")"
}
install_receipt() {
  commit=$1
  [ -d /opt/slopnet ] && [ ! -L /opt/slopnet ] && [ "$(stat -c %u /opt/slopnet)" = 0 ] || return 1
  [ -z "$(find /opt/slopnet -maxdepth 0 -perm /022 -print -quit)" ] || return 1
  printf "kind=install-v2\npath=/opt/slopnet\ndev=%s\nino=%s\nrelease=%s\ncommit=%s" \
    "$(stat -c %d /opt/slopnet)" "$(stat -c %i /opt/slopnet)" "$release" "$commit"
}
protected_file() {
  file=$1
  [ -f "$file" ] && [ ! -L "$file" ] || return 1
  [ "$(stat -c %u "$file")" = 0 ] || return 1
  [ -z "$(find "$file" -maxdepth 0 -perm /022 -print -quit)" ] || return 1
}
[ "$(uname -s)" = Linux ] || refuse_install "Project planning currently supports Linux servers only."
protected_file /opt/slopnet/slopnet || refuse_install "The server planner is not protected root-owned code."
protected_file /opt/slopnet/crew.py || refuse_install "The server crew adapter is not protected root-owned code."
[ -d /opt/slopnet/.git ] && [ ! -L /opt/slopnet ] || refuse_install "The managed install is not a normal Git checkout."
[ "$(git -c safe.directory=/opt/slopnet -C /opt/slopnet remote get-url origin)" = https://github.com/jpheerlyn-dev/slopnet.git ] || refuse_install "The managed install has the wrong origin."
expected=$(git -c safe.directory=/opt/slopnet -C /opt/slopnet rev-parse "refs/tags/$release^{commit}" 2>/dev/null) || refuse_install "The app release tag is absent from the managed checkout."
[ "$(git -c safe.directory=/opt/slopnet -C /opt/slopnet rev-parse HEAD)" = "$expected" ] || refuse_install "The managed checkout is on a different release."
git -c safe.directory=/opt/slopnet -C /opt/slopnet diff --quiet "$expected" -- && [ -z "$(git -c safe.directory=/opt/slopnet -C /opt/slopnet status --porcelain --untracked-files=all)" ] || refuse_install "Protected server code differs from the released copy."
expected_account=$(runtime_receipt) || refuse_install "The runtime account is no longer locked to its private identity."
safe_marker /var/lib/slopnet/runtime-account-v2 "$expected_account" || refuse_install "The runtime account does not match its protected ownership receipt."
expected_install=$(install_receipt "$expected") || refuse_install "The server install no longer has its protected identity."
safe_marker /var/lib/slopnet/install-v2 "$expected_install" || refuse_install "The server install does not match its protected ownership receipt."
safe_marker /var/lib/slopnet/release-v1 "release=$release" || refuse_install "The server has a different SlopNet release."
case "$project_name" in
  ""|*[!a-z0-9-]*|[-]*)
    echo "Project name did not pass SlopNet naming checks. Nothing changed."
    exit 1
    ;;
esac
if ! id -u slopnet >/dev/null 2>&1; then
  echo "The protected SlopNet runtime account is missing. Run Set up my server first."
  exit 1
fi
runtime_uid=$(id -u slopnet)
runtime_home=$(getent passwd slopnet | cut -d: -f6)
if [ "$runtime_home" != /home/slopnet ] || [ ! -d "$runtime_home" ] || \
   [ -L "$runtime_home" ] || [ "$(stat -c %u "$runtime_home")" != "$runtime_uid" ]; then
  echo "The protected SlopNet runtime home no longer matches its marker. Nothing changed."
  exit 1
fi
if [ ! -s /opt/slopnet/.slopnet/crew.json ]; then
  echo "No proved coding app is available yet. Run Set up my server first."
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
final_project_root="$runtime_home/projects/$project_name"
if [ -e "$final_project_root" ]; then
  echo "That project folder already exists. SlopNet will not build on top of it. Choose another name."
  exit 1
fi
project_checks_available=0
for project_check in junk naming protected-paths secrets slop-lint; do
  if [ -f "/opt/slopnet/checks/$project_check.sh" ]; then
    project_checks_available=$((project_checks_available + 1))
  fi
done
if [ "$project_checks_available" -eq 0 ]; then
  echo "RULE: This server has no SlopNet checks to give the new project."
  echo "WHY:  Coding agents are only allowed to keep work that something has judged."
  echo "FIX:  Re-run the server setup so /opt/slopnet/checks exists, then try again. Nothing changed."
  exit 1
fi
mkdir -p "$runtime_home/projects"
chmod 700 "$runtime_home/projects"
project_root=$(mktemp -d "$runtime_home/projects/.slopnet-plan.XXXXXX")
trap "rm -rf -- \"$project_root\"" EXIT HUP INT TERM
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
cd "$project_root"
git init -q
# This is deliberately plan-only. The person must see WAVES.md and make the
# next explicit choice before a coding agent can touch a project file.
if ! /usr/bin/python3 /opt/slopnet/slopnet plan "$idea"; then
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
plan_commit=$(git rev-parse HEAD)
mv "$project_root" "$final_project_root"
trap - EXIT HUP INT TERM
printf "SLOPNET_PLAN_COMMIT=%s\n" "$plan_commit"
echo "[OK] Plan recorded locally. No coding agent has run."'
encoded_project=$(printf '%s' "$remote_project" | base64 | tr -d '\n')

if [ "$username" = "root" ]; then
  /usr/bin/ssh -o "UserKnownHostsFile=$known_hosts_path" -o LogLevel=ERROR -o StrictHostKeyChecking=yes -o IdentitiesOnly=yes -tt -i "$key_path" -p "$port" "$username@$host" "/bin/sh -c 'set -eu; umask 077; f=\$(/usr/bin/mktemp /tmp/slopnet-XXXXXXXX); cleanup_payload() { /bin/rm -f -- \"\$f\"; }; trap cleanup_payload EXIT HUP INT TERM; /usr/bin/printf \"%s\" \"\$1\" | /usr/bin/base64 -d > \"\$f\"; /bin/chmod 0555 \"\$f\"; /usr/sbin/runuser -u slopnet -- /usr/bin/env HOME=/home/slopnet /bin/sh \"\$f\" \"\$2\" \"\$3\" \"\$4\" </dev/tty' slopnet-payload '$encoded_project' '$name_b64' '$idea_b64' '$release'"
else
  /usr/bin/ssh -o "UserKnownHostsFile=$known_hosts_path" -o LogLevel=ERROR -o StrictHostKeyChecking=yes -o IdentitiesOnly=yes -tt -i "$key_path" -p "$port" "$username@$host" "/usr/bin/sudo /bin/sh -c 'set -eu; umask 077; f=\$(/usr/bin/mktemp /tmp/slopnet-XXXXXXXX); cleanup_payload() { /bin/rm -f -- \"\$f\"; }; trap cleanup_payload EXIT HUP INT TERM; /usr/bin/printf \"%s\" \"\$1\" | /usr/bin/base64 -d > \"\$f\"; /bin/chmod 0555 \"\$f\"; /usr/sbin/runuser -u slopnet -- /usr/bin/env HOME=/home/slopnet /bin/sh \"\$f\" \"\$2\" \"\$3\" \"\$4\" </dev/tty' slopnet-payload '$encoded_project' '$name_b64' '$idea_b64' '$release'"
fi

say "Project planning finished. Read the plan shown above before choosing whether agents should start coding."
