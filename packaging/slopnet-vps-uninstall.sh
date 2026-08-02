#!/usr/bin/env bash
# Remove SlopNet from a server, and nothing else.
#
# A server usually has other things on it — a website, a database, another model
# runner. This removes the private SlopNet account and its home, the SlopNet
# install directory, and the key SlopNet itself added. Every other account,
# service and file is left exactly as it was. There is no wildcard here that
# could reach somebody else's data.
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

if [ "$#" -ne 3 ]; then
  printf '%s\n' 'Usage: slopnet-vps-uninstall.sh HOST PORT USER' >&2
  exit 2
fi

host="$1"
port="$2"
username="$3"
ssh_dir="$HOME/.ssh"
key_path="$ssh_dir/slopnet_vps_ed25519"
key_receipt_path="$key_path.receipt"
known_hosts_path="$ssh_dir/slopnet_vps_known_hosts"
known_hosts_receipt_path="$known_hosts_path.receipt"
if ! [[ "$username" =~ ^[A-Za-z_][A-Za-z0-9_-]{0,31}$ ]]; then
  printf '%s\n' 'The server login name is invalid. Nothing changed.' >&2
  exit 2
fi
if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
  printf '%s\n' 'The server port must be a number from 1 to 65535. Nothing changed.' >&2
  exit 2
fi
say() { printf '\n%s\n' "$1"; }

local_refuse() {
  printf '%s\n' "SlopNet will not use the dedicated SSH files: $1" >&2
  printf '%s\n' \
    "Archive the named .ssh collision yourself, then start removal again." >&2
  exit 1
}

if stat -f '%u' "$HOME" >/dev/null 2>&1; then
  local_owner() { stat -f '%u' "$1"; }
  local_mode() { stat -f '%Lp' "$1"; }
  local_dev() { stat -f '%d' "$1"; }
  local_ino() { stat -f '%i' "$1"; }
else
  local_owner() { stat -c '%u' "$1"; }
  local_mode() { stat -c '%a' "$1"; }
  local_dev() { stat -c '%d' "$1"; }
  local_ino() { stat -c '%i' "$1"; }
fi

local_exists() { [ -e "$1" ] || [ -L "$1" ]; }

prepare_ssh_directory() {
  local_uid=$(id -u)
  if local_exists "$ssh_dir"; then
    [ -d "$ssh_dir" ] && [ ! -L "$ssh_dir" ] || \
      local_refuse "$ssh_dir is redirected or is not a directory."
    [ "$(local_owner "$ssh_dir")" = "$local_uid" ] || \
      local_refuse "$ssh_dir is not owned by this Mac account."
  else
    old_umask=$(umask)
    umask 077
    mkdir "$ssh_dir" || local_refuse "$ssh_dir could not be created safely."
    umask "$old_umask"
  fi
  [ -d "$ssh_dir" ] && [ ! -L "$ssh_dir" ] && \
    [ "$(local_owner "$ssh_dir")" = "$local_uid" ] || \
    local_refuse "$ssh_dir changed while it was being checked."
  chmod 700 "$ssh_dir"
  [ "$(local_mode "$ssh_dir")" = 700 ] || \
    local_refuse "$ssh_dir does not have private permissions."
}

key_paths_complete() {
  local_exists "$key_path" && local_exists "$key_path.pub" && \
    local_exists "$key_receipt_path"
}
key_paths_absent() {
  ! local_exists "$key_path" && ! local_exists "$key_path.pub" && \
    ! local_exists "$key_receipt_path"
}
known_hosts_paths_complete() {
  local_exists "$known_hosts_path" && local_exists "$known_hosts_receipt_path"
}
known_hosts_paths_absent() {
  ! local_exists "$known_hosts_path" && ! local_exists "$known_hosts_receipt_path"
}

