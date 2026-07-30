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
slopnet_release="v0.9.1"
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
  say "Step 1 of 3 — protect this connection"
  say "Create a passphrase for the SlopNet connection key. It stays on this Mac and protects the key if the Mac is ever lost."
  ssh-keygen -q -t ed25519 -f "$key_path" -C "slopnet-vps"
elif [ ! -f "$key_path.pub" ]; then
  ssh-keygen -y -f "$key_path" > "$key_path.pub"
fi

if command -v ssh-add >/dev/null 2>&1; then
  say "macOS will now ask for that passphrase once more so it can keep the key in your Keychain."
  ssh-add -q --apple-use-keychain "$key_path" || \
    say "The key was not added to the macOS keychain. That is safe; SSH may ask for the passphrase during setup."
fi

say "Step 2 of 3 — confirm your VPS"
say "If SSH asks whether you trust this server, continue only when ${host} is the IP address from your VPS provider. Then enter the VPS password if asked. It is not saved."
cat "$key_path.pub" | ssh -o LogLevel=ERROR -p "$port" "$username@$host" \
  'key=$(cat); umask 077; mkdir -p "$HOME/.ssh"; touch "$HOME/.ssh/authorized_keys"; grep -qxF "$key" "$HOME/.ssh/authorized_keys" || printf "%s\n" "$key" >> "$HOME/.ssh/authorized_keys"'

ssh -o LogLevel=ERROR -i "$key_path" -p "$port" "$username@$host" true

say "Your protected connection is ready."
say "Step 3 of 3 — prepare the VPS"
say "SlopNet will update its own workspace and then ask separately before it changes anything on the VPS. If you did not sign in as root, your VPS may ask for your sudo password now."
read -r -p "Press Return to prepare the VPS, or close this window to stop: "

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
if [ -d /opt/slopnet/.git ]; then
  if id -u slopnet >/dev/null 2>&1 && command -v runuser >/dev/null 2>&1; then
    runuser -u slopnet -- git -C /opt/slopnet fetch --quiet --tags origin
  else
    git -c safe.directory=/opt/slopnet -C /opt/slopnet fetch --quiet --tags origin
  fi
else
  git clone --quiet https://github.com/jpheerlyn-dev/slopnet.git /opt/slopnet
fi
cd /opt/slopnet
# Check out the exact release this installer was shipped with, rather than
# whatever the default branch says today. The next line is the only thing that
# decides which code a beginner runs as root on their own server; a moving
# branch would mean anyone who could push could choose that for them.
# Updating SlopNet is deliberately a decision, not a side effect of setup.
if ! git -c advice.detachedHead=false checkout --quiet "$slopnet_release" 2>/dev/null; then
  echo "RULE: SlopNet could not check out its released version ($slopnet_release)."
  echo "WHY:  Setup runs this code as root, so it will not fall back to whatever the branch currently holds."
  echo "FIX:  Check this server can reach GitHub, then start setup again. Nothing was installed."
  exit 1
fi
./slopnet setup --vps'

encoded_setup=$(printf '%s' "$remote_setup" | base64)
if [ "$username" = "root" ]; then
  ssh -tt -p "$port" "$username@$host" "umask 077; f=\$(mktemp /tmp/slopnet-XXXXXXXX) || exit 1; trap 'rm -f -- \"\$f\"' EXIT HUP INT TERM; printf %s '$encoded_setup' | base64 -d > \"\$f\" && sh \"\$f\" '$slopnet_release' </dev/tty"
else
  ssh -tt -p "$port" "$username@$host" "umask 077; f=\$(mktemp /tmp/slopnet-XXXXXXXX) || exit 1; trap 'rm -f -- \"\$f\"' EXIT HUP INT TERM; printf %s '$encoded_setup' | base64 -d > \"\$f\" && sudo sh \"\$f\" '$slopnet_release' </dev/tty"
fi

say "SlopNet VPS setup finished. Read the result above before starting any project work."
read -r -p "Press Return to close this setup window: "
