#!/usr/bin/env bash
# Build SlopNet.dmg — the disc image a person downloads, opens, and drags
# into Applications, the way every other Mac app is installed.
#
#   ./packaging/build_dmg.sh              # writes ./SlopNet.dmg
#   ./packaging/build_dmg.sh ~/Desktop    # writes it somewhere else
#
# Why a disc image and not a zip: opening a .dmg shows a window with the app
# on the left and an Applications folder on the right. Dragging one onto the
# other is the whole install, and it is the gesture Mac users already know.
# A zip drops a loose app in Downloads and leaves people wondering where it
# should live.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pkg="$root/packaging"
destination="${1:-$root}"
dmg="$destination/SlopNet.dmg"
staging="$(mktemp -d "${TMPDIR:-/tmp}/slopnet-dmg.XXXXXX")"
trap 'rm -rf "$staging"' EXIT

command -v hdiutil >/dev/null 2>&1 || {
  printf '%s\n' 'Building a disc image needs macOS hdiutil.' >&2
  exit 1
}

# Refuse to ship an installer that points at stale server code.
#
# The onboard script pins a release tag, and that tag decides which code runs
# as root on somebody's server. A crash was fixed here, a disc image was built
# and handed over, and the server carried on installing the tagged version that
# still had the bug — because nobody had cut a new tag. The fix existed and
# reached nobody.
#
# Development stays free to run ahead of the last release. Building the thing
# a person actually installs is where the pin has to be true.
pinned=$(sed -n 's/^slopnet_release="\(.*\)"$/\1/p' "$pkg/slopnet-vps-onboard.sh")
if [ -n "$pinned" ] && git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
  if ! git -C "$root" rev-parse --verify --quiet "$pinned^{commit}" >/dev/null; then
    printf 'The installer pins release %s, which is not a tag in this repository.\n' "$pinned" >&2
    printf 'Cut it, or correct slopnet_release in packaging/slopnet-vps-onboard.sh.\n' >&2
    exit 1
  fi
  # Only the files that actually run on the server. Mac-side sources and notes
  # move all the time and cannot make a server install wrong.
  drifted=$(git -C "$root" diff --name-only "$pinned" HEAD -- \
    slopnet crew.py checks packaging/slopnet-vps-onboard.sh \
    packaging/slopnet-vps-coding-app.sh packaging/slopnet-vps-local-helper.sh \
    packaging/slopnet-vps-uninstall.sh)
  if [ -n "$drifted" ]; then
    printf 'The installer pins release %s, but server code has changed since:\n' "$pinned" >&2
    printf '%s\n' "$drifted" | sed 's/^/  /' >&2
    printf '\nA disc image built now would install the old code. Cut a release first:\n' >&2
    printf '  git tag -a vX.Y.Z -m "..." && git push origin vX.Y.Z\n' >&2
    printf 'then set slopnet_release in packaging/slopnet-vps-onboard.sh to match.\n' >&2
    exit 1
  fi
fi

# Build a fresh app straight into the staging folder, so the image can never
# contain yesterday's build.
bash "$pkg/build_app.sh" "$staging" >/dev/null

# The other half of the drag: a shortcut to Applications sitting beside the
# app, so the destination is visible rather than something to go and find.
ln -s /Applications "$staging/Applications"

# A short note for the first open. An app that is not signed with a paid
# Apple Developer ID is refused by Gatekeeper on first launch, and the
# message macOS shows ("damaged", "unidentified developer") sounds far worse
# than the truth. Saying so up front is kinder than letting someone think
# the download is broken.
cat > "$staging/Read me first.txt" <<'NOTE'
Installing SlopNet
==================

1. Drag the SlopNet icon onto the Applications folder next to it.
2. Open your Applications folder and find SlopNet.
3. The FIRST time only: hold Control, click SlopNet, and choose Open.
   Then click Open again in the box that appears.

Why that third step: Apple asks developers to pay for a yearly certificate
before macOS will open a downloaded app without complaining. SlopNet does
not have one yet, so the first launch needs your permission. It only
happens once. Every launch after that is a normal double-click.

If you double-click first and macOS says the app is damaged or from an
unidentified developer, nothing is wrong — close that box and follow
step 3.
NOTE

rm -f "$dmg"
hdiutil create \
  -volname "SlopNet" \
  -srcfolder "$staging" \
  -ov -format UDZO \
  "$dmg" >/dev/null

size=$(du -h "$dmg" | cut -f1 | tr -d ' ')
printf 'Built %s (%s)\n' "$dmg" "$size"
printf 'Open it, drag SlopNet onto Applications, then Control-click SlopNet the first time.\n'
