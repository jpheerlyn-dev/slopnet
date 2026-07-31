#!/usr/bin/env bash
# Remove SlopNet from a server, and nothing else.
#
# A server usually has other things on it — a website, a database, another model
# runner. This removes the private SlopNet account and its home, the SlopNet
# install directory, and the key SlopNet itself added. Every other account,
# service and file is left exactly as it was. There is no wildcard here that
# could reach somebody else's data.
set -euo pipefail

if [ "$#" -ne 3 ]; then
  printf '%s\n' 'Usage: slopnet-vps-uninstall.sh HOST PORT USER' >&2
  exit 2
fi

host="$1"
port="$2"
username="$3"
key_path="$HOME/.ssh/slopnet_vps_ed25519"

say() { printf '\n%s\n' "$1"; }

say "Removing SlopNet from ${host}"
say "This removes the private slopnet account and everything it downloaded, and the SlopNet folder. Other accounts, websites, databases and services on this server are not touched."
read -r -p "Remove it? [y/N] " answer
case "$(printf %s "$answer" | tr '[:upper:]' '[:lower:]')" in
  y|yes) ;;
  *) say "Nothing changed."; exit 0 ;;
esac

remote='set -eu
if id -u slopnet >/dev/null 2>&1; then
  home=$(getent passwd slopnet | cut -d: -f6)
  pkill -u slopnet 2>/dev/null || true
  sleep 1
  userdel -r slopnet 2>/dev/null || userdel slopnet 2>/dev/null || true
  if [ -n "$home" ] && [ -d "$home" ]; then rm -rf -- "$home"; fi
  echo "[OK] removed the private slopnet account and its files"
else
  echo "[OK] there was no slopnet account"
fi
if [ -d /opt/slopnet ]; then
  rm -rf -- /opt/slopnet
  echo "[OK] removed /opt/slopnet"
else
  echo "[OK] there was no /opt/slopnet"
fi
# Working files from setup and from the model benchmark. Each is created with
# mktemp under a slopnet- prefix, and an interrupted run leaves one behind.
rm -f -- /tmp/slopnet-* 2>/dev/null || true
echo "[OK] removed any leftover SlopNet working files in /tmp"
keys="$HOME/.ssh/authorized_keys"
if [ -f "$keys" ] && grep -q "slopnet-vps" "$keys"; then
  tmp=$(mktemp)
  grep -v "slopnet-vps" "$keys" > "$tmp" || true
  cat "$tmp" > "$keys"
  rm -f -- "$tmp"
  echo "[OK] removed the SlopNet key from this account"
fi
echo "[OK] every other account, service and file on this server was left alone"'
encoded=$(printf '%s' "$remote" | base64 | tr -d '\n')

# The key may already be gone; fall back to a password login so uninstalling
# still works after a partial removal.
ssh_opts="-tt -p $port -o StrictHostKeyChecking=accept-new"
if [ -f "$key_path" ]; then
  ssh_opts="$ssh_opts -i $key_path"
fi

# shellcheck disable=SC2086
if [ "$username" = "root" ]; then
  ssh -o LogLevel=ERROR -o StrictHostKeyChecking=accept-new $ssh_opts "$username@$host" "umask 077; f=\$(mktemp /tmp/slopnet-XXXXXXXX) || exit 1; trap 'rm -f -- \"\$f\"' EXIT HUP INT TERM; printf %s '$encoded' | base64 -d > \"\$f\" && sh \"\$f\" </dev/tty"
else
  ssh -o LogLevel=ERROR -o StrictHostKeyChecking=accept-new $ssh_opts "$username@$host" "umask 077; f=\$(mktemp /tmp/slopnet-XXXXXXXX) || exit 1; trap 'rm -f -- \"\$f\"' EXIT HUP INT TERM; printf %s '$encoded' | base64 -d > \"\$f\" && sudo sh \"\$f\" </dev/tty"
fi

say "SlopNet has been removed from your server."
