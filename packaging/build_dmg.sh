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