validate_key_pair() {
  local_uid=$(id -u)
  for protected in "$key_path" "$key_path.pub" "$key_receipt_path"; do
    [ -f "$protected" ] && [ ! -L "$protected" ] || return 1
    [ "$(local_owner "$protected")" = "$local_uid" ] || return 1
    [ "$(local_mode "$protected")" = 600 ] || return 1
  done
  [ "$(wc -l < "$key_path.pub" | tr -d ' ')" = 1 ] || return 1
  public_line=$(sed -n '1p' "$key_path.pub")
  case "$public_line" in
    ssh-ed25519\ *\ slopnet-vps) ;;
    *) return 1 ;;
  esac
  public_body=${public_line#ssh-ed25519 }
  public_body=${public_body% slopnet-vps}
  printf '%s' "$public_body" | grep -Eq '^[A-Za-z0-9+/]+={0,2}$' || return 1
  private_sha256=$(shasum -a 256 "$key_path" | awk '{print $1}') || return 1
  public_sha256=$(shasum -a 256 "$key_path.pub" | awk '{print $1}') || return 1
  expected_receipt=$(printf \
    'kind=slopnet-ssh-key-v1\nprivate_dev=%s\nprivate_ino=%s\npublic_dev=%s\npublic_ino=%s\nprivate_sha256=%s\npublic_sha256=%s\npublic_line=%s' \
    "$(local_dev "$key_path")" "$(local_ino "$key_path")" \
    "$(local_dev "$key_path.pub")" "$(local_ino "$key_path.pub")" \
    "$private_sha256" "$public_sha256" "$public_line")
  printf '%s\n' "$expected_receipt" | cmp -s - "$key_receipt_path" || return 1
  derived=$(ssh-keygen -y -P '' -f "$key_path" 2>/dev/null) || return 1
  # Compare the key material, not the whole line. ssh-keygen prints the
  # comment when the private key carries one and leaves it off when it does
  # not, so whole-line comparison fails on some machines and passes on others.
  # slopnet-vps-onboard.sh was fixed for this; removal was not, so on OpenSSH
  # 10 every uninstall decided SlopNet's own key was untrustworthy, refused to
  # use it, fell back to a password and could not take the key off the server.
  [ "$(printf '%s' "$public_line" | awk '{print $1" "$2}')" = \
    "$(printf '%s' "$derived" | awk '{print $1" "$2}')" ] || return 1
  validated_public_line=$public_line
}

validate_known_hosts() {
  local_uid=$(id -u)
  for protected in "$known_hosts_path" "$known_hosts_receipt_path"; do
    [ -f "$protected" ] && [ ! -L "$protected" ] || return 1
    [ "$(local_owner "$protected")" = "$local_uid" ] || return 1
    [ "$(local_mode "$protected")" = 600 ] || return 1
  done
  expected_receipt=$(printf \
    'kind=slopnet-known-hosts-v1\nknown_hosts_dev=%s\nknown_hosts_ino=%s' \
    "$(local_dev "$known_hosts_path")" "$(local_ino "$known_hosts_path")")
  printf '%s\n' "$expected_receipt" | cmp -s - "$known_hosts_receipt_path"
}

create_known_hosts() {
  hosts_tmp=$(mktemp "$ssh_dir/.slopnet-known-hosts.XXXXXX")
  receipt_tmp=$(mktemp "$ssh_dir/.slopnet-known-hosts-receipt.XXXXXX")
  cleanup_hosts() { rm -f "$hosts_tmp" "$receipt_tmp"; }
  trap cleanup_hosts EXIT HUP INT TERM
  chmod 600 "$hosts_tmp"
  ln "$hosts_tmp" "$known_hosts_path" || \
    local_refuse "$known_hosts_path appeared while its private file was being created."
  rm -f "$hosts_tmp"
  printf 'kind=slopnet-known-hosts-v1\nknown_hosts_dev=%s\nknown_hosts_ino=%s\n' \
    "$(local_dev "$known_hosts_path")" "$(local_ino "$known_hosts_path")" > "$receipt_tmp"
  chmod 600 "$receipt_tmp"
  ln "$receipt_tmp" "$known_hosts_receipt_path" || \
    local_refuse "$known_hosts_receipt_path appeared while it was being recorded."
  rm -f "$receipt_tmp"
  trap - EXIT HUP INT TERM
}

