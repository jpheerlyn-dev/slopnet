#!/usr/bin/env bash
# The interactive half of the Mac app's first server connection.
# Password prompts stay inside macOS OpenSSH; this script never receives or
# stores a server password.
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  printf '%s\n' 'Usage: slopnet-vps-onboard.sh HOST PORT USER [SERVER_NAME]' >&2
  exit 2
fi

host="$1"
port="$2"
username="$3"
server_name="${4:-your server}"
# The exact SlopNet release this installer puts on a server. Setup runs
# that code as root, so it is pinned rather than following whatever the
# default branch holds today. Bump it when a release is cut and proved.
slopnet_release="v0.9.62"
# Filled with the verified tag commit when build_app.sh copies this helper
# into SlopNet.app. Keeping the source empty prevents a mutable tag name from
# being the only authority for code that will run as root.
slopnet_commit=""
ssh_dir="$HOME/.ssh"
key_path="$ssh_dir/slopnet_vps_ed25519"
key_receipt_path="$key_path.receipt"
known_hosts_path="$ssh_dir/slopnet_vps_known_hosts"
known_hosts_receipt_path="$known_hosts_path.receipt"
repo_url="https://github.com/jpheerlyn-dev/slopnet.git"

if ! [[ "$slopnet_release" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf '%s\n' 'This copy of SlopNet has an invalid server release pin. Download it again.' >&2
  exit 1
fi
if ! [[ "$slopnet_commit" =~ ^[0-9a-f]{40,64}$ ]]; then
  printf '%s\n' 'This installer has no verified server commit. Build SlopNet from its signed release tag again.' >&2
  exit 1
fi

say() {
  printf '\n%s\n' "$1"
}

local_refuse() {
  printf '%s\n' "SlopNet will not use the dedicated SSH files: $1" >&2
  printf '%s\n' \
    "Archive the named .ssh collision yourself, then start server setup again." >&2
  exit 1
}

# These helpers run on the Mac. BSD stat is standard there; the GNU spelling
# keeps the failure probes useful on another Unix without weakening the check.
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
  # It failed here, on every run after the first, which left setup unable to
  # accept a key SlopNet had generated itself.
  [ "$(printf '%s' "$public_line" | awk '{print $1" "$2}')" = \
    "$(printf '%s' "$derived" | awk '{print $1" "$2}')" ] || return 1
  validated_public_line=$public_line
}

write_key_receipt() {
  private_sha256=$(shasum -a 256 "$key_path" | awk '{print $1}')
  public_sha256=$(shasum -a 256 "$key_path.pub" | awk '{print $1}')
  public_line=$(sed -n '1p' "$key_path.pub")
  receipt_tmp=$(mktemp "$ssh_dir/.slopnet-key-receipt.XXXXXX")
  cleanup_receipt() { rm -f "$receipt_tmp"; }
  trap cleanup_receipt EXIT HUP INT TERM
  printf \
    'kind=slopnet-ssh-key-v1\nprivate_dev=%s\nprivate_ino=%s\npublic_dev=%s\npublic_ino=%s\nprivate_sha256=%s\npublic_sha256=%s\npublic_line=%s\n' \
    "$(local_dev "$key_path")" "$(local_ino "$key_path")" \
    "$(local_dev "$key_path.pub")" "$(local_ino "$key_path.pub")" \
    "$private_sha256" "$public_sha256" "$public_line" > "$receipt_tmp"
  chmod 600 "$receipt_tmp"
  ln "$receipt_tmp" "$key_receipt_path" || \
    local_refuse "$key_receipt_path appeared while the new key was being recorded."
  rm -f "$receipt_tmp"
  trap - EXIT HUP INT TERM
}

# Take on a key that SlopNet itself made before receipts existed.
#
# Every installation from before this release has a private key and a public
# key and no receipt, so the completeness check refuses and setup cannot run at
# all. Telling somebody to archive their own .ssh files by hand is exactly the
# work this app exists to remove, and it left a working installation unusable.
#
# Nothing is taken on trust. The pair has to be two ordinary files this user
# owns, the public one has to be a single line in the shape SlopNet writes, and
# the public key has to be the one this private key derives. That is the same
# proof the receipt records when a key is generated here — it is only being
# done after the fact.
adopt_key_pair() {
  local_uid=$(id -u)
  for protected in "$key_path" "$key_path.pub"; do
    [ -f "$protected" ] && [ ! -L "$protected" ] || return 1
    [ "$(local_owner "$protected")" = "$local_uid" ] || return 1
  done
  [ "$(wc -l < "$key_path.pub" | tr -d ' ')" = 1 ] || return 1
  public_line=$(sed -n '1p' "$key_path.pub")
  case "$public_line" in
    ssh-ed25519\ *\ slopnet-vps) ;;
    *) return 1 ;;
  esac
  derived=$(ssh-keygen -y -P '' -f "$key_path" 2>/dev/null) || return 1
  # Compare the key material, not the whole line. ssh-keygen prints the
  # comment when the private key carries one and leaves it off when it does
  # not, so whole-line comparison fails on some machines and passes on others.
  # It failed here, on every run after the first, which left setup unable to
  # accept a key SlopNet had generated itself.
  [ "$(printf '%s' "$public_line" | awk '{print $1" "$2}')" = \
    "$(printf '%s' "$derived" | awk '{print $1" "$2}')" ] || return 1
  chmod 600 "$key_path" "$key_path.pub" || return 1
  write_key_receipt
  validated_public_line=$public_line
}

