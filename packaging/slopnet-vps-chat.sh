#!/usr/bin/env bash
# One private, finite conversation with the local model already proved by
# SlopNet.  It is deliberately not an agent: it has no tools, no listener,
# no provider credential and no route to the planner or the project runner.
set -euo pipefail

if [ "$#" -lt 4 ] || [ "$#" -gt 5 ]; then
  printf '%s\n' 'Usage: slopnet-vps-chat.sh HOST PORT USER QUESTION [CONTEXT]' >&2
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
# What has happened so far: earlier turns, and what the terminal has shown.
# Empty on the first question of a conversation.
context_b64=$(printf '%s' "${5:-}" | base64 | tr -d '\n')
remote_chat='set -eu
question_b64=$1
context_b64=${2:-}
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
  if command -v timeout >/dev/null 2>&1; then
    timeout 300 runuser -u slopnet -- env HOME="$runtime_home" PATH="$runtime_home/.local/bin:/usr/local/bin:/usr/bin:/bin" \
      nice -n 10 "$llama" cli -hf "$model" --offline -c 16384 -b 512 -ub 256 --no-warmup -n 256 --single-turn \
      -sys "$system_prompt" -p "$question_prompt" -st --no-display-prompt --no-perf --simple-io
    return
  fi
  runuser -u slopnet -- env HOME="$runtime_home" PATH="$runtime_home/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    nice -n 10 "$llama" cli -hf "$model" --offline -c 16384 -b 512 -ub 256 --no-warmup -n 256 --single-turn \
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
  ssh -T -i "$key_path" -p "$port" -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$username@$host" "umask 077; f=\$(mktemp /tmp/slopnet-XXXXXXXX) || exit 1; trap 'rm -f -- \"\$f\"' EXIT HUP INT TERM; printf %s '$encoded_chat' | base64 -d > \"\$f\" && chmod 700 \"\$f\" && sh \"\$f\" '$question_b64' '$context_b64'"
else
  ssh -tt -i "$key_path" -p "$port" "$username@$host" "umask 077; f=\$(mktemp /tmp/slopnet-XXXXXXXX) || exit 1; trap 'rm -f -- \"\$f\"' EXIT HUP INT TERM; printf %s '$encoded_chat' | base64 -d > \"\$f\" && sudo chmod 700 \"\$f\" && sudo sh \"\$f\" '$question_b64' '$context_b64' </dev/tty"
fi
