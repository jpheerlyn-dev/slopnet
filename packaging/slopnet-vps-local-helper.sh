#!/usr/bin/env bash
# Set up one optional, local Llama.cpp helper on a server prepared by SlopNet.
#
# This is intentionally not a service.  It runs one finite test under the
# locked `slopnet` account, stores only the selected public model identifier,
# and leaves no listening port behind.  A later project flow may ask the
# person whether to use it for a draft; it cannot start coding by itself.
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

if [ "$#" -lt 5 ] || [ "$#" -gt 6 ]; then
  printf '%s\n' 'Usage: slopnet-vps-local-helper.sh HOST PORT USER MODEL RELEASE [--approved]' >&2
  exit 2
fi

host="$1"
port="$2"
username="$3"
model="$4"
release="$5"
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
default_model="ibm-granite/granite-4.1-3b-GGUF:Q4_K_M"
# The wizard shows the download size and the server's free storage and memory,
# and will not enable its Install button until it has checked. Pressing that
# button is the approval. Asking twice more down here, in a terminal, is the
# interrogation that was taken out of server setup for the same reason.
approved="no"
[ "${6:-}" = "--approved" ] && approved="yes"

# Ask, unless it was already answered upstairs. Still printed either way, so
# the transcript records what was agreed to.
confirm() {
  if [ "$approved" = "yes" ]; then
    printf '\n%s [y/N] y   (approved in SlopNet before this started)\n' "$1"
    return 0
  fi
  read -r -p "$1 [y/N] " answer
  case "$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')" in
    y|yes) return 0 ;;
    *) return 1 ;;
  esac
}
# A request-rewriter never needs a model's enormous advertised context. This
# deliberately small bound prevents its KV cache from consuming an otherwise
# healthy server. It is not an agent-runtime limit and does not affect paid CLIs.
helper_context="4096"

say() {
  printf '\n%s\n' "$1"
}

valid_model() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*(:[A-Za-z0-9][A-Za-z0-9._-]*)?$ ]]
}

if ! valid_model "$model"; then
  printf '%s\n' 'Use a public Hugging Face GGUF identifier: owner/model:quant. URLs and tokens are not accepted.' >&2
  exit 2
fi
if ! [[ "$release" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf '%s\n' 'This copy of SlopNet has an invalid server release pin. Download it again.' >&2
  exit 2
fi
if [ ! -f "$key_path" ]; then
  printf '%s\n' 'SlopNet cannot find the protected server key from setup. Run Connect and prepare this server first.' >&2
  exit 1
fi

if command -v clear >/dev/null 2>&1; then
  clear 2>/dev/null || printf ''
fi
printf '\033]0;SlopNet local helper\007'
say "Optional SlopNet local helper"
say "Selected public Hugging Face model: ${model}"
if [ "$model" = "$default_model" ]; then
  say "IBM Granite 4.1 3B Q4_K_M is the default. Its published GGUF download is about 2.1 GB."
else
  say "SlopNet does not know this model's size in advance. The server will show its actual free storage and memory before it downloads it."
fi
say "Llama.cpp and the model will belong only to the locked slopnet account. No API key is requested or saved, no external model port is opened, and the one test exits when it is done."
if ! confirm "Continue?"; then
  say "Nothing changed on your server."
  exit 3
fi

model_b64=$(printf '%s' "$model" | base64 | tr -d '\n')
remote_approved="no"
[ "$approved" = "yes" ] && remote_approved="yes"
remote_setup='set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
umask 077
model_b64=$1
release=$3
# The approval, carried across explicitly. A shell function defined in the
# local half of this script does not exist over here: the remote half is
# base64-encoded, sent, and run by a fresh shell. Calling one here failed with
# "confirm: not found", took the "no" branch, printed "Nothing changed" and
# exited 0 — so the wrapper reported that setup had finished while nothing had
# been installed at all.
approved=${2:-no}
refuse_install() {
  echo "RULE: $1"
  echo "WHY:  The local guide must not change an unknown or stale server setup."
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
[ "$(uname -s)" = Linux ] || refuse_install "Local-guide setup currently supports Linux servers only."
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
confirm() {
  if [ "$approved" = "yes" ]; then
    printf "\n%s [y/N] y   (approved in SlopNet before this started)\n" "$1"
    return 0
  fi
  read -r answer_raw
  case "$(printf "%s" "$answer_raw" | tr "[:upper:]" "[:lower:]")" in
    y|yes) return 0 ;;
    *) return 1 ;;
  esac
}
default_model="ibm-granite/granite-4.1-3b-GGUF:Q4_K_M"
helper_context=4096
model=$(printf "%s" "$model_b64" | base64 -d)
case "$model" in
  *[!A-Za-z0-9._:/\-]*|*//*|/*/|:*:*)
    echo "Model identifier did not pass SlopNet safety checks. Nothing changed."
    exit 1
    ;;
esac
if ! printf "%s" "$model" | grep -Eq "^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*(:[A-Za-z0-9][A-Za-z0-9._-]*)?$"; then
  echo "Model identifier did not pass SlopNet safety checks. Nothing changed."
  exit 1
fi
if [ "$(id -u)" -ne 0 ]; then
  echo "The local helper must be prepared through the account that can use sudo. Nothing changed."
  exit 1
fi
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
if ! command -v curl >/dev/null 2>&1; then
  echo "This server has no curl command, so SlopNet cannot fetch the official Llama.cpp installer. Nothing changed."
  exit 1
fi
if ! command -v timeout >/dev/null 2>&1 || ! command -v free >/dev/null 2>&1 || \
   ! command -v od >/dev/null 2>&1 || ! command -v rev >/dev/null 2>&1; then
  echo "This Linux server cannot report, bound and challenge the local model safely because a required base command is missing. Nothing changed."
  exit 1
fi
disk_free=$(df -Pm "$runtime_home" | awk "NR==2 {print \$4}")
memory_free=$(free -m | awk "/Mem:/ {print \$7}")
case "$disk_free:$memory_free" in
  *[!0-9:]*|:*|*:) echo "The server did not return numeric storage and memory capacity. Nothing changed."; exit 1 ;;