# The same, for the dedicated known-hosts file. Adopting it keeps the server
# fingerprints already trusted, so nobody is asked to confirm a host they
# accepted months ago.
adopt_known_hosts() {
  local_uid=$(id -u)
  [ -f "$known_hosts_path" ] && [ ! -L "$known_hosts_path" ] || return 1
  [ "$(local_owner "$known_hosts_path")" = "$local_uid" ] || return 1
  chmod 600 "$known_hosts_path" || return 1
  receipt_tmp=$(mktemp "$ssh_dir/.slopnet-known-hosts-receipt.XXXXXX")
  cleanup_adopted() { rm -f "$receipt_tmp"; }
  trap cleanup_adopted EXIT HUP INT TERM
  printf 'kind=slopnet-known-hosts-v1\nknown_hosts_dev=%s\nknown_hosts_ino=%s\n' \
    "$(local_dev "$known_hosts_path")" "$(local_ino "$known_hosts_path")" > "$receipt_tmp"
  chmod 600 "$receipt_tmp"
  ln "$receipt_tmp" "$known_hosts_receipt_path" || \
    local_refuse "$known_hosts_receipt_path appeared while it was being recorded."
  rm -f "$receipt_tmp"
  trap - EXIT HUP INT TERM
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

clear
printf '\033]0;SlopNet Server setup\007'
say "SlopNet Server setup"
say "You are setting up a protected connection between this Mac and your server. SlopNet will never save your server password."

prepare_ssh_directory
# A key from before receipts existed is taken on rather than refused, once it
# has been proved. Only a pair that cannot be proved stops setup, and then the
# message names the files rather than leaving somebody to guess.
if ! key_paths_absent && ! key_paths_complete; then
  if local_exists "$key_path" && local_exists "$key_path.pub" && \
     ! local_exists "$key_receipt_path" && adopt_key_pair; then
    say "Recorded the connection key this Mac already had, after checking the pair matches."
  else
    local_refuse "the private key, public key and key receipt are not one complete proved set: $key_path, $key_path.pub, $key_receipt_path."
  fi
fi
if ! known_hosts_paths_absent && ! known_hosts_paths_complete; then
  if local_exists "$known_hosts_path" && ! local_exists "$known_hosts_receipt_path" && \
     adopt_known_hosts; then
    say "Recorded the server fingerprints this Mac already trusted."
  else
    local_refuse "the dedicated known-hosts file and its receipt are not one complete proved set: $known_hosts_path, $known_hosts_receipt_path."
  fi
fi
if key_paths_complete && ! validate_key_pair; then
  local_refuse "the existing key files do not match their SlopNet receipt."
fi
if known_hosts_paths_complete && ! validate_known_hosts; then
  local_refuse "the dedicated known-hosts file does not match its SlopNet receipt."
fi
if key_paths_absent; then
  say "Step 1 of 3 — making a key for this connection"
  say "SlopNet is creating a key so this Mac can reach your server without a password every time. It is kept in your own .ssh folder, readable only by you."
  # No passphrase, deliberately. A passphrase here bought one more secret to
  # remember and three extra prompts, and it was cached in the login keychain
  # immediately afterwards anyway — so it protected nothing that the file
  # permissions and FileVault do not already protect. The key reaches exactly
  # one server, the one the person is setting up.
  ssh-keygen -q -t ed25519 -N "" -f "$key_path" -C "slopnet-vps"
  chmod 600 "$key_path" "$key_path.pub"
  write_key_receipt
  validate_key_pair || local_refuse "the newly generated key failed its identity proof."
fi
if known_hosts_paths_absent; then
  create_known_hosts
  validate_known_hosts || local_refuse "the new dedicated known-hosts file failed its identity proof."
fi


say "Step 2 of 3 — confirm your server"
say "Connecting to ${server_name}. Enter the server password if asked. It is not saved."
remote_authorize='set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
key=$(/bin/cat)
/usr/bin/printf "%s\n" "$key" | /usr/bin/grep -Eq "^ssh-ed25519 [A-Za-z0-9+/]+={0,2} slopnet-vps$" || exit 1
uid=$(/usr/bin/id -u)
ssh_dir=$HOME/.ssh
if [ -e "$ssh_dir" ] || [ -L "$ssh_dir" ]; then
  [ -d "$ssh_dir" ] && [ ! -L "$ssh_dir" ] && [ "$(/usr/bin/stat -c %u "$ssh_dir")" = "$uid" ] || exit 1
else
  umask 077
  /bin/mkdir -- "$ssh_dir"
fi
/bin/chmod 700 -- "$ssh_dir"
keys=$ssh_dir/authorized_keys
if [ -e "$keys" ] || [ -L "$keys" ]; then
  [ -f "$keys" ] && [ ! -L "$keys" ] && [ "$(/usr/bin/stat -c %u "$keys")" = "$uid" ] || exit 1
fi
temporary=$(/usr/bin/mktemp "$ssh_dir/.authorized_keys.XXXXXX")
cleanup_key() { /bin/rm -f -- "$temporary"; }
trap cleanup_key EXIT HUP INT TERM
if [ -f "$keys" ]; then /bin/cat -- "$keys" > "$temporary"; fi
if ! /usr/bin/grep -qxF -- "$key" "$temporary"; then
  if [ -s "$temporary" ]; then /usr/bin/printf "\n" >> "$temporary"; fi
  /usr/bin/printf "%s\n" "$key" >> "$temporary"
fi
/bin/chmod 600 -- "$temporary"
/bin/mv -f -- "$temporary" "$keys"
trap - EXIT HUP INT TERM'
/usr/bin/printf '%s\n' "$validated_public_line" | /usr/bin/ssh \
  -o "UserKnownHostsFile=$known_hosts_path" \
  -o LogLevel=ERROR -o StrictHostKeyChecking=accept-new \
  -o IdentitiesOnly=yes -i "$key_path" -p "$port" "$username@$host" \
  "$remote_authorize"

validate_key_pair || local_refuse "the dedicated key changed during server confirmation."
validate_known_hosts || local_refuse "the dedicated known-hosts file changed identity during server confirmation."
/usr/bin/ssh -o "UserKnownHostsFile=$known_hosts_path" \
  -o LogLevel=ERROR -o StrictHostKeyChecking=accept-new \
  -o IdentitiesOnly=yes -i "$key_path" -p "$port" "$username@$host" /usr/bin/true

say "Your protected connection is ready."
say "Step 3 of 3 — prepare the server"
# Everything that changes, said once, here — the only place in this flow with
# a terminal the person actually opened. Setup used to repeat six variations
# of this question over the SSH connection, where an unanswered one stops the
# run with nothing on screen.
say "This is everything SlopNet changes on your server:"
printf '%s\n' \
  "  - creates a locked account called slopnet, with a private home folder" \
  "  - installs protected SlopNet code into /opt/slopnet; only root can change it" \
  "  - installs bubblewrap, so coding agents run boxed in rather than loose" \
  "" \
  "It does not touch root SSH access, password SSH access, firewall rules or ports." \
  "It does not install a coding app, sign you in to anything, or download the guide yet."
say "If you did not sign in as root, your server may ask for your sudo password now."
read -r -p "Make those changes? [y/N] " ready
case "$(printf %s "$ready" | tr "[:upper:]" "[:lower:]")" in
  y|yes) ;;
  *) say "Nothing changed on your server."; exit 3 ;;
