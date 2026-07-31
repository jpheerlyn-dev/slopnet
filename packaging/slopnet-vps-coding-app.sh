#!/usr/bin/env bash
# Sign in to the coding app on a server SlopNet has already prepared.
#
# Deliberately separate from preparing the server. Signing in needs a browser,
# a link and a one-time code, and it is the slowest, most interruptible part of
# setup. It used to sit in the middle, which put the private local guide —
# the thing that helps somebody understand everything else — behind it. Now it
# runs last, and only when somebody wants to build something.
set -euo pipefail

if [ "$#" -lt 3 ] || [ "$#" -gt 5 ]; then
  printf '%s\n' 'Usage: slopnet-vps-coding-app.sh HOST PORT USER [PROVIDER]' >&2
  exit 2
fi

host="$1"
port="$2"
username="$3"
# Which coding app. Defaults to the one proved end to end on a real server.
provider="${4:-openai}"
# The release this copy of the app expects on the server.
release="${5:-}"
case "$provider" in
  anthropic|openai|google|xai) ;;
  *) printf '%s\n' "SlopNet does not know how to sign in to '$provider'." >&2; exit 2 ;;
esac
key_path="$HOME/.ssh/slopnet_vps_ed25519"

if [ ! -f "$key_path" ]; then
  printf '%s\n' 'SlopNet cannot find the key from setup. Prepare your server first.' >&2
  exit 1
fi

printf '\n%s\n' "Signing in to your coding app"
printf '%s\n' "A page will open in your browser and ask you to approve this. SlopNet never sees the login itself — your browser handles it, and the credential stays on your server."

remote='set -eu
release=$1
provider=$2
# Bring the server up to the release this app was built against before running
# anything from it. Nothing did this, so a Mac that had been updated kept
# driving whatever version the server was left on — and the two disagreeing is
# invisible until something behaves like an older build, which is exactly what
# happened: the app asked for a Gemini sign-in and the server ran Codex code.
if [ -n "$release" ] && [ -d /opt/slopnet/.git ]; then
  owner=$(stat -c %U /opt/slopnet 2>/dev/null || echo root)
  if [ "$owner" != "root" ] && command -v runuser >/dev/null 2>&1; then
    as_owner="runuser -u $owner --"
  else
    as_owner=""
  fi
  $as_owner git -c safe.directory=/opt/slopnet -C /opt/slopnet fetch --quiet --tags --force origin || true
  $as_owner git -c safe.directory=/opt/slopnet -c advice.detachedHead=false \
    -C /opt/slopnet checkout --quiet "$release" || true
fi
cd /opt/slopnet
exec runuser -u slopnet -- env HOME=/home/slopnet \
  PATH=/opt/slopnet:/home/slopnet/.local/bin:/home/slopnet/.local/node_modules/.bin:/usr/local/bin:/usr/bin:/bin \
  /opt/slopnet/slopnet setup --vps --coding-app-only --approved --provider "$provider"'
encoded=$(printf '%s' "$remote" | base64 | tr -d '\n')

if [ "$username" = "root" ]; then
  ssh -o LogLevel=ERROR -o StrictHostKeyChecking=accept-new -tt -i "$key_path" -p "$port" "$username@$host" "umask 077; f=\$(mktemp /tmp/slopnet-XXXXXXXX) || exit 1; trap 'rm -f -- \"\$f\"' EXIT HUP INT TERM; printf %s '$encoded' | base64 -d > \"\$f\" && sh \"\$f\" '$release' '$provider' </dev/tty"
else
  ssh -o LogLevel=ERROR -o StrictHostKeyChecking=accept-new -tt -i "$key_path" -p "$port" "$username@$host" "umask 077; f=\$(mktemp /tmp/slopnet-XXXXXXXX) || exit 1; trap 'rm -f -- \"\$f\"' EXIT HUP INT TERM; printf %s '$encoded' | base64 -d > \"\$f\" && sudo sh \"\$f\" '$release' '$provider' </dev/tty"
fi