say "Removing SlopNet from your server"
say "This removes the private slopnet account and everything it downloaded, and the SlopNet folder. Other accounts, websites, databases and services on this server are not touched."
read -r -p "Remove it? [y/N] " answer
case "$(printf %s "$answer" | tr '[:upper:]' '[:lower:]')" in
  y|yes) ;;
  *) say "Nothing changed."; exit 3 ;;
esac

prepare_ssh_directory
key_proved=no
validated_public_line=""
if key_paths_complete && validate_key_pair; then
  key_proved=yes
elif ! key_paths_absent; then
  say "The same-named connection key does not match SlopNet's receipt. It will be left alone; archive it manually if you no longer need it."
fi
if ! known_hosts_paths_absent && ! known_hosts_paths_complete; then
  local_refuse "the dedicated known-hosts file and its receipt are not one complete proved set."
fi
if known_hosts_paths_complete; then
  validate_known_hosts || \
    local_refuse "the dedicated known-hosts file does not match its SlopNet receipt."
else
  create_known_hosts
  validate_known_hosts || local_refuse "the new dedicated known-hosts file failed its identity proof."
fi
public_key_b64=""
if [ "$key_proved" = yes ]; then
  public_key_b64=$(printf '%s' "$validated_public_line" | base64 | tr -d '\n')
fi

