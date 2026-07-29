#!/usr/bin/env bash
# One private, finite conversation with the local model already proved by
# SlopNet.  It is deliberately not an agent: it has no tools, no listener,
# no provider credential and no route to the planner or the project runner.
set -euo pipefail

if [ "$#" -ne 4 ]; then
  printf '%s\n' 'Usage: slopnet-vps-chat.sh HOST PORT USER QUESTION' >&2
  exit 2
fi

host="$1"
port="$2"
username="$3"
question="$4"
key_path="$HOME/.ssh/slopnet_vps_ed25519"

if [ ! -f "$key_path" ]; then
  printf '%s\n' 'SlopNet cannot find the protected VPS key. Run Connect and prepare this server first.' >&2
  exit 1
fi
if [ -z "$question" ]; then
  printf '%s\n' 'Ask the local guide a question first. Nothing ran.' >&2
  exit 1
fi

question_b64=$(printf '%s' "$question" | base64 | tr -d '\n')
remote_chat='set -eu
question_b64=$1
if ! id -u slopnet >/dev/null 2>&1; then
  echo "The protected SlopNet runtime account is missing. Run Connect and prepare this server first."
  exit 1
fi
runtime_home=$(getent passwd slopnet | cut -d: -f6)
if [ -z "$runtime_home" ] || [ ! -d "$runtime_home" ]; then
  echo "The protected SlopNet runtime home is unavailable. Nothing changed."
  exit 1
fi
llama="$runtime_home/.local/bin/llama"
config="$runtime_home/.local/share/slopnet/local-helper.env"
if [ ! -x "$llama" ] || [ ! -r "$config" ]; then
  echo "No local guide is ready yet. In Settings, install and test the local model first."
  exit 1
fi
model=$(sed -n "s/^SLOPNET_LOCAL_HELPER_MODEL=//p" "$config" | head -n 1)
if ! printf "%s" "$model" | grep -Eq "^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*(:[A-Za-z0-9][A-Za-z0-9._-]*)?$"; then
  echo "The selected local-model record is invalid. Reinstall it from Settings."
  exit 1
fi
question=$(printf "%s" "$question_b64" | base64 -d)
system_prompt="You are the private SlopNet setup guide. Explain only SlopNet, a VPS, setup choices, or request wording. You have no tools, files, or secrets. Never run, promise, or claim actions; never make a project, plan, agent, or build. For a build request, say to choose Build, read the plan, and approve the run. Keep answers under 180 words."
question_prompt="First output exactly SLOPNET_REPLY_START on one line. Then answer the question.\n\nQUESTION:\n$question"
run_model() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 300 runuser -u slopnet -- env HOME="$runtime_home" PATH="$runtime_home/.local/bin:/usr/local/bin:/usr/bin:/bin" \
      nice -n 10 "$llama" cli -hf "$model" --offline -c 4096 -b 512 -ub 256 --no-warmup -n 256 --single-turn \
      -sys "$system_prompt" -p "$question_prompt" -st --no-display-prompt --no-perf --simple-io
    return
  fi
  runuser -u slopnet -- env HOME="$runtime_home" PATH="$runtime_home/.local/bin:/usr/local/bin:/usr/bin:/bin" \
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
reply=$(printf "%s\n" "$model_output" | awk "
  /^SLOPNET_REPLY_START[[:space:]]*\$/ { showing = 1; next }
  showing && /^\\[ Prompt:/ { exit }
  showing && /^Exiting/ { exit }
  showing { print }
")
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
  ssh -T -i "$key_path" -p "$port" -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$username@$host" "umask 077; printf %s '$encoded_chat' | base64 -d > /tmp/slopnet-local-chat.sh && chmod 700 /tmp/slopnet-local-chat.sh && sh /tmp/slopnet-local-chat.sh '$question_b64'; status=\$?; rm -f -- /tmp/slopnet-local-chat.sh; exit \$status"
else
  ssh -tt -i "$key_path" -p "$port" "$username@$host" "umask 077; printf %s '$encoded_chat' | base64 -d > /tmp/slopnet-local-chat.sh && sudo chmod 700 /tmp/slopnet-local-chat.sh && sudo sh /tmp/slopnet-local-chat.sh '$question_b64' </dev/tty; status=\$?; rm -f -- /tmp/slopnet-local-chat.sh; exit \$status"
fi