esac

remote_setup='set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
slopnet_release=$1
pinned_commit=$2
expected_repo=https://github.com/jpheerlyn-dev/slopnet.git
managed=/var/lib/slopnet
account_marker=$managed/runtime-account-v2
install_marker=$managed/install-v2
release_marker=$managed/release-v1
approved_marker=$managed/approved-build-v1
expected_release="release=$slopnet_release"
had_previous=no
had_previous_approved=no
previous_install_receipt=
previous_release=

printf "%s" "$slopnet_release" | grep -Eq "^v[0-9]+\.[0-9]+\.[0-9]+$" || exit 1
printf "%s" "$pinned_commit" | grep -Eq "^[0-9a-f]{40,64}$" || exit 1

refuse() {
  echo "RULE: $1"
  echo "WHY:  SlopNet will not adopt, execute or later delete server data it did not prove it created."
  echo "FIX:  Archive the name collision yourself, then start server setup again. Nothing was changed."
  exit 1
}
safe_marker() {
  marker=$1
  expected=$2
  [ -f "$marker" ] || return 1
  [ ! -L "$marker" ] || return 1
  [ "$(stat -c %u "$marker")" = 0 ] || return 1
  [ -z "$(find "$marker" -maxdepth 0 -perm /022 -print -quit)" ] || return 1
  [ "$(cat "$marker")" = "$expected" ] || return 1
}
runtime_receipt() {
  uid=$(id -u slopnet 2>/dev/null) || return 1
  gid=$(id -g slopnet 2>/dev/null) || return 1
  home=$(getent passwd slopnet | cut -d: -f6)
  shell=$(getent passwd slopnet | cut -d: -f7)
  [ "$uid" -ne 0 ] && [ "$home" = /home/slopnet ] && \
    [ "$shell" = /usr/sbin/nologin ] || return 1
  [ -d "$home" ] && [ ! -L "$home" ] || return 1
  [ "$(stat -c %u "$home")" = "$uid" ] && [ "$(stat -c %a "$home")" = 700 ] || return 1
  [ "$(getent group "$gid" | cut -d: -f1)" = slopnet ] || return 1
  groups=$(id -G slopnet) || return 1
  [ "$groups" = "$gid" ] || return 1
  password_state=$(passwd -S slopnet 2>/dev/null | awk "{print \$2}")
  [ "$password_state" = L ] || [ "$password_state" = LK ] || return 1
  printf "kind=runtime-account-v2\nname=slopnet\nuid=%s\ngid=%s\nhome=/home/slopnet\nshell=/usr/sbin/nologin\nhome_dev=%s\nhome_ino=%s" \
    "$uid" "$gid" "$(stat -c %d "$home")" "$(stat -c %i "$home")"
}
install_receipt() {
  recorded_release=$1
  recorded_commit=$2
  [ -d /opt/slopnet ] && [ ! -L /opt/slopnet ] || return 1
  [ "$(stat -c %u /opt/slopnet)" = 0 ] || return 1
  [ -z "$(find /opt/slopnet -maxdepth 0 -perm /022 -print -quit)" ] || return 1
  [ "$(git -C /opt/slopnet remote get-url origin)" = "$expected_repo" ] || return 1
  [ "$(git -C /opt/slopnet rev-parse HEAD)" = "$recorded_commit" ] || return 1
  [ "$(git -C /opt/slopnet rev-parse "refs/tags/$recorded_release^{commit}")" = "$recorded_commit" ] || return 1
  git -C /opt/slopnet diff --quiet --exit-code || return 1
  [ -z "$(git -C /opt/slopnet status --porcelain --untracked-files=all)" ] || return 1
  printf "kind=install-v2\npath=/opt/slopnet\ndev=%s\nino=%s\nrelease=%s\ncommit=%s" \
    "$(stat -c %d /opt/slopnet)" "$(stat -c %i /opt/slopnet)" \
    "$recorded_release" "$recorded_commit"
}

