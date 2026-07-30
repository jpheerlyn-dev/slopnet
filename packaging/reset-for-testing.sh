#!/usr/bin/env bash
# Put this Mac and a server back to how they look to somebody who has never
# run SlopNet, so the first-run experience can be tested honestly.
#
#   ./packaging/reset-for-testing.sh              # show what would go
#   ./packaging/reset-for-testing.sh --mac        # reset this Mac only
#   ./packaging/reset-for-testing.sh --server     # reset the server only
#   ./packaging/reset-for-testing.sh --all        # both
#
# Why this exists: deleting SlopNet.app removes almost nothing. macOS keeps
# preferences, request history and the connection key well outside the app
# bundle, so a reinstall walks straight past setup and the test proves
# nothing. On the server the same is true of the private runtime account.
#
# What it will NEVER touch: anything on the server that is not SlopNet's own.
# A VPS usually has other things running — a web server, a database, another
# model runner — and this removes the SlopNet account, the SlopNet install
# directory, and the key SlopNet added. Nothing else.
set -euo pipefail

mode="${1:---dry-run}"
do_mac=0
do_server=0
case "$mode" in
  --mac) do_mac=1 ;;
  --server) do_server=1 ;;
  --all) do_mac=1; do_server=1 ;;
  --dry-run) ;;
  *) printf 'Usage: %s [--mac|--server|--all]\n' "$0" >&2; exit 2 ;;
esac

app_id="com.slopnet.app"
support="$HOME/Library/Application Support/SlopNet"
key="$HOME/.ssh/slopnet_vps_ed25519"

host=$(defaults read "$app_id" SlopNetVPSHost 2>/dev/null || true)
port=$(defaults read "$app_id" SlopNetVPSPort 2>/dev/null || echo 22)
user=$(defaults read "$app_id" SlopNetVPSUser 2>/dev/null || echo root)

say() { printf '%s\n' "$1"; }

say ""
say "On this Mac:"
if defaults read "$app_id" >/dev/null 2>&1; then
  say "  · remembered server, and the flags saying setup and the guide passed"
else
  say "  · (no remembered settings)"
fi
[ -d "$support" ] && say "  · your saved request notes ($support)" \
                  || say "  · (no saved request notes)"
[ -f "$key" ] && say "  · the connection key SlopNet made ($key)" \
              || say "  · (no connection key)"

say ""
say "On the server${host:+ ($host)}:"
if [ -n "$host" ]; then
  say "  · the private slopnet account and its home, including any downloaded model"
  say "  · /opt/slopnet"
  say "  · the SlopNet key from ${user}'s authorized_keys"
  say ""
  say "  NOT touched: every other account, service and file. If that server"
  say "  also runs a web server, a database or another model, they stay."
else
  say "  · (no server remembered, nothing to do)"
fi

if [ "$do_mac" -eq 0 ] && [ "$do_server" -eq 0 ]; then
  say ""
  say "Nothing changed. Re-run with --mac, --server or --all to do it."
  exit 0
fi

say ""
printf 'Type RESET to confirm: '
read -r answer
[ "$answer" = "RESET" ] || { say "Nothing changed."; exit 0; }

if [ "$do_server" -eq 1 ] && [ -n "$host" ]; then
  say ""
  say "Resetting the server…"
  # Runs as the login account. Every removal names SlopNet explicitly; there
  # is no wildcard that could reach somebody else's files.
  remote='set -eu
if id -u slopnet >/dev/null 2>&1; then
  home=$(getent passwd slopnet | cut -d: -f6)
  pkill -u slopnet 2>/dev/null || true
  sleep 1
  userdel -r slopnet 2>/dev/null || userdel slopnet 2>/dev/null || true
  [ -n "$home" ] && [ -d "$home" ] && rm -rf -- "$home"
  echo "  removed the slopnet account and its home"
else
  echo "  no slopnet account"
fi
if [ -d /opt/slopnet ]; then
  rm -rf -- /opt/slopnet
  echo "  removed /opt/slopnet"
else
  echo "  no /opt/slopnet"
fi
keys="$HOME/.ssh/authorized_keys"
if [ -f "$keys" ] && grep -q "slopnet-vps" "$keys"; then
  tmp=$(mktemp)
  grep -v "slopnet-vps" "$keys" > "$tmp" || true
  cat "$tmp" > "$keys"
  rm -f -- "$tmp"
  echo "  removed the SlopNet key from authorized_keys"
else
  echo "  no SlopNet key in authorized_keys"
fi
echo "  left alone: every other account, service and file"'
  if [ "$user" = "root" ]; then
    ssh -p "$port" -o StrictHostKeyChecking=accept-new "$user@$host" "$remote"
  else
    ssh -t -p "$port" -o StrictHostKeyChecking=accept-new "$user@$host" "sudo sh -c '$remote'"
  fi
fi

if [ "$do_mac" -eq 1 ]; then
  say ""
  say "Resetting this Mac…"
  defaults delete "$app_id" 2>/dev/null && say "  forgot the remembered server and setup flags" \
    || say "  no remembered settings"
  if [ -d "$support" ]; then rm -rf -- "$support"; say "  removed saved request notes"; fi
  if [ -f "$key" ]; then
    ssh-add -d "$key" >/dev/null 2>&1 || true
    rm -f -- "$key" "$key.pub"
    say "  removed the connection key"
  fi
fi

say ""
say "Done. Delete SlopNet from Applications, install it again from the disc"
say "image, and it will open as it does for somebody who has never seen it."
