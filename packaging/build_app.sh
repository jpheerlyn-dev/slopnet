#!/usr/bin/env bash
# Build SlopNet.app without a third-party packager.
#
# ./packaging/build_app.sh /Applications
#
# The bundle contains a native Mac control screen and an SSH helper. It never
# contains a provider token or a VPS password.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pkg="$root/packaging"
destination="${1:-/Applications}"
app="$destination/SlopNet.app"
contents="$app/Contents"
work="$(mktemp -d "${TMPDIR:-/tmp}/slopnet-app.XXXXXX")"
icon_file="$work/AppIcon.icns"
trap 'rm -rf "$work"' EXIT

if [ -e "$app" ]; then
  printf 'Refusing to overwrite %s. Archive or move the existing app, then build again.\n' "$app" >&2
  exit 1
fi

command -v clang >/dev/null 2>&1 || { printf '%s\n' 'SlopNet.app needs the macOS clang compiler.' >&2; exit 1; }
python3 "$pkg/make_icon.py" "$icon_file"

mkdir -p "$contents/MacOS" "$contents/Resources"
clang -fobjc-arc -mmacosx-version-min=13.0 -framework AppKit "$pkg/SlopNetLauncher.m" -o "$contents/MacOS/SlopNet"
cp "$icon_file" "$contents/Resources/AppIcon.icns"
cp "$pkg/slopnet-vps-onboard.sh" "$contents/Resources/slopnet-vps-onboard.sh"
chmod 755 "$contents/Resources/slopnet-vps-onboard.sh"

cat > "$contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SlopNet</string>
  <key>CFBundleDisplayName</key><string>SlopNet</string>
  <key>CFBundleIdentifier</key><string>com.slopnet.app</string>
  <key>CFBundleVersion</key><string>0.1.3</string>
  <key>CFBundleShortVersionString</key><string>0.1.3</string>
  <key>CFBundleExecutable</key><string>SlopNet</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSAppleEventsUsageDescription</key><string>SlopNet opens Terminal only to run the VPS setup the person has explicitly started. Terminal receives the normal SSH password prompt; SlopNet does not collect or store that password.</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$app" >/dev/null 2>&1 || true

lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$lsregister" -f "$app" >/dev/null 2>&1 || true
printf 'Built %s\n' "$app"