remote='set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
login_user=$1
public_key_b64=$2
refuse() {
  echo "RULE: $1"
  echo "WHY:  SlopNet deletes only the account and install its protected identity receipts prove it created."
  echo "FIX:  Inspect this server manually. No account or install folder was removed."
  exit 1
}
safe_marker() {
  marker=$1
  expected=$2
  [ -d /var/lib/slopnet ] && [ ! -L /var/lib/slopnet ] || return 1
  [ "$(stat -c %u /var/lib/slopnet)" = 0 ] || return 1
  [ -z "$(find /var/lib/slopnet -maxdepth 0 -perm /022 -print -quit)" ] || return 1
  [ -f "$marker" ] && [ ! -L "$marker" ] || return 1
  [ "$(stat -c %u "$marker")" = 0 ] || return 1
  [ -z "$(find "$marker" -maxdepth 0 -perm /022 -print -quit)" ] || return 1
  [ "$(cat "$marker")" = "$expected" ] || return 1
}
protected_marker() {
  marker=$1
  [ -d /var/lib/slopnet ] && [ ! -L /var/lib/slopnet ] || return 1
  [ "$(stat -c %u /var/lib/slopnet)" = 0 ] || return 1
  [ -z "$(find /var/lib/slopnet -maxdepth 0 -perm /022 -print -quit)" ] || return 1
  [ -f "$marker" ] && [ ! -L "$marker" ] || return 1
  [ "$(stat -c %u "$marker")" = 0 ] || return 1
  [ -z "$(find "$marker" -maxdepth 0 -perm /022 -print -quit)" ] || return 1
}
runtime_receipt() {
  uid=$(id -u slopnet 2>/dev/null) || return 1
  gid=$(id -g slopnet 2>/dev/null) || return 1
  home=$(getent passwd slopnet | cut -d: -f6)
  shell=$(getent passwd slopnet | cut -d: -f7)
  [ "$uid" -ne 0 ] && [ "$home" = /home/slopnet ] && \
    [ "$shell" = /usr/sbin/nologin ] || return 1
  [ -d "$home" ] && [ ! -L "$home" ] && [ "$(stat -c %u "$home")" = "$uid" ] || return 1
  [ "$(stat -c %a "$home")" = 700 ] && [ "$(getent group "$gid" | cut -d: -f1)" = slopnet ] || return 1
  [ "$(id -G slopnet)" = "$gid" ] || return 1
  password_state=$(passwd -S slopnet 2>/dev/null | awk "{print \$2}")
  [ "$password_state" = L ] || [ "$password_state" = LK ] || return 1
  printf "kind=runtime-account-v2\nname=slopnet\nuid=%s\ngid=%s\nhome=/home/slopnet\nshell=/usr/sbin/nologin\nhome_dev=%s\nhome_ino=%s" \
    "$uid" "$gid" "$(stat -c %d "$home")" "$(stat -c %i "$home")"
}
install_receipt() {
  recorded_release=$1
  recorded_commit=$2
  [ -d /opt/slopnet ] && [ ! -L /opt/slopnet ] && [ "$(stat -c %u /opt/slopnet)" = 0 ] || return 1
  [ -z "$(find /opt/slopnet -maxdepth 0 -perm /022 -print -quit)" ] || return 1
  [ "$(git -C /opt/slopnet remote get-url origin)" = https://github.com/jpheerlyn-dev/slopnet.git ] || return 1
  [ "$(git -C /opt/slopnet rev-parse HEAD)" = "$recorded_commit" ] || return 1
  [ "$(git -C /opt/slopnet rev-parse "refs/tags/$recorded_release^{commit}")" = "$recorded_commit" ] || return 1
  git -C /opt/slopnet diff --quiet --exit-code || return 1
  [ -z "$(git -C /opt/slopnet status --porcelain --untracked-files=all)" ] || return 1
  printf "kind=install-v2\npath=/opt/slopnet\ndev=%s\nino=%s\nrelease=%s\ncommit=%s" \
    "$(stat -c %d /opt/slopnet)" "$(stat -c %i /opt/slopnet)" \
    "$recorded_release" "$recorded_commit"
}

[ "$(uname -s)" = Linux ] || refuse "Server removal currently supports Linux only."
[ "$(id -u)" = 0 ] || refuse "Server removal did not receive root privilege."
managed_proved=no
if id -u slopnet >/dev/null 2>&1; then
  expected_account=$(runtime_receipt) || refuse "The slopnet account is no longer a locked private runtime identity."
  safe_marker /var/lib/slopnet/runtime-account-v2 "$expected_account" || \
    refuse "The slopnet account does not match its protected ownership receipt."
  managed_proved=yes
elif [ -e /var/lib/slopnet/runtime-account-v2 ] || [ -L /var/lib/slopnet/runtime-account-v2 ]; then
  refuse "A runtime-account receipt remains but its exact account is absent."
fi
if [ -e /opt/slopnet ] || [ -L /opt/slopnet ]; then
  protected_marker /var/lib/slopnet/install-v2 || refuse "/opt/slopnet has no protected ownership receipt."
  recorded_release=$(sed -n "s/^release=//p" /var/lib/slopnet/install-v2)
  recorded_commit=$(sed -n "s/^commit=//p" /var/lib/slopnet/install-v2)
  printf "%s" "$recorded_release" | grep -Eq "^v[0-9]+\.[0-9]+\.[0-9]+$" || refuse "The install receipt has an invalid release."
  printf "%s" "$recorded_commit" | grep -Eq "^[0-9a-f]{40,64}$" || refuse "The install receipt has an invalid commit."
  expected_install=$(install_receipt "$recorded_release" "$recorded_commit") || \
    refuse "/opt/slopnet no longer matches its protected release identity."
  safe_marker /var/lib/slopnet/install-v2 "$expected_install" || \
    refuse "/opt/slopnet does not match its protected ownership receipt."
  safe_marker /var/lib/slopnet/release-v1 "release=$recorded_release" || \
    refuse "The release marker no longer matches the protected install."
  if [ -e /var/lib/slopnet/approved-build-v1 ] || \
     [ -L /var/lib/slopnet/approved-build-v1 ]; then
    approved_build=$(printf "kind=approved-build-v1\nrelease=%s\ncommit=%s" \
      "$recorded_release" "$recorded_commit")
    safe_marker /var/lib/slopnet/approved-build-v1 "$approved_build" || \
      refuse "The approved-build marker does not match the current protected install."
  fi
  managed_proved=yes
elif [ -e /var/lib/slopnet/install-v2 ] || [ -L /var/lib/slopnet/install-v2 ] || \
     [ -e /var/lib/slopnet/release-v1 ] || [ -L /var/lib/slopnet/release-v1 ] || \
     [ -e /var/lib/slopnet/approved-build-v1 ] || \
     [ -L /var/lib/slopnet/approved-build-v1 ]; then
  refuse "An install receipt remains but its exact install is absent."
fi
if [ "$managed_proved" = yes ]; then
  unknown=$(find /var/lib/slopnet -mindepth 1 -maxdepth 1 \
    ! -name runtime-account-v2 ! -name install-v2 ! -name release-v1 \
    ! -name approved-build-v1 \
    -print -quit)
  [ -z "$unknown" ] || refuse "The management folder contains an unknown file."
fi

if id -u slopnet >/dev/null 2>&1; then
  pkill -u slopnet 2>/dev/null || true
  sleep 1
  if ! userdel -r slopnet; then
    refuse "The managed runtime account could not be removed cleanly."
  fi
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
# Upgrades keep old managed code root-only for recovery. Each archive carries
# its own exact root-owned marker; a same-named folder without that receipt is
# unrelated data and is left alone.
find /opt -maxdepth 1 -type d -name "slopnet.archive.*" -print | \
while IFS= read -r archive; do
  case "$archive" in
    /opt/slopnet.archive.*) ;;
    *) continue ;;
  esac
  archive_marker="$archive/.slopnet-archive-v1"
  [ -d "$archive" ] && [ ! -L "$archive" ] && \
    [ "$(stat -c %u "$archive")" = 0 ] && \
    [ -z "$(find "$archive" -maxdepth 0 -perm /022 -print -quit)" ] && \
    [ -f "$archive_marker" ] && [ ! -L "$archive_marker" ] && \
    [ "$(stat -c %u "$archive_marker")" = 0 ] && \
    [ -z "$(find "$archive_marker" -maxdepth 0 -perm /022 -print -quit)" ] && \
    [ "$(cat "$archive_marker")" = "archive=$archive" ] || continue
  rm -rf -- "$archive"
  echo "[OK] removed a protected SlopNet recovery copy"