esac
echo
echo "Protected runtime account: slopnet"
echo "Free storage: ${disk_free:-unknown} MiB"
echo "Available memory right now: ${memory_free:-unknown} MiB"
if [ "$model" = "$default_model" ]; then
  if [ -z "$disk_free" ] || [ "$disk_free" -lt 5000 ]; then
    echo "RULE: IBM Granite 4.1 3B needs more free storage than this server has reserved for a safe download."
    echo "WHY:  Its Q4_K_M GGUF is about 2.1 GB and SlopNet leaves room for the download and cache."
    echo "FIX:  Free at least 5000 MiB or choose a smaller public GGUF in Settings. Nothing changed."
    exit 1
  fi
  if [ "$memory_free" != "unknown" ] && [ "$memory_free" -lt 6000 ]; then
    echo "RULE: IBM Granite 4.1 3B needs more available memory than this server has right now."
    echo "WHY:  Its real bounded proof used about 3.9 GiB RSS; SlopNet keeps room for the server and other work."
    echo "FIX:  Stop other workloads or use a server with at least 6000 MiB available memory. Nothing changed."
    exit 1
  fi
fi
echo
echo "Llama.cpp will be installed from its official installer into the slopnet account."
echo "The selected public model will download now and answer one harmless one-time token. This can take a while."
echo "SlopNet limits this helper to a 4,096-token context and modest batches so a short draft cannot take over the server."
if ! confirm "Install and test it?"; then
  echo "Nothing changed."
  exit 3
fi

if [ ! -x "$runtime_home/.local/bin/llama" ]; then
  echo "Installing Llama.cpp as slopnet…"
  # Downloaded in full, then run. Piping a download into a shell hands the
  # interpreter a half-finished script line by line, so a connection that
  # drops midway executes the first half of an install and can still look
  # like it worked. llama.app is the ggml-org installer; it fetches from
  # their own Hugging Face bucket.
  llama_installer="$runtime_home/.cache/slopnet-llama-install.sh"
  runuser -u slopnet -- mkdir -p "$runtime_home/.cache"
  if ! runuser -u slopnet -- curl -fsSL --proto "=https" --tlsv1.2 --max-time 300 \
       -o "$llama_installer" https://llama.app/install.sh || [ ! -s "$llama_installer" ]; then
    runuser -u slopnet -- rm -f "$llama_installer"
    echo "The Llama.cpp installer could not be downloaded. Nothing was installed."
    exit 1
  fi
  runuser -u slopnet -- env HOME="$runtime_home" PATH="$runtime_home/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    sh "$llama_installer"
  runuser -u slopnet -- rm -f "$llama_installer"
fi
llama="$runtime_home/.local/bin/llama"
if [ ! -x "$llama" ]; then
  echo "The official installer finished without the expected llama command at $llama. Nothing else was configured."
  exit 1
fi

run_model() {
  timeout 900 runuser -u slopnet -- env HOME="$runtime_home" PATH="$runtime_home/.local/bin:/usr/local/bin:/usr/bin:/bin" "$@"
}

