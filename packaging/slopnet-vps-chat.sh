#!/usr/bin/env bash
# One private, finite conversation with the local model already proved by
# SlopNet.  It is deliberately not an agent: it has no tools, no listener,
# no provider credential and no route to the planner or the project runner.
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

if [ "$#" -ne 6 ]; then
  printf '%s\n' 'Usage: slopnet-vps-chat.sh HOST PORT USER QUESTION CONTEXT RELEASE' >&2
  exit 2
fi

host="$1"
port="$2"
username="$3"
question="$4"
context="$5"
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
if [ -z "$question" ]; then
  printf '%s\n' 'Ask the local guide a question first. Nothing ran.' >&2
  exit 1
fi
if ! [[ "$release" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf '%s\n' 'This copy of SlopNet has an invalid server release pin. Download it again.' >&2
  exit 1
fi

question_b64=$(printf '%s' "$question" | base64 | tr -d '\n')
# What has happened so far: earlier turns, and what the terminal has shown.
# Empty on the first question of a conversation.
context_b64=$(printf '%s' "$context" | base64 | tr -d '\n')
remote_chat='set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
question_b64=$1
context_b64=$2
release=$3
refuse_install() {
  echo "The server has an unknown or different SlopNet setup. Prepare it with this copy of the app, then try again. No action was taken."
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
[ "$(uname -s)" = Linux ] || refuse_install
[ -d /opt/slopnet/.git ] && [ ! -L /opt/slopnet ] || refuse_install
[ "$(git -C /opt/slopnet remote get-url origin)" = https://github.com/jpheerlyn-dev/slopnet.git ] || refuse_install
expected=$(git -C /opt/slopnet rev-parse "refs/tags/$release^{commit}" 2>/dev/null) || refuse_install
[ "$(git -C /opt/slopnet rev-parse HEAD)" = "$expected" ] || refuse_install
git -C /opt/slopnet diff --quiet "$expected" -- && [ -z "$(git -C /opt/slopnet status --porcelain --untracked-files=all)" ] || refuse_install
expected_account=$(runtime_receipt) || refuse_install
safe_marker /var/lib/slopnet/runtime-account-v2 "$expected_account" || refuse_install
expected_install=$(install_receipt "$expected") || refuse_install
safe_marker /var/lib/slopnet/install-v2 "$expected_install" || refuse_install
safe_marker /var/lib/slopnet/release-v1 "release=$release" || refuse_install
if ! id -u slopnet >/dev/null 2>&1; then
  echo "The protected SlopNet runtime account is missing. Run Connect and prepare this server first."
  exit 1
fi
runtime_uid=$(id -u slopnet)
runtime_home=$(getent passwd slopnet | cut -d: -f6)
if [ "$runtime_home" != /home/slopnet ] || [ ! -d "$runtime_home" ] || \
   [ -L "$runtime_home" ] || [ "$(stat -c %u "$runtime_home")" != "$runtime_uid" ]; then
  echo "The protected SlopNet runtime home no longer matches its marker. Nothing changed."
  exit 1
fi
llama="$runtime_home/.local/bin/llama"
config="$runtime_home/.local/share/slopnet/local-helper.env"
if [ ! -x "$llama" ] || [ ! -r "$config" ]; then
  echo "No local guide is ready yet. In Settings, install and test the local model first."
  exit 1
fi
if ! command -v timeout >/dev/null 2>&1; then
  echo "This Linux server has no timeout command, so the private guide cannot be bounded safely. No action was taken."
  exit 1
fi
model=$(sed -n "s/^SLOPNET_LOCAL_HELPER_MODEL=//p" "$config" | head -n 1)
if ! printf "%s" "$model" | grep -Eq "^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*(:[A-Za-z0-9][A-Za-z0-9._-]*)?$"; then
  echo "The selected local-model record is invalid. Reinstall it from Settings."
  exit 1
fi
question=$(printf "%s" "$question_b64" | base64 -d)
context=""
if [ -n "$context_b64" ]; then
  context=$(printf "%s" "$context_b64" | base64 -d)
fi
system_prompt="You are the private SlopNet guide, running on their own server. You can read what has happened so far, including what the terminal has printed. Use it to explain plainly what is going on and what to do next. You cannot run commands, open files, or change anything: you have no tools yet, so never claim to have done something, and never invent output you were not shown. If a build is wanted, say to choose Build, read the plan, then approve the run. Keep answers under 180 words."
if [ -n "$context" ]; then
  question_prompt="First output exactly SLOPNET_REPLY_START on one line. Then answer the question.\n\nWHAT HAS HAPPENED SO FAR:\n$context\n\nQUESTION:\n$question"
else
  question_prompt="First output exactly SLOPNET_REPLY_START on one line. Then answer the question.\n\nQUESTION:\n$question"
fi
run_model() {
  timeout 300 runuser -u slopnet -- env HOME="$runtime_home" PATH="$runtime_home/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    nice -n 10 "$llama" cli -hf "$model" --offline -c 4096 -b 512 -ub 256 --no-warmup -n 256 --single-turn \
    -sys "$system_prompt" -p "$question_prompt" -st --no-display-prompt --no-perf --simple-io
}
if ! model_output=$(run_model 2>&1); then
  echo "The private local guide could not reply within its safe limit. No action was taken. Try again."
  exit 1
fi
# This version of llama.cpp prints a visual banner and echoes the prompt even
# with its basic-I/O options. The marker is part of the model reply, so the
# app shows only that reply. A malformed answer stays a plain failure rather
# than leaking a transcript or silently falling through to a coding model.
# This build of llama.cpp echoes the whole prompt back regardless of its quiet
# options, and that echo contains the marker word — so matching the marker
# anywhere finds the instruction, not the answer. Requiring the marker alone on
# its line avoided that, but then a 3B model writing it inline threw the entire
# reply away and told the person their guide was unreadable.
#
# So anchor on the last thing known to belong to the echo: whichever comes
# later, the marker or the question itself. Everything after that is the reply.
reply=$(printf "%s\n" "$model_output" | LC_ALL=C awk -v q="$question" "
  { lines[NR] = \$0 }
  END {
    start = 0
    for (i = 1; i <= NR; i++) {
      if (index(lines[i], \"SLOPNET_REPLY_START\")) start = i
      if (length(q) && index(lines[i], q)) start = i
    }
    for (i = start + 1; i <= NR; i++) {
      if (lines[i] ~ /^\\[ Prompt:/) break
      if (lines[i] ~ /^Exiting/) break
      out[++n] = lines[i]
    }
    last = n
    while (last > 0 && out[last] ~ /^[[:space:]]*\$/) last--
    first = 1
    while (first <= last && out[first] ~ /^[[:space:]]*\$/) first++
    for (i = first; i <= last; i++) print out[i]
  }
" 2>/dev/null)
if [ -z "$reply" ]; then
  echo "The private local guide returned an unreadable reply. No action was taken. Try again."
  exit 1
fi
printf "%s\n" "$reply"
exit 0'
encoded_chat=$(printf '%s' "$remote_chat" | base64 | tr -d '\n')

# The temporary remote wrapper belongs to this one conversation and is removed
# immediately afterwards.  The model and its configuration stay private to
# the locked runtime account.
if [ "$username" = "root" ]; then
  /usr/bin/ssh -o "UserKnownHostsFile=$known_hosts_path" -T -i "$key_path" -p "$port" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes "$username@$host" "/bin/sh -c 'set -eu; umask 077; f=\$(/usr/bin/mktemp /tmp/slopnet-XXXXXXXX); cleanup_payload() { /bin/rm -f -- \"\$f\"; }; trap cleanup_payload EXIT HUP INT TERM; /usr/bin/printf \"%s\" \"\$1\" | /usr/bin/base64 -d > \"\$f\"; /bin/chmod 600 \"\$f\"; /bin/sh \"\$f\" \"\$2\" \"\$3\" \"\$4\"' slopnet-payload '$encoded_chat' '$question_b64' '$context_b64' '$release'"
else
  /usr/bin/ssh -o "UserKnownHostsFile=$known_hosts_path" -o LogLevel=ERROR -o StrictHostKeyChecking=yes -o IdentitiesOnly=yes -tt -i "$key_path" -p "$port" "$username@$host" "/usr/bin/sudo /bin/sh -c 'set -eu; umask 077; f=\$(/usr/bin/mktemp /tmp/slopnet-XXXXXXXX); cleanup_payload() { /bin/rm -f -- \"\$f\"; }; trap cleanup_payload EXIT HUP INT TERM; /usr/bin/printf \"%s\" \"\$1\" | /usr/bin/base64 -d > \"\$f\"; /bin/chmod 600 \"\$f\"; /bin/sh \"\$f\" \"\$2\" \"\$3\" \"\$4\" </dev/tty' slopnet-payload '$encoded_chat' '$question_b64' '$context_b64' '$release'"
fi