done
if [ "$managed_proved" = yes ]; then
  # The protected parent cannot be renamed by the runtime account. Refuse an
  # unknown entry instead of deleting or adopting unrelated state.
  rm -f -- /var/lib/slopnet/runtime-account-v2 /var/lib/slopnet/install-v2 \
    /var/lib/slopnet/release-v1 /var/lib/slopnet/approved-build-v1
  rmdir /var/lib/slopnet 2>/dev/null || true
fi
login_home=$(getent passwd "$login_user" | cut -d: -f6)
login_uid=$(id -u "$login_user" 2>/dev/null || true)
login_ssh_dir="$login_home/.ssh"
keys="$login_home/.ssh/authorized_keys"
public_key=""
if [ -n "$public_key_b64" ]; then
  public_key=$(printf "%s" "$public_key_b64" | base64 -d)
fi
if [ -n "$public_key" ]; then
  printf "%s\n" "$public_key" | grep -Eq "^ssh-ed25519 [A-Za-z0-9+/]+={0,2} slopnet-vps$" || \
    refuse "The supplied dedicated public key is not one exact Ed25519 line."
fi
if [ -n "$login_home" ] && [ -n "$login_uid" ] && [ -n "$public_key" ] && \
   [ -d "$login_ssh_dir" ] && [ ! -L "$login_ssh_dir" ] && \
   [ "$(stat -c %u "$login_ssh_dir")" = "$login_uid" ] && \
   [ -f "$keys" ] && [ ! -L "$keys" ] && \
   [ "$(stat -c %u "$keys")" = "$login_uid" ] && \
   grep -qxF -- "$public_key" "$keys"; then
  if runuser -u "$login_user" -- env SSH_DIR="$login_ssh_dir" KEYS="$keys" \
      PUBLIC_KEY="$public_key" sh -c "