[ "$(uname -s)" = Linux ] || refuse "Server setup currently supports Linux only."
[ "$(id -u)" = 0 ] || refuse "The protected server setup is not running as root."
if ! command -v git >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y git
  else
    echo "Git is missing and this server has no supported automatic installer. Install git, then start SlopNet again."
    exit 1
  fi
fi
for needed in stat find getent runuser install mktemp passwd awk; do
  command -v "$needed" >/dev/null 2>&1 || refuse "The Linux $needed command is missing."
done
# An installation made before the v2 receipts existed.
#
# Those servers carry runtime-account-v1 and install-v1, a runtime account with
# a login shell, and an install owned by that account. Every later check refuses
# all three, so a working installation became unusable and the only advice was
# to archive it by hand. The v1 receipts are themselves the proof that SlopNet
# made what is there — nothing else can write a root-owned file in this folder —
# so they are enough to justify upgrading it in place rather than refusing it.
#
# The v1 receipts are consumed by the upgrade. If it is interrupted after that,
# the v2 receipts written below are what the next run reads, and if it is
# interrupted before, nothing has changed.
upgrade_from_v1() {
  for legacy in "$managed/runtime-account-v1" "$managed/install-v1"; do
    [ -f "$legacy" ] && [ ! -L "$legacy" ] || return 1
    [ "$(stat -c %u "$legacy")" = 0 ] || return 1
    [ -z "$(find "$legacy" -maxdepth 0 -perm /022 -print -quit)" ] || return 1
  done
  id -u slopnet >/dev/null 2>&1 || return 1
  [ "$(getent passwd slopnet | cut -d: -f6)" = /home/slopnet ] || return 1
  [ -d /opt/slopnet ] && [ ! -L /opt/slopnet ] || return 1

  # The account must not be able to log in, and the install must belong to
  # root, which is what the v2 receipts record and every later check requires.
  usermod -s /usr/sbin/nologin slopnet || return 1
  chown -R 0:0 /opt/slopnet || return 1
  chmod go-w /opt/slopnet || return 1
  # Record the account in the current format straight away. Clearing the old
  # receipts without writing the new one leaves the account unmarked, which the
  # very next check refuses — the upgrade has to finish what it started.
  upgraded_account=$(runtime_receipt) || return 1
  account_tmp=$(mktemp "$managed/.account.XXXXXX") || return 1
  printf "%s" "$upgraded_account" > "$account_tmp" || return 1
  chmod 600 "$account_tmp" || return 1
  mv -f "$account_tmp" "$account_marker" || return 1
  rm -f "$managed/runtime-account-v1" "$managed/install-v1" || return 1
  echo "Upgraded the SlopNet records on this server to the current format."
}

