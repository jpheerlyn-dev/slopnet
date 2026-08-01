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
# Server removal is delegated to the same receipt-checked uninstaller shipped
# in the app. This helper must never grow a second, name-only deletion path.
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
uninstaller="$root/packaging/slopnet-vps-uninstall.sh"

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
known_hosts="$HOME/.ssh/slopnet_vps_known_hosts"

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
say "On the remembered server:"
if [ -n "$host" ]; then
  say "  · the private slopnet account and its home, including any downloaded model"
  say "  · /opt/slopnet"
  say "  · only the exact receipt-backed SlopNet key from ${user}'s authorized_keys"
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
  [ -x "$uninstaller" ] || {
    say "The receipt-checked uninstaller is missing. Nothing was removed."
    exit 1
  }
  "$uninstaller" "$host" "$port" "$user"
elif [ "$do_server" -eq 1 ]; then
  say "No server is remembered, so safe server removal cannot identify a target. Nothing changed."
  exit 1
fi

if [ "$do_mac" -eq 1 ]; then
  # Resetting app state first would discard the server details needed to
  # remove an authorized key. Refuse every complete, partial, dangling or
  # legacy same-named connection artifact; the proved uninstaller removes only
  # an exact pair and its exact server line.
  for connection_path in \
      "$key" "$key.pub" "$key.receipt" \
      "$known_hosts" "$known_hosts.receipt"; do
    if [ -e "$connection_path" ] || [ -L "$connection_path" ]; then
      say "A SlopNet connection file remains at $connection_path."
      say "Mac reset stopped before forgetting the server or deleting notes."
      say "Run --all so the receipt-checked uninstaller can remove server access, or archive the collision manually."
      exit 1
    fi
  done
  say ""
  say "Resetting this Mac…"
  defaults delete "$app_id" 2>/dev/null && say "  forgot the remembered server and setup flags" \
    || say "  no remembered settings"
  if [ -d "$support" ]; then rm -rf -- "$support"; say "  removed saved request notes"; fi
fi

say ""
say "Done. Delete SlopNet from Applications, install it again from the disc"
say "image, and it will open as it does for somebody who has never seen it."