set -eu
[ -d \"\$SSH_DIR\" ] && [ ! -L \"\$SSH_DIR\" ] && \
  [ \"\$(stat -c %u \"\$SSH_DIR\")\" = \"\$(id -u)\" ] || exit 1
[ -f \"\$KEYS\" ] && [ ! -L \"\$KEYS\" ] && \
  [ \"\$(stat -c %u \"\$KEYS\")\" = \"\$(id -u)\" ] || exit 1
temporary=\$(mktemp \"\${KEYS}.XXXXXX\")
cleanup_key() { rm -f -- \"\$temporary\"; }
trap cleanup_key EXIT HUP INT TERM
grep -vxF -- \"\$PUBLIC_KEY\" \"\$KEYS\" > \"\$temporary\" || true
chmod --reference=\"\$KEYS\" \"\$temporary\"
mv -f -- \"\$temporary\" \"\$KEYS\"
trap - EXIT HUP INT TERM
"; then
    echo "[OK] removed the SlopNet key from this account"
  else
    echo "[NOTE] the dedicated key could not be removed safely; remove its exact line manually"
  fi
fi
echo "[OK] every other account, service and file on this server was left alone"'
encoded=$(printf '%s' "$remote" | base64 | tr -d '\n')

# The key may already be gone; fall back to a password login so uninstalling
# still works after a partial removal.
ssh_opts=(-o "UserKnownHostsFile=$known_hosts_path" -o LogLevel=ERROR \
  -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -tt -p "$port")
if [ "$key_proved" = yes ]; then
  ssh_opts+=(-i "$key_path")
else
  ssh_opts+=(-o PubkeyAuthentication=no)
fi

if [ "$username" = "root" ]; then
  /usr/bin/ssh "${ssh_opts[@]}" "$username@$host" "/bin/sh -c 'set -eu; umask 077; f=\$(/usr/bin/mktemp /tmp/slopnet-XXXXXXXX); cleanup_payload() { /bin/rm -f -- \"\$f\"; }; trap cleanup_payload EXIT HUP INT TERM; /usr/bin/printf \"%s\" \"\$1\" | /usr/bin/base64 -d > \"\$f\"; /bin/chmod 600 \"\$f\"; /bin/sh \"\$f\" \"\$2\" \"\$3\" </dev/tty' slopnet-payload '$encoded' '$username' '$public_key_b64'"
else
  /usr/bin/ssh "${ssh_opts[@]}" "$username@$host" "/usr/bin/sudo /bin/sh -c 'set -eu; umask 077; f=\$(/usr/bin/mktemp /tmp/slopnet-XXXXXXXX); cleanup_payload() { /bin/rm -f -- \"\$f\"; }; trap cleanup_payload EXIT HUP INT TERM; /usr/bin/printf \"%s\" \"\$1\" | /usr/bin/base64 -d > \"\$f\"; /bin/chmod 600 \"\$f\"; /bin/sh \"\$f\" \"\$2\" \"\$3\" </dev/tty' slopnet-payload '$encoded' '$username' '$public_key_b64'"
fi

if [ "$key_proved" = yes ] && validate_key_pair; then
  rm -f "$key_path" "$key_path.pub" "$key_receipt_path"
  say "The proved SlopNet connection key was removed from this Mac."
elif ! key_paths_absent; then
  say "The same-named local key was left alone because its SlopNet proof did not match."
fi
if validate_known_hosts; then
  rm -f "$known_hosts_path" "$known_hosts_receipt_path"
  say "SlopNet's proved server-fingerprint file was removed from this Mac."
else
  say "The same-named server-fingerprint file was left alone because its proof changed."
fi

say "SlopNet has been removed from your server."