if [ -d "$managed" ] && [ ! -L "$managed" ] && [ "$(stat -c %u "$managed")" = 0 ] && \
   { [ -e "$managed/runtime-account-v1" ] || [ -e "$managed/install-v1" ]; }; then
  upgrade_from_v1 || refuse "The older SlopNet records on this server could not be upgraded."
fi

if [ -e "$managed" ] || [ -L "$managed" ]; then
  [ -d "$managed" ] && [ ! -L "$managed" ] && \
    [ "$(stat -c %u "$managed")" = 0 ] && \
    [ -z "$(find "$managed" -maxdepth 0 -perm /022 -print -quit)" ] || \
    refuse "The SlopNet management folder is not a protected root-owned directory."
  unknown=$(find "$managed" -mindepth 1 -maxdepth 1 \
    ! -name runtime-account-v2 ! -name install-v2 ! -name release-v1 \
    ! -name approved-build-v1 \
    -print -quit)
  [ -z "$unknown" ] || \
    refuse "The SlopNet management folder contains an unknown or legacy receipt."
fi

# A common account name is not ownership. A pre-existing `slopnet` user might
# hold another person’s files; without the root-owned marker made when SlopNet
# created it, setup stops before chmod, chown or provider credentials.
if id -u slopnet >/dev/null 2>&1; then
  expected_account=$(runtime_receipt) || \
    refuse "The existing slopnet account is not locked to its private home and group."
  safe_marker "$account_marker" "$expected_account" || \
    refuse "An unmarked slopnet account already exists."
elif [ -e "$account_marker" ] || [ -L "$account_marker" ]; then
  refuse "A stale SlopNet account marker exists without its account."
elif [ -e /home/slopnet ] || [ -L /home/slopnet ]; then
  refuse "The slopnet account is absent but /home/slopnet already belongs to something else."
fi

