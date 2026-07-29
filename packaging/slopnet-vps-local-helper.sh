#!/usr/bin/env bash
# Set up one optional, local Llama.cpp helper on a VPS prepared by SlopNet.
#
# This is intentionally not a service.  It runs one finite test under the
# locked `slopnet` account, stores only the selected public model identifier,
# and leaves no listening port behind.  A later project flow may ask the
# person whether to use it for a draft; it cannot start coding by itself.
set -euo pipefail

if [ "$#" -ne 4 ]; then
  printf '%s\n' 'Usage: slopnet-vps-local-helper.sh HOST PORT USER MODEL' >&2
  exit 2
fi

host="$1"
port="$2"
username="$3"
model="$4"
key_path="$HOME/.ssh/slopnet_vps_ed25519"
default_model="ibm-granite/granite-4.1-8b-GGUF:Q4_K_M"
# A request-rewriter never needs a model's enormous advertised context. This
# deliberately small bound prevents its KV cache from consuming an otherwise
# healthy VPS. It is not an agent-runtime limit and does not affect paid CLIs.
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
  printf '%s\n' 'SlopNet cannot find the protected VPS key from setup. Run Connect and prepare this server first.' >&2
  exit 1
fi

if command -v clear >/dev/null 2>&1; then
  clear 2>/dev/null || printf ''
fi
printf '\033]0;SlopNet local helper\007'
say "Optional SlopNet local helper"
say "Selected public Hugging Face model: ${model}"
if [ "$model" = "$default_model" ]; then
  say "IBM Granite 4.1 8B Q4_K_M is the default. Its published GGUF download is about 5.35 GB."
else
  say "SlopNet does not know this model's size in advance. The server will show its actual free storage and memory before it downloads it."
fi
say "Llama.cpp and the model will belong only to the locked slopnet account. No API key is requested or saved, no external model port is opened, and the one test exits when it is done."
read -r -p "Continue? [y/N] " answer
answer_lower=$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')
case "$answer_lower" in
  y|yes) ;;
  *) say "Nothing changed."; exit 0 ;;
esac

model_b64=$(printf '%s' "$model" | base64 | tr -d '\n')
remote_setup='set -eu
umask 077
model_b64=$1
default_model="ibm-granite/granite-4.1-8b-GGUF:Q4_K_M"
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
if [ "$model" = "$default_model" ] && { [ -z "$disk_free" ] || [ "$disk_free" -lt 8000 ]; }; then
  echo "RULE: IBM Granite 4.1 8B needs more free storage than this server has reserved for a safe download."
  echo "WHY:  Its Q4_K_M GGUF is about 5.35 GB and SlopNet leaves room for the download and cache."
  echo "FIX:  Free at least 8000 MiB or choose a smaller public GGUF in Settings. Nothing changed."
  exit 1
fi
echo
echo "Llama.cpp will be installed from its official installer into the slopnet account."
echo "The selected public model will download now and answer one harmless word. This can take a while."
echo "SlopNet limits this helper to a 4,096-token context and modest batches so a short draft cannot take over the VPS."
read -r -p "Install and test it? [y/N] " answer
answer_lower=$(printf "%s" "$answer" | tr "[:upper:]" "[:lower:]")
case "$answer_lower" in
  y|yes) ;;
  *) echo "Nothing changed."; exit 0 ;;
esac

if [ ! -x "$runtime_home/.local/bin/llama" ]; then
  echo "Installing Llama.cpp as slopnet…"
  runuser -u slopnet -- env HOME="$runtime_home" PATH="$runtime_home/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    sh -c "curl -LsSf https://llama.app/install.sh | sh"
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
  ssh -tt -i "$key_path" -p "$port" "$username@$host" "umask 077; printf %s '$encoded_setup' | base64 -d > /tmp/slopnet-local-helper.sh && chmod 700 /tmp/slopnet-local-helper.sh && sh /tmp/slopnet-local-helper.sh '$model_b64' </dev/tty; status=\$?; rm -f -- /tmp/slopnet-local-helper.sh; exit \$status"
else
  ssh -tt -i "$key_path" -p "$port" "$username@$host" "umask 077; printf %s '$encoded_setup' | base64 -d > /tmp/slopnet-local-helper.sh && sudo chmod 700 /tmp/slopnet-local-helper.sh && sudo sh /tmp/slopnet-local-helper.sh '$model_b64' </dev/tty; status=\$?; rm -f -- /tmp/slopnet-local-helper.sh; exit \$status"
fi

say "Local helper setup finished. It remains on your server; no model service is running."
read -r -p "Press Return to close this setup window: "
