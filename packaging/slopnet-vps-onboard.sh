#!/usr/bin/env bash
# The interactive half of the Mac app's first VPS connection.
# Password prompts stay inside macOS OpenSSH; this script never receives or
# stores a VPS password.
set -euo pipefail

host="$1"
port="$2"
username="$3"
# The exact SlopNet release this installer puts on a server. Setup runs
# that code as root, so it is pinned rather than following whatever the
# default branch holds today. Bump it when a release is cut and proved.
slopnet_release="v0.9.8"
key_path="$HOME/.ssh/slopnet_vps_ed25519"
repo_url="https://github.com/jpheerlyn-dev/slopnet.git"

say() {
  printf '\n%s\n' "$1"
}

clear
printf '\033]0;SlopNet VPS setup\007'
say "SlopNet VPS setup"
say "You are setting up a protected connection between this Mac and your VPS. SlopNet will never save your VPS password."

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if [ ! -f "$key_path" ]; then
  say "Step 1 of 3 — making a key for this connection"
  say "SlopNet is creating a key so this Mac can reach your server without a password every time. It is kept in your own .ssh folder, readable only by you."
  # No passphrase, deliberately. A passphrase here bought one more secret to
  # remember and three extra prompts, and it was cached in the login keychain
  # immediately afterwards anyway — so it protected nothing that the file
  # permissions and FileVault do not already protect. The key reaches exactly
  # one server, the one the person is setting up.
  ssh-keygen -q -t ed25519 -N "" -f "$key_path" -C "slopnet-vps"
  chmod 600 "$key_path"
elif [ ! -f "$key_path.pub" ]; then
  ssh-keygen -y -f "$key_path" > "$key_path.pub"
fi


say "Step 2 of 3 — confirm your VPS"
say "If SSH asks whether you trust this server, continue only when ${host} is the IP address from your VPS provider. Then enter the VPS password if asked. It is not saved."
cat "$key_path.pub" | ssh -o LogLevel=ERROR -p "$port" "$username@$host" \
  'key=$(cat); umask 077; mkdir -p "$HOME/.ssh"; touch "$HOME/.ssh/authorized_keys"; grep -qxF "$key" "$HOME/.ssh/authorized_keys" || printf "%s\n" "$key" >> "$HOME/.ssh/authorized_keys"'

ssh -o LogLevel=ERROR -i "$key_path" -p "$port" "$username@$host" true

say "Your protected connection is ready."
say "Step 3 of 3 — prepare the VPS"
# Everything that changes, said once, here — the only place in this flow with
# a terminal the person actually opened. Setup used to repeat six variations
# of this question over the SSH connection, where an unanswered one stops the
# run with nothing on screen.
say "This is everything SlopNet changes on your VPS:"
printf '%s\n' \
  "  - creates a locked account called slopnet, with a private home folder" \
  "  - installs SlopNet into /opt/slopnet and gives that account ownership of it" \
  "  - installs bubblewrap, so coding agents run boxed in rather than loose" \
  "  - installs the coding app's command-line tool, ready to sign in later" \
  "" \
  "It does not touch root SSH access, password SSH access, firewall rules or ports." \
  "It does not sign you in to anything, and it does not download the guide yet."
say "If you did not sign in as root, your VPS may ask for your sudo password now."
read -r -p "Make those changes? [y/N] " ready
case "$(printf %s "$ready" | tr "[:upper:]" "[:lower:]")" in
  y|yes) ;;
  *) say "Nothing changed on your VPS."; exit 0 ;;
esac

remote_setup='set -e
slopnet_release=$1
if ! command -v git >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y git
  else
    echo "Git is missing and this VPS has no supported automatic installer. Install git, then start SlopNet again."
    exit 1
  fi
fi
# After the first run /opt/slopnet belongs to the slopnet user while this
# script runs as root, and git refuses to touch a repository somebody else
# owns. Every git call here therefore goes through one helper: as the owner
# when that user exists, so fetched objects do not end up owned by root, and
# always naming the directory as trusted, which is what root needs to read it.
#
# Getting this wrong is invisible on a first install and fatal on every run
# after it — the state a person is in precisely when they are retrying.
checkout_owner=$(stat -c %U /opt/slopnet 2>/dev/null || echo root)
if [ "$checkout_owner" != "root" ] && id -u "$checkout_owner" >/dev/null 2>&1 \
   && command -v runuser >/dev/null 2>&1; then
  as_owner="runuser -u $checkout_owner --"
else
  as_owner=""
fi
sgit() {
  $as_owner git -c safe.directory=/opt/slopnet -c advice.detachedHead=false "$@"
}

if [ -d /opt/slopnet/.git ]; then
  sgit -C /opt/slopnet fetch --quiet --tags --force origin
else
  git clone --quiet https://github.com/jpheerlyn-dev/slopnet.git /opt/slopnet
fi
cd /opt/slopnet
# Check out the exact release this installer was shipped with, rather than
# whatever the default branch says today. The next line is the only thing that
# decides which code a beginner runs as root on their own server; a moving
# branch would mean anyone who could push could choose that for them.
# Updating SlopNet is deliberately a decision, not a side effect of setup.
#
# The real git error is printed. Hiding it once cost an evening chasing a
# network fault that did not exist: the failure was an ownership refusal, and
# the message this prints said to check the connection to GitHub.
if ! checkout_error=$(sgit -C /opt/slopnet checkout --quiet "$slopnet_release" 2>&1); then
  echo "RULE: SlopNet could not check out its released version ($slopnet_release)."
  echo "WHY:  Setup runs this code as root, so it will not fall back to whatever the branch currently holds."
  echo "FIX:  Read the git error below, fix what it names, then start setup again. Nothing was installed."
  echo "$checkout_error"
  exit 1
fi
./slopnet setup --vps --approved'

encoded_setup=$(printf '%s' "$remote_setup" | base64)
if [ "$username" = "root" ]; then
  ssh -tt -p "$port" "$username@$host" "umask 077; f=\$(mktemp /tmp/slopnet-XXXXXXXX) || exit 1; trap 'rm -f -- \"\$f\"' EXIT HUP INT TERM; printf %s '$encoded_setup' | base64 -d > \"\$f\" && sh \"\$f\" '$slopnet_release' </dev/tty"
else
  ssh -tt -p "$port" "$username@$host" "umask 077; f=\$(mktemp /tmp/slopnet-XXXXXXXX) || exit 1; trap 'rm -f -- \"\$f\"' EXIT HUP INT TERM; printf %s '$encoded_setup' | base64 -d > \"\$f\" && sudo sh \"\$f\" '$slopnet_release' </dev/tty"
fi

say "SlopNet VPS setup finished. Read the result above before starting any project work."