if [ -e /opt/slopnet ] || [ -L /opt/slopnet ]; then
  [ -f "$install_marker" ] && [ ! -L "$install_marker" ] || \
    refuse "An unmarked /opt/slopnet folder already exists."
  recorded_release=$(sed -n "s/^release=//p" "$install_marker")
  recorded_commit=$(sed -n "s/^commit=//p" "$install_marker")
  printf "%s" "$recorded_release" | grep -Eq "^v[0-9]+\.[0-9]+\.[0-9]+$" || \
    refuse "The SlopNet install receipt has an invalid release."
  printf "%s" "$recorded_commit" | grep -Eq "^[0-9a-f]{40,64}$" || \
    refuse "The SlopNet install receipt has an invalid commit."
  expected_install=$(install_receipt "$recorded_release" "$recorded_commit") || \
    refuse "The existing /opt/slopnet folder no longer matches its release receipt."
  safe_marker "$install_marker" "$expected_install" || \
    refuse "An unmarked /opt/slopnet folder already exists."
  safe_marker "$release_marker" "release=$recorded_release" || \
    refuse "The existing SlopNet release marker does not match its install receipt."
  if [ -e "$approved_marker" ] || [ -L "$approved_marker" ]; then
    previous_approved_receipt=$(printf \
      "kind=approved-build-v1\nrelease=%s\ncommit=%s" \
      "$recorded_release" "$recorded_commit")
    safe_marker "$approved_marker" "$previous_approved_receipt" || \
      refuse "The approved-build marker does not match the current protected install."
    had_previous_approved=yes
  fi
  had_previous=yes
  previous_install_receipt=$expected_install
  previous_release=$recorded_release
elif [ -e "$install_marker" ] || [ -L "$install_marker" ]; then
  refuse "A stale SlopNet install marker exists without its folder."
elif [ -e "$release_marker" ] || [ -L "$release_marker" ]; then
  refuse "A stale SlopNet release marker exists without its install."
elif [ -e "$approved_marker" ] || [ -L "$approved_marker" ]; then
  refuse "A stale approved-build marker exists without its install."
fi

# Never fetch or run as root from a checkout writable by the runtime account.
# A complete fresh clone is checked out at the pinned tag, made root-owned,
# and only then moved into place. A previous managed copy is archived rather
# than reused; local changes therefore cannot ride into root setup.
fresh=$(mktemp -d /opt/slopnet.new.XXXXXX)
archive=""
published=no
cleanup_install() {
  set +e
  if [ "$published" = yes ] && [ -d /opt/slopnet ] && [ ! -L /opt/slopnet ]; then
    rm -rf -- /opt/slopnet
  fi
  if [ "$had_previous_approved" = yes ] && [ -n "$archive" ] && \
     [ -f "$archive/.slopnet-approved-build-v1" ] && \
     [ ! -L "$archive/.slopnet-approved-build-v1" ] && \
     [ ! -e "$approved_marker" ] && [ ! -L "$approved_marker" ]; then
    mv "$archive/.slopnet-approved-build-v1" "$approved_marker"
  fi
  if [ -n "$archive" ] && [ ! -e /opt/slopnet ] && [ -d "$archive" ] && [ ! -L "$archive" ]; then
    mv "$archive" /opt/slopnet
  fi
  if [ -d "$managed" ] && [ ! -L "$managed" ] && [ "$(stat -c %u "$managed")" = 0 ]; then
    if [ "$had_previous" = yes ]; then
      restore_install=$(mktemp "$managed/.install-v2.rollback.XXXXXX")
      printf "%s\n" "$previous_install_receipt" > "$restore_install"
      chmod 0644 "$restore_install"
      chown root:root "$restore_install"
      mv "$restore_install" "$install_marker"
      restore_release=$(mktemp "$managed/.release-v1.rollback.XXXXXX")
      printf "release=%s\n" "$previous_release" > "$restore_release"
      chmod 0644 "$restore_release"
      chown root:root "$restore_release"
      mv "$restore_release" "$release_marker"
    else
      rm -f -- "$install_marker" "$release_marker"
    fi
  fi
  rm -rf -- "$fresh"
}
trap '"'"'cleanup_install'"'"' EXIT HUP INT TERM
git clone --quiet --no-checkout "$expected_repo" "$fresh/repo"
[ "$(git -C "$fresh/repo" remote get-url origin)" = "$expected_repo" ] || \
  refuse "The downloaded SlopNet checkout has the wrong origin."
if ! checkout_error=$(git -C "$fresh/repo" -c advice.detachedHead=false \
    checkout --quiet --detach "refs/tags/$slopnet_release" 2>&1); then
  echo "RULE: SlopNet could not check out its released version ($slopnet_release)."
  echo "WHY:  Setup runs this code as root, so it will not fall back to whatever the branch currently holds."
  echo "FIX:  Read the git error below, fix what it names, then start setup again. Nothing was installed."
  echo "$checkout_error"
  exit 1
