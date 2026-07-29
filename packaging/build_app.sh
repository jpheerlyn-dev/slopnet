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

# Updating must be the easy path: an app you cannot reinstall is an app
# stuck on its first version. The old copy is moved aside, never deleted,
# so you can always go back to it.
previous=""
if [ -e "$app" ]; then
  previous="$destination/SlopNet-previous-$(date +%Y%m%d-%H%M%S).app"
  mv "$app" "$previous" || {
    printf 'Could not move the existing app aside: %s\n' "$app" >&2
    printf 'Close SlopNet if it is running, then build again.\n' >&2
    exit 1
  }
  printf 'Existing app kept as %s\n' "$previous"
fi

command -v clang >/dev/null 2>&1 || { printf '%s\n' 'SlopNet.app needs the macOS clang compiler.' >&2; exit 1; }
python3 "$pkg/make_icon.py" "$icon_file"

mkdir -p "$contents/MacOS" "$contents/Resources"
clang -fobjc-arc -mmacosx-version-min=13.0 -framework AppKit \
  -I "$pkg" "$pkg/SlopNetLauncher.m" "$pkg/SlopNetConsole.m" \
  "$pkg/SlopNetSettings.m" \
  -o "$contents/MacOS/SlopNet"
cp "$icon_file" "$contents/Resources/AppIcon.icns"
cp "$pkg/slopnet-vps-onboard.sh" "$contents/Resources/slopnet-vps-onboard.sh"
cp "$pkg/slopnet-vps-project.sh" "$contents/Resources/slopnet-vps-project.sh"
cp "$pkg/tools.json" "$contents/Resources/tools.json"
chmod 755 "$contents/Resources/slopnet-vps-onboard.sh"
chmod 755 "$contents/Resources/slopnet-vps-project.sh"

built_at="$(date '+%Y-%m-%d %H:%M')"
cat > "$contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SlopNet</string>
  <key>CFBundleDisplayName</key><string>SlopNet</string>
  <key>CFBundleIdentifier</key><string>com.slopnet.app</string>
  <key>CFBundleVersion</key><string>0.3.0</string>
  <key>CFBundleShortVersionString</key><string>0.3.0</string>
  <key>SlopNetBuiltAt</key><string>${built_at}</string>
  <key>CFBundleExecutable</key><string>SlopNet</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <!-- No NSAppleEventsUsageDescription: SlopNet no longer drives Terminal.
       Everything runs inside the app window, so macOS never has to ask for
       Automation permission. -->
  <key>NSHumanReadableCopyright</key><string>MIT licensed.</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$app" >/dev/null 2>&1 || true

lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$lsregister" -f "$app" >/dev/null 2>&1 || true
printf 'Built %s\n' "$app"
