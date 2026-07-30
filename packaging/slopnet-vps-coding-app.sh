#!/usr/bin/env bash
# Sign in to the coding app on a server SlopNet has already prepared.
#
# Deliberately separate from preparing the server. Signing in needs a browser,
# a link and a one-time code, and it is the slowest, most interruptible part of
# setup. It used to sit in the middle, which put the private local guide —
# the thing that helps somebody understand everything else — behind it. Now it
# runs last, and only when somebody wants to build something.
set -euo pipefail

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  printf '%s\n' 'Usage: slopnet-vps-coding-app.sh HOST PORT USER [PROVIDER]' >&2
  exit 2
fi

host="$1"
port="$2"
username="$3"
# Which coding app. Defaults to the one proved end to end on a real server.
provider="${4:-openai}"
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
cd /opt/slopnet
exec runuser -u slopnet -- env HOME=/home/slopnet \
  PATH=/home/slopnet/.local/bin:/home/slopnet/.local/node_modules/.bin:/usr/local/bin:/usr/bin:/bin \
  /opt/slopnet/slopnet setup --vps --coding-app-only --approved --provider PROVIDER'
remote=$(printf '%s' "$remote" | sed "s/PROVIDER/$provider/")
encoded=$(printf '%s' "$remote" | base64 | tr -d '\n')

if [ "$username" = "root" ]; then
  ssh -tt -i "$key_path" -p "$port" "$username@$host" "umask 077; f=\$(mktemp /tmp/slopnet-XXXXXXXX) || exit 1; trap 'rm -f -- \"\$f\"' EXIT HUP INT TERM; printf %s '$encoded' | base64 -d > \"\$f\" && sh \"\$f\" </dev/tty"
else
  ssh -tt -i "$key_path" -p "$port" "$username@$host" "umask 077; f=\$(mktemp /tmp/slopnet-XXXXXXXX) || exit 1; trap 'rm -f -- \"\$f\"' EXIT HUP INT TERM; printf %s '$encoded' | base64 -d > \"\$f\" && sudo sh \"\$f\" </dev/tty"
fi