fi
[ "$(git -C "$fresh/repo" rev-parse HEAD)" = "$pinned_commit" ] && \
  [ "$(git -C "$fresh/repo" rev-parse "refs/tags/$slopnet_release^{commit}")" = "$pinned_commit" ] || \
  refuse "The released tag no longer resolves to the commit verified in this Mac app."
git -C "$fresh/repo" diff --quiet --exit-code
chown -R root:root "$fresh/repo"
chmod -R go-w "$fresh/repo"

install -d -m 0755 -o root -g root "$managed"
if [ -d /opt/slopnet ]; then
  archive=$(mktemp -d /opt/slopnet.archive.XXXXXX)
  rmdir "$archive"
  mv /opt/slopnet "$archive"
  if [ "$had_previous_approved" = yes ]; then
    mv "$approved_marker" "$archive/.slopnet-approved-build-v1"
  fi
fi
mv "$fresh/repo" /opt/slopnet
published=yes
rmdir "$fresh"
expected_install=$(install_receipt "$slopnet_release" "$pinned_commit") || \
  refuse "The newly published checkout failed its release identity proof."
marker_tmp=$(mktemp "$managed/.install-v2.XXXXXX")
printf "%s\n" "$expected_install" > "$marker_tmp"
chmod 0644 "$marker_tmp"
chown root:root "$marker_tmp"
mv "$marker_tmp" "$install_marker"
release_tmp=$(mktemp "$managed/.release-v1.XXXXXX")
printf "%s\n" "$expected_release" > "$release_tmp"
chmod 0644 "$release_tmp"
chown root:root "$release_tmp"
mv "$release_tmp" "$release_marker"
published=no
trap - EXIT HUP INT TERM
if [ -n "$archive" ]; then
  chmod -R go-rwx "$archive"
  archive_marker="$archive/.slopnet-archive-v1"
  printf "archive=%s\n" "$archive" > "$archive_marker"
  chmod 0600 "$archive_marker"
  chown root:root "$archive_marker"
  echo "[OK] archived the previous managed SlopNet install"
fi

cd /opt/slopnet
/usr/bin/python3 /opt/slopnet/slopnet setup --vps --approved'

encoded_setup=$(printf '%s' "$remote_setup" | base64)
if [ "$username" = "root" ]; then
  /usr/bin/ssh -tt -o "UserKnownHostsFile=$known_hosts_path" \
    -o LogLevel=ERROR -o StrictHostKeyChecking=accept-new \
    -o IdentitiesOnly=yes -i "$key_path" -p "$port" "$username@$host" "/bin/sh -c 'set -eu; umask 077; f=\$(/usr/bin/mktemp /tmp/slopnet-XXXXXXXX); cleanup_payload() { /bin/rm -f -- \"\$f\"; }; trap cleanup_payload EXIT HUP INT TERM; /usr/bin/printf \"%s\" \"\$1\" | /usr/bin/base64 -d > \"\$f\"; /bin/chmod 600 \"\$f\"; /bin/sh \"\$f\" \"\$2\" \"\$3\" </dev/tty' slopnet-payload '$encoded_setup' '$slopnet_release' '$slopnet_commit'"
else
  /usr/bin/ssh -tt -o "UserKnownHostsFile=$known_hosts_path" \
    -o LogLevel=ERROR -o StrictHostKeyChecking=accept-new \
    -o IdentitiesOnly=yes -i "$key_path" -p "$port" "$username@$host" "/usr/bin/sudo /bin/sh -c 'set -eu; umask 077; f=\$(/usr/bin/mktemp /tmp/slopnet-XXXXXXXX); cleanup_payload() { /bin/rm -f -- \"\$f\"; }; trap cleanup_payload EXIT HUP INT TERM; /usr/bin/printf \"%s\" \"\$1\" | /usr/bin/base64 -d > \"\$f\"; /bin/chmod 600 \"\$f\"; /bin/sh \"\$f\" \"\$2\" \"\$3\" </dev/tty' slopnet-payload '$encoded_setup' '$slopnet_release' '$slopnet_commit'"
fi

validate_key_pair || local_refuse "the dedicated key changed during server setup."
validate_known_hosts || local_refuse "the dedicated known-hosts file changed identity during server setup."

say "SlopNet Server setup finished. Read the result above before starting any project work."