echo "Downloading and proving the selected model as slopnet…"
challenge=$(od -An -N12 -tx1 /dev/urandom | tr -d " \n")
expected_answer=$(printf "%s" "$challenge" | rev)
proof_prompt="Print only this token with its characters in reverse order: $challenge"
if ! proof_output=$(run_model nice -n 10 "$llama" cli -hf "$model" -c "$helper_context" -b 512 -ub 256 --no-warmup -p "$proof_prompt" -st --no-display-prompt --no-perf --simple-io); then
  echo "The local model test failed. Llama.cpp and any partial cache were left in the protected runtime account for inspection; SlopNet did not enable the helper."
  exit 1
fi
printf "%s\n" "$proof_output"
if ! printf "%s\n" "$proof_output" | grep -Fx -- "$expected_answer" >/dev/null; then
  echo "The local model did not answer its one-time harmless challenge. Llama.cpp and its cache were left for inspection; SlopNet did not enable the helper."
  exit 1
fi

config_dir="$runtime_home/.local/share/slopnet"
# Everything below the runtime home is controlled by the locked account. Do
# not follow one of its paths with a root install/chown/write: a pre-planted
# symlink could turn that into a privileged write somewhere else. Drop
# privilege first and let an atomic user-owned file replace the old choice.
if ! runuser -u slopnet -- env CONFIG_DIR="$config_dir" MODEL="$model" /bin/sh -c "
set -eu
umask 077
[ ! -L \"\$CONFIG_DIR\" ] || exit 1
mkdir -p -- \"\$CONFIG_DIR\"
[ -d \"\$CONFIG_DIR\" ] && [ ! -L \"\$CONFIG_DIR\" ] || exit 1
choice=
cleanup_choice() { [ -z \"\$choice\" ] || rm -f -- \"\$choice\"; }
trap cleanup_choice EXIT HUP INT TERM
choice=\$(mktemp \"\$CONFIG_DIR/.local-helper.env.XXXXXX\")
printf \"SLOPNET_LOCAL_HELPER_MODEL=%s\\n\" \"\$MODEL\" > \"\$choice\"
chmod 600 \"\$choice\"
mv -f -- \"\$choice\" \"\$CONFIG_DIR/local-helper.env\"
choice=
trap - EXIT HUP INT TERM
"; then
  echo "The locked account could not save its local-helper choice safely. Nothing was enabled."
  exit 1
fi
echo "[OK] Local helper passed. Selected model is private to the slopnet account and will be offered only as an optional request draft."
'
encoded_setup=$(printf '%s' "$remote_setup" | base64 | tr -d '\n')

if [ "$username" = "root" ]; then
  /usr/bin/ssh -o "UserKnownHostsFile=$known_hosts_path" -o LogLevel=ERROR -o StrictHostKeyChecking=yes -o IdentitiesOnly=yes -tt -i "$key_path" -p "$port" "$username@$host" "/bin/sh -c 'set -eu; umask 077; f=\$(/usr/bin/mktemp /tmp/slopnet-XXXXXXXX); cleanup_payload() { /bin/rm -f -- \"\$f\"; }; trap cleanup_payload EXIT HUP INT TERM; /usr/bin/printf \"%s\" \"\$1\" | /usr/bin/base64 -d > \"\$f\"; /bin/chmod 600 \"\$f\"; /bin/sh \"\$f\" \"\$2\" \"\$3\" \"\$4\" </dev/tty' slopnet-payload '$encoded_setup' '$model_b64' '$remote_approved' '$release'"
else
  /usr/bin/ssh -o "UserKnownHostsFile=$known_hosts_path" -o LogLevel=ERROR -o StrictHostKeyChecking=yes -o IdentitiesOnly=yes -tt -i "$key_path" -p "$port" "$username@$host" "/usr/bin/sudo /bin/sh -c 'set -eu; umask 077; f=\$(/usr/bin/mktemp /tmp/slopnet-XXXXXXXX); cleanup_payload() { /bin/rm -f -- \"\$f\"; }; trap cleanup_payload EXIT HUP INT TERM; /usr/bin/printf \"%s\" \"\$1\" | /usr/bin/base64 -d > \"\$f\"; /bin/chmod 600 \"\$f\"; /bin/sh \"\$f\" \"\$2\" \"\$3\" \"\$4\" </dev/tty' slopnet-payload '$encoded_setup' '$model_b64' '$remote_approved' '$release'"
fi

# Only say it finished if it did. This line printed after a remote half that
# had bailed out installing nothing, which is worse than any error: the app
# went on to the next step believing the guide was there.
say "The guide is installed and answered its test. It remains on your server; no model service is running."
