#!/usr/bin/env bash
# The interactive half of the Mac app's first VPS connection.
# Password prompts stay inside macOS OpenSSH; this script never receives or
# stores a VPS password.
set -euo pipefail

host="$1"
port="$2"
username="$3"
key_path="$HOME/.ssh/slopnet_vps_ed25519"
repo_url="https://github.com/jpheerlyn-dev/slopnet.git"

say() {
  printf '\n%s\n' "$1"
}

say "SlopNet will now connect to ${username}@${host}:${port}."
say "Your password is requested by OpenSSH only if this VPS has not accepted your dedicated SlopNet key yet."

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if [ ! -f "$key_path" ]; then
  say "Creating one dedicated SSH key on this Mac for SlopNet VPS access."
  ssh-keygen -t ed25519 -f "$key_path" -N "" -C "slopnet-vps" >/dev/null
elif [ ! -f "$key_path.pub" ]; then
  ssh-keygen -y -f "$key_path" > "$key_path.pub"
fi

say "First connection: check the VPS host fingerprint shown by SSH, then enter the password supplied by your provider if asked."
cat "$key_path.pub" | ssh -p "$port" "$username@$host" \
  'umask 077; mkdir -p "$HOME/.ssh"; touch "$HOME/.ssh/authorized_keys"; cat >> "$HOME/.ssh/authorized_keys"'

ssh -o BatchMode=yes -p "$port" "$username@$host" 'printf "SSH key accepted on %s\\n" "$(hostname)"'

say "Connection proved. The next command may ask for your VPS sudo password."
say "It installs Git only when missing, downloads SlopNet, then lets SlopNet ask separately before it creates its isolated runtime account, installs a sandbox prerequisite, or starts a provider login."
read -r -p "Press Return to continue, or close this Terminal window to stop: "

remote_setup='set -e
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
  git -C /opt/slopnet pull --ff-only
else
  git clone https://github.com/jpheerlyn-dev/slopnet.git /opt/slopnet
fi
cd /opt/slopnet
./slopnet setup --vps'

encoded_setup=$(printf '%s' "$remote_setup" | base64)
if [ "$username" = "root" ]; then
  ssh -tt -p "$port" "$username@$host" "printf %s '$encoded_setup' | base64 -d | sh"
else
  ssh -tt -p "$port" "$username@$host" "printf %s '$encoded_setup' | base64 -d | sudo sh"
fi

say "SlopNet VPS setup finished. Read the result above before starting any project work."
read -r -p "Press Return to close this setup window: "
