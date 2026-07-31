#!/usr/bin/env bash
# Set up one optional, local Llama.cpp helper on a server prepared by SlopNet.
#
# This is intentionally not a service.  It runs one finite test under the
# locked `slopnet` account, stores only the selected public model identifier,
# and leaves no listening port behind.  A later project flow may ask the
# person whether to use it for a draft; it cannot start coding by itself.
set -euo pipefail

if [ "$#" -lt 4 ] || [ "$#" -gt 5 ]; then
  printf '%s\n' 'Usage: slopnet-vps-local-helper.sh HOST PORT USER MODEL [--approved]' >&2
  exit 2
fi

host="$1"
port="$2"
username="$3"
model="$4"
key_path="$HOME/.ssh/slopnet_vps_ed25519"
default_model="ibm-granite/granite-4.1-3b-GGUF:Q4_K_M"
# The wizard shows the download size and the server's free storage and memory,
# and will not enable its Install button until it has checked. Pressing that
# button is the approval. Asking twice more down here, in a terminal, is the
# interrogation that was taken out of server setup for the same reason.
approved="no"
[ "${5:-}" = "--approved" ] && approved="yes"

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
  exit 0
fi

model_b64=$(printf '%s' "$model" | base64 | tr -d '\n')
remote_approved="no"
[ "$approved" = "yes" ] && remote_approved="yes"
remote_setup='set -eu
umask 077
model_b64=$1
# The approval, carried across explicitly. A shell function defined in the
# local half of this script does not exist over here: the remote half is
# base64-encoded, sent, and run by a fresh shell. Calling one here failed with
# "confirm: not found", took the "no" branch, printed "Nothing changed" and
# exited 0 — so the wrapper reported that setup had finished while nothing had
# been installed at all.
approved=${2:-no}
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
runtime_home=$(getent passwd slopnet | cut -d: -f6)
if [ -z "$runtime_home" ] || [ ! -d "$runtime_home" ]; then
  echo "The protected SlopNet runtime home is unavailable. Nothing changed."
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "This server has no curl command, so SlopNet cannot fetch the official Llama.cpp installer. Nothing changed."
  exit 1
fi
disk_free=$(df -Pm "$runtime_home" | awk "NR==2 {print \$4}")
memory_free="unknown"
if command -v free >/dev/null 2>&1; then
  memory_free=$(free -m | awk "/Mem:/ {print \$7}")
fi
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
echo "The selected public model will download now and answer one harmless word. This can take a while."
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
  if command -v timeout >/dev/null 2>&1; then
    timeout 900 runuser -u slopnet -- env HOME="$runtime_home" PATH="$runtime_home/.local/bin:/usr/local/bin:/usr/bin:/bin" "$@"
  else
    runuser -u slopnet -- env HOME="$runtime_home" PATH="$runtime_home/.local/bin:/usr/local/bin:/usr/bin:/bin" "$@"
  fi
}

echo "Downloading and proving the selected model as slopnet…"
if ! proof_output=$(run_model nice -n 10 "$llama" cli -hf "$model" -c "$helper_context" -b 512 -ub 256 --no-warmup -p "Reply with exactly READY." -st --no-display-prompt --no-perf --simple-io); then
  echo "The local model test failed. Llama.cpp and any partial cache were left in the protected runtime account for inspection; SlopNet did not enable the helper."
  exit 1
fi
printf "%s\n" "$proof_output"
if ! printf "%s\n" "$proof_output" | grep -Eq "(^|[^A-Za-z])READY[.!]?([^A-Za-z]|$)"; then
  echo "The local model did not complete the harmless READY proof. Llama.cpp and its cache were left for inspection; SlopNet did not enable the helper."
  exit 1
fi

config_dir="$runtime_home/.local/share/slopnet"
install -d -m 700 -o slopnet -g slopnet "$config_dir"
printf "SLOPNET_LOCAL_HELPER_MODEL=%s\n" "$model" > "$config_dir/local-helper.env"
chown slopnet:slopnet "$config_dir/local-helper.env"
chmod 600 "$config_dir/local-helper.env"
echo "[OK] Local helper passed. Selected model is private to the slopnet account and will be offered only as an optional request draft."
'
encoded_setup=$(printf '%s' "$remote_setup" | base64 | tr -d '\n')

if [ "$username" = "root" ]; then
  ssh -tt -i "$key_path" -p "$port" "$username@$host" "umask 077; f=\$(mktemp /tmp/slopnet-XXXXXXXX) || exit 1; trap 'rm -f -- \"\$f\"' EXIT HUP INT TERM; printf %s '$encoded_setup' | base64 -d > \"\$f\" && chmod 700 \"\$f\" && sh \"\$f\" '$model_b64' '$remote_approved' </dev/tty"
else
  ssh -tt -i "$key_path" -p "$port" "$username@$host" "umask 077; f=\$(mktemp /tmp/slopnet-XXXXXXXX) || exit 1; trap 'rm -f -- \"\$f\"' EXIT HUP INT TERM; printf %s '$encoded_setup' | base64 -d > \"\$f\" && sudo chmod 700 \"\$f\" && sudo sh \"\$f\" '$model_b64' '$remote_approved' </dev/tty"
fi

# Only say it finished if it did. This line printed after a remote half that
# had bailed out installing nothing, which is worse than any error: the app
# went on to the next step believing the guide was there.
say "The guide is installed and answered its test. It remains on your server; no model service is running."
