#!/usr/bin/env bash
# Read-only proof for every post-onboarding Mac SSH call.

PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

slopnet_ssh_dir="$HOME/.ssh"
slopnet_key_path="$slopnet_ssh_dir/slopnet_vps_ed25519"
slopnet_key_receipt="$slopnet_key_path.receipt"
slopnet_known_hosts="$slopnet_ssh_dir/slopnet_vps_known_hosts"
slopnet_known_hosts_receipt="$slopnet_known_hosts.receipt"

if stat -f '%u' "$HOME" >/dev/null 2>&1; then
  slopnet_owner() { stat -f '%u' "$1"; }
  slopnet_mode() { stat -f '%Lp' "$1"; }
  slopnet_dev() { stat -f '%d' "$1"; }
  slopnet_ino() { stat -f '%i' "$1"; }
else
  slopnet_owner() { stat -c '%u' "$1"; }
  slopnet_mode() { stat -c '%a' "$1"; }
  slopnet_dev() { stat -c '%d' "$1"; }
  slopnet_ino() { stat -c '%i' "$1"; }
fi

slopnet_prove_local_ssh() {
  slopnet_uid=$(id -u)
  [ -d "$slopnet_ssh_dir" ] && [ ! -L "$slopnet_ssh_dir" ] &&
    [ "$(slopnet_owner "$slopnet_ssh_dir")" = "$slopnet_uid" ] &&
    [ "$(slopnet_mode "$slopnet_ssh_dir")" = 700 ] || return 1
  for slopnet_file in "$slopnet_key_path" "$slopnet_key_path.pub" \
      "$slopnet_key_receipt" "$slopnet_known_hosts" \
      "$slopnet_known_hosts_receipt"; do
    [ -f "$slopnet_file" ] && [ ! -L "$slopnet_file" ] &&
      [ "$(slopnet_owner "$slopnet_file")" = "$slopnet_uid" ] &&
      [ "$(slopnet_mode "$slopnet_file")" = 600 ] || return 1
  done
  [ "$(wc -l < "$slopnet_key_path.pub" | tr -d ' ')" = 1 ] || return 1
  slopnet_public_line=$(sed -n '1p' "$slopnet_key_path.pub")
  case "$slopnet_public_line" in ssh-ed25519\ *\ slopnet-vps) ;; *) return 1 ;; esac
  slopnet_body=${slopnet_public_line#ssh-ed25519 }
  slopnet_body=${slopnet_body% slopnet-vps}
  printf '%s' "$slopnet_body" | grep -Eq '^[A-Za-z0-9+/]+={0,2}$' || return 1
  slopnet_private_sha=$(shasum -a 256 "$slopnet_key_path" | awk '{print $1}') || return 1
  slopnet_public_sha=$(shasum -a 256 "$slopnet_key_path.pub" | awk '{print $1}') || return 1
  slopnet_expected_key=$(printf \
    'kind=slopnet-ssh-key-v1\nprivate_dev=%s\nprivate_ino=%s\npublic_dev=%s\npublic_ino=%s\nprivate_sha256=%s\npublic_sha256=%s\npublic_line=%s' \
    "$(slopnet_dev "$slopnet_key_path")" "$(slopnet_ino "$slopnet_key_path")" \
    "$(slopnet_dev "$slopnet_key_path.pub")" "$(slopnet_ino "$slopnet_key_path.pub")" \
    "$slopnet_private_sha" "$slopnet_public_sha" "$slopnet_public_line")
  printf '%s\n' "$slopnet_expected_key" | cmp -s - "$slopnet_key_receipt" || return 1
  slopnet_derived=$(ssh-keygen -y -P '' -f "$slopnet_key_path" 2>/dev/null) || return 1
  [ "$slopnet_public_line" = "$slopnet_derived slopnet-vps" ] || return 1
  slopnet_expected_hosts=$(printf \
    'kind=slopnet-known-hosts-v1\nknown_hosts_dev=%s\nknown_hosts_ino=%s' \
    "$(slopnet_dev "$slopnet_known_hosts")" "$(slopnet_ino "$slopnet_known_hosts")")
  printf '%s\n' "$slopnet_expected_hosts" | \
    cmp -s - "$slopnet_known_hosts_receipt"
}

slopnet_require_local_ssh() {
  slopnet_prove_local_ssh && return 0
  printf '%s\n' \
    'SlopNet refused the connection because its dedicated key or host-trust receipt is missing or changed.' >&2
  printf '%s\n' \
    'Archive the same-named .ssh collision manually, then prepare this server again.' >&2
  return 1
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  slopnet_require_local_ssh
fi
