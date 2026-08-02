#!/usr/bin/env bash
# Sign in to the coding app on a server SlopNet has already prepared.
#
# Deliberately separate from preparing the server. Signing in needs a browser,
# a link and a one-time code, and it is the slowest, most interruptible part of
# setup. It used to sit in the middle, which put the private local guide —
# the thing that helps somebody understand everything else — behind it. Now it
# runs last, and only when somebody wants to build something.
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

if [ "$#" -ne 5 ]; then
  printf '%s\n' 'Usage: slopnet-vps-coding-app.sh HOST PORT USER PROVIDER RELEASE' >&2
  exit 2
fi

host="$1"
port="$2"
username="$3"
# Which coding app. Defaults to the one proved end to end on a real server.
provider="$4"
# The release this copy of the app expects on the server.
release="$5"
if ! [[ "$release" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf '%s\n' 'This copy of SlopNet has an invalid server release pin. Download it again.' >&2
  exit 2
fi
case "$provider" in
  anthropic|openai|google|xai) ;;
  *) printf '%s\n' "SlopNet does not know how to sign in to '$provider'." >&2; exit 2 ;;
esac
key_path="$HOME/.ssh/slopnet_vps_ed25519"
known_hosts_path="$HOME/.ssh/slopnet_vps_known_hosts"
if ! [[ "$host" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$ ]] ||
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
  printf '%s\n' 'SlopNet cannot find the key from setup. Prepare your server first.' >&2
  exit 1
fi

printf '\n%s\n' "Signing in to your coding app"
printf '%s\n' "A page will open in your browser and ask you to approve this. SlopNet never sees the login itself — your browser handles it, and the credential stays on your server."

remote='set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
release=$1
provider=$2

refuse() {
  echo "RULE: $1"
  echo "WHY:  A provider login must not execute an unknown or stale server checkout."
  echo "FIX:  Prepare this server with the current SlopNet app, then try sign-in again."
  exit 1
}
safe_marker() {
  # No apostrophes in here: this block lives inside a single-quoted payload.
  #
  # These names must not collide with anything a caller holds. The arguments
  # used to be taken as marker and expected, and sh has no local variables, so
  # calling this clobbered the caller variable named expected -- which holds
  # the release commit. The next line then recorded that wreckage in the commit
  # field of the install receipt, so the check could never pass, and the local
  # guide, project, build and coding-app flows all refused with "does not match
  # its protected ownership receipt".
  marker_path=$1
  marker_want=$2
  [ -d /var/lib/slopnet ] && [ ! -L /var/lib/slopnet ] || return 1
  [ "$(stat -c %u /var/lib/slopnet)" = 0 ] || return 1
  [ -z "$(find /var/lib/slopnet -maxdepth 0 -perm /022 -print -quit)" ] || return 1
  [ -f "$marker_path" ] && [ ! -L "$marker_path" ] || return 1
  [ "$(stat -c %u "$marker_path")" = 0 ] || return 1
  [ -z "$(find "$marker_path" -maxdepth 0 -perm /022 -print -quit)" ] || return 1
  [ "$(cat "$marker_path")" = "$marker_want" ] || return 1
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

[ "$(uname -s)" = Linux ] || refuse "Coding-app setup currently supports Linux only."
[ "$(id -u)" = 0 ] || refuse "Coding-app setup did not receive root privilege."
[ -d /opt/slopnet/.git ] && [ ! -L /opt/slopnet ] || \
  refuse "The managed server install is not a normal Git checkout."
[ "$(git -C /opt/slopnet remote get-url origin)" = \
  https://github.com/jpheerlyn-dev/slopnet.git ] || refuse "The server install has the wrong origin."
expected=$(git -C /opt/slopnet rev-parse "refs/tags/$release^{commit}" 2>/dev/null) || \
  refuse "The release tag expected by this app is not installed on the server."
[ "$(git -C /opt/slopnet rev-parse HEAD)" = "$expected" ] || \
  refuse "The server is on a different SlopNet release."
git -C /opt/slopnet diff --quiet "$expected" -- && \
  [ -z "$(git -C /opt/slopnet status --porcelain --untracked-files=all)" ] || \
  refuse "Protected server code differs from the released copy."
expected_account=$(runtime_receipt) || refuse "The runtime account is no longer locked to its private identity."
safe_marker /var/lib/slopnet/runtime-account-v2 "$expected_account" || \
  refuse "The runtime account does not match its protected ownership receipt."
expected_install=$(install_receipt "$expected") || refuse "The server install no longer has its protected identity."
safe_marker /var/lib/slopnet/install-v2 "$expected_install" || \
  refuse "The server install does not match its protected ownership receipt."
safe_marker /var/lib/slopnet/release-v1 "release=$release" || \
  refuse "The server release marker does not match this app."
for protected in /opt/slopnet/slopnet /opt/slopnet/crew.py; do
  [ -f "$protected" ] && [ ! -L "$protected" ] || refuse "Protected server code is not a normal file."
  [ "$(stat -c %u "$protected")" = 0 ] || refuse "Protected server code is not owned by root."
  [ -z "$(find "$protected" -maxdepth 0 -perm /022 -print -quit)" ] || \
    refuse "Protected server code is writable outside root."
done
home=$(getent passwd slopnet | cut -d: -f6)
[ "$home" = /home/slopnet ] || refuse "The runtime account home does not match its marker."
cd /opt/slopnet
exec runuser -u slopnet -- env HOME="$home" \
  PATH=/usr/bin:/bin:/usr/local/bin:/opt/slopnet:$home/.local/bin:$home/.kimi-code/bin:$home/.local/node_modules/.bin \
  /usr/bin/python3 /opt/slopnet/slopnet setup --vps --coding-app-only --approved --provider "$provider"'
encoded=$(printf '%s' "$remote" | base64 | tr -d '\n')

if [ "$username" = "root" ]; then
  /usr/bin/ssh -o "UserKnownHostsFile=$known_hosts_path" -o LogLevel=ERROR -o StrictHostKeyChecking=yes -o IdentitiesOnly=yes \
    -tt -i "$key_path" -p "$port" "$username@$host" "/bin/sh -c 'set -eu; umask 077; f=\$(/usr/bin/mktemp /tmp/slopnet-XXXXXXXX); cleanup_payload() { /bin/rm -f -- \"\$f\"; }; trap cleanup_payload EXIT HUP INT TERM; /usr/bin/printf \"%s\" \"\$1\" | /usr/bin/base64 -d > \"\$f\"; /bin/chmod 600 \"\$f\"; /bin/sh \"\$f\" \"\$2\" \"\$3\" </dev/tty' slopnet-payload '$encoded' '$release' '$provider'"
else
  /usr/bin/ssh -o "UserKnownHostsFile=$known_hosts_path" -o LogLevel=ERROR -o StrictHostKeyChecking=yes -o IdentitiesOnly=yes \
    -tt -i "$key_path" -p "$port" "$username@$host" "/usr/bin/sudo /bin/sh -c 'set -eu; umask 077; f=\$(/usr/bin/mktemp /tmp/slopnet-XXXXXXXX); cleanup_payload() { /bin/rm -f -- \"\$f\"; }; trap cleanup_payload EXIT HUP INT TERM; /usr/bin/printf \"%s\" \"\$1\" | /usr/bin/base64 -d > \"\$f\"; /bin/chmod 600 \"\$f\"; /bin/sh \"\$f\" \"\$2\" \"\$3\" </dev/tty' slopnet-payload '$encoded' '$release' '$provider'"
fi
