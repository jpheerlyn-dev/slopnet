#!/usr/bin/env bash
# The third and deliberately separate step of the Mac app: run a plan the
# person has already read and explicitly approved.  It cannot be reached from
# local-model chat or from first-run setup.
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

if [ "$#" -ne 6 ]; then
  printf '%s\n' 'Usage: slopnet-vps-build.sh HOST PORT USER PROJECT_NAME PLAN_COMMIT RELEASE' >&2
  exit 2
fi

host="$1"
port="$2"
username="$3"
project_name="$4"
plan_commit="$5"
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

if [ ! -f "$key_path" ]; then
  printf '%s\n' 'SlopNet cannot find the protected server key. Run Connect and prepare this server first.' >&2
  exit 1
fi
case "$project_name" in
  ""|*[!a-z0-9-]*|[-]*)
    printf '%s\n' 'Project name did not pass SlopNet naming checks. Nothing ran.' >&2
    exit 1
    ;;
esac
if ! [[ "$release" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf '%s\n' 'This copy of SlopNet has an invalid server release pin. Download it again.' >&2
  exit 1
fi
if ! [[ "$plan_commit" =~ ^[0-9a-f]{40,64}$ ]]; then
  printf '%s\n' 'The approved plan has no valid commit identity. Nothing ran.' >&2
  exit 1
fi

project_b64=$(printf '%s' "$project_name" | base64 | tr -d '\n')
remote_build='set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
project_b64=$1
plan_commit=$2
release=$3
project_name=$(printf "%s" "$project_b64" | base64 -d)
refuse_install() {
  echo "RULE: $1"
  echo "WHY:  Coding must not run against an unknown, writable or stale SlopNet install."
  echo "FIX:  Prepare this server with the current SlopNet app, then try again. Nothing ran."
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
[ "$(uname -s)" = Linux ] || refuse_install "Approved builds currently support Linux servers only."
protected_file /opt/slopnet/slopnet || refuse_install "The server runner is not protected root-owned code."
protected_file /opt/slopnet/crew.py || refuse_install "The server crew adapter is not protected root-owned code."
[ -d /opt/slopnet/.git ] && [ ! -L /opt/slopnet ] || refuse_install "The managed install is not a normal Git checkout."
[ "$(git -C /opt/slopnet remote get-url origin)" = https://github.com/jpheerlyn-dev/slopnet.git ] || refuse_install "The managed install has the wrong origin."
expected=$(git -C /opt/slopnet rev-parse "refs/tags/$release^{commit}" 2>/dev/null) || refuse_install "The app release tag is absent from the managed checkout."
[ "$(git -C /opt/slopnet rev-parse HEAD)" = "$expected" ] || refuse_install "The managed checkout is on a different release."
git -C /opt/slopnet diff --quiet "$expected" -- && [ -z "$(git -C /opt/slopnet status --porcelain --untracked-files=all)" ] || refuse_install "Protected server code differs from the released copy."
expected_account=$(runtime_receipt) || refuse_install "The runtime account is no longer locked to its private identity."
safe_marker /var/lib/slopnet/runtime-account-v2 "$expected_account" || refuse_install "The runtime account does not match its protected ownership receipt."
expected_install=$(install_receipt "$expected") || refuse_install "The server install no longer has its protected identity."
safe_marker /var/lib/slopnet/install-v2 "$expected_install" || refuse_install "The server install does not match its protected ownership receipt."
safe_marker /var/lib/slopnet/release-v1 "release=$release" || refuse_install "The server has a different SlopNet release."
approved_build=$(printf "kind=approved-build-v1\nrelease=%s\ncommit=%s" "$release" "$expected")
if ! safe_marker /var/lib/slopnet/approved-build-v1 "$approved_build"; then
  echo "RULE: This exact approved-build runner has not passed its controlled server proof."
  echo "WHY:  A plan can be kept safely, but unproved orchestration must not spend from a coding subscription or edit a project."
  echo "FIX:  Keep the plan only. A controlled server test must prove release $release and record its protected receipt before coding agents can run."
  exit 1
fi
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
runtime_uid=$(id -u slopnet)
runtime_home=$(getent passwd slopnet | cut -d: -f6)
if [ "$runtime_home" != /home/slopnet ] || [ ! -d "$runtime_home" ] || \
   [ -L "$runtime_home" ] || [ "$(stat -c %u "$runtime_home")" != "$runtime_uid" ]; then
  echo "The protected SlopNet runtime home no longer matches its marker. Nothing ran."
  exit 1
fi
project_root="$runtime_home/projects/$project_name"
if [ ! -d "$project_root/.git" ] || [ ! -f "$project_root/WAVES.md" ]; then
  echo "There is no saved plan for this project. Make and read a plan before starting agents."
  exit 1
fi
current_plan=$(/usr/bin/git -C "$project_root" rev-parse HEAD 2>/dev/null) || {
  echo "The saved project has no readable plan commit. Nothing ran."
  exit 1
}
if [ "$current_plan" != "$plan_commit" ]; then
  echo "The saved project changed after the plan you read. Make and approve a new plan; nothing ran."
  exit 1
fi
if ! /usr/bin/git -C "$project_root" diff --quiet "$plan_commit" -- || \
   [ -n "$(/usr/bin/git -C "$project_root" status --porcelain --untracked-files=all)" ]; then
  echo "The saved project differs from the exact plan you read. Make and approve a new plan; nothing ran."
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
  PATH="/usr/bin:/bin:/usr/local/bin:$runtime_home/.local/bin:$runtime_home/.local/node_modules/.bin" \
  /usr/bin/python3 /opt/slopnet/slopnet run'
encoded_build=$(printf '%s' "$remote_build" | base64 | tr -d '\n')

if [ "$username" = "root" ]; then
  /usr/bin/ssh -o "UserKnownHostsFile=$known_hosts_path" -o LogLevel=ERROR -o StrictHostKeyChecking=yes -o IdentitiesOnly=yes -tt -i "$key_path" -p "$port" "$username@$host" "/bin/sh -c 'set -eu; umask 077; f=\$(/usr/bin/mktemp /tmp/slopnet-XXXXXXXX); cleanup_payload() { /bin/rm -f -- \"\$f\"; }; trap cleanup_payload EXIT HUP INT TERM; /usr/bin/printf \"%s\" \"\$1\" | /usr/bin/base64 -d > \"\$f\"; /bin/chmod 600 \"\$f\"; /bin/sh \"\$f\" \"\$2\" \"\$3\" \"\$4\" </dev/tty' slopnet-payload '$encoded_build' '$project_b64' '$plan_commit' '$release'"
else
  /usr/bin/ssh -o "UserKnownHostsFile=$known_hosts_path" -o LogLevel=ERROR -o StrictHostKeyChecking=yes -o IdentitiesOnly=yes -tt -i "$key_path" -p "$port" "$username@$host" "/usr/bin/sudo /bin/sh -c 'set -eu; umask 077; f=\$(/usr/bin/mktemp /tmp/slopnet-XXXXXXXX); cleanup_payload() { /bin/rm -f -- \"\$f\"; }; trap cleanup_payload EXIT HUP INT TERM; /usr/bin/printf \"%s\" \"\$1\" | /usr/bin/base64 -d > \"\$f\"; /bin/chmod 600 \"\$f\"; /bin/sh \"\$f\" \"\$2\" \"\$3\" \"\$4\" </dev/tty' slopnet-payload '$encoded_build' '$project_b64' '$plan_commit' '$release'"
fi
