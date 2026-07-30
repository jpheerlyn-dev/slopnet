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

# The app icon comes from the operator's SlopNet-Logo.png when it exists;
# the generated placeholder icon remains the fallback so a checkout without
# the logo still builds. The PNG is 2048x2086 — sips resamples each square
# size directly (the 1.8% squeeze is invisible at icon sizes).
logo="$root/SlopNet-Logo.png"
if [ -f "$logo" ]; then
  iconset="$work/AppIcon.iconset"
  mkdir -p "$iconset"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$logo" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$logo" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$iconset" -o "$icon_file"
else
  printf 'No SlopNet-Logo.png at the repo root; using the generated icon.\n'
  python3 "$pkg/make_icon.py" "$icon_file"
fi

mkdir -p "$contents/MacOS" "$contents/Resources"
clang -fobjc-arc -Wall -Wextra -mmacosx-version-min=13.0 \
  -framework AppKit -framework CoreText \
  -I "$pkg" "$pkg/SlopNetLauncher.m" "$pkg/SlopNetConsole.m" \
  "$pkg/SlopNetSettings.m" "$pkg/SlopNetBrand.m" "$pkg/SlopNetWizard.m" \
  -o "$contents/MacOS/SlopNet"
cp "$icon_file" "$contents/Resources/AppIcon.icns"

# The colour badge font (Menlo + full-colour provider logos). Optional: when
# the terminal-visuals package is absent the app still builds and falls back
# to plain Unicode marks. Licence: a Menlo derivative may ship inside this
# local app but must never be published as a standalone download — which is
# also why the font stays out of git (see packaging/terminal-visuals/README.md).
badge_font="$pkg/terminal-visuals/packaging-fonts/Menlo-StormCode-Color.ttf"
if [ -f "$badge_font" ]; then
  cp "$badge_font" "$contents/Resources/Menlo-StormCode-Color.ttf"
else
  printf 'No colour badge font at %s — building with plain marks.\n' "$badge_font"
fi
cp "$pkg/slopnet-vps-onboard.sh" "$contents/Resources/slopnet-vps-onboard.sh"
cp "$pkg/slopnet-vps-project.sh" "$contents/Resources/slopnet-vps-project.sh"
cp "$pkg/slopnet-vps-local-helper.sh" "$contents/Resources/slopnet-vps-local-helper.sh"
cp "$pkg/slopnet-vps-chat.sh" "$contents/Resources/slopnet-vps-chat.sh"
cp "$pkg/slopnet-vps-build.sh" "$contents/Resources/slopnet-vps-build.sh"
cp "$pkg/slopnet-vps-uninstall.sh" "$contents/Resources/slopnet-vps-uninstall.sh"
cp "$pkg/tools.json" "$contents/Resources/tools.json"
chmod 755 "$contents/Resources/slopnet-vps-onboard.sh"
chmod 755 "$contents/Resources/slopnet-vps-project.sh"
chmod 755 "$contents/Resources/slopnet-vps-local-helper.sh"
chmod 755 "$contents/Resources/slopnet-vps-chat.sh"
chmod 755 "$contents/Resources/slopnet-vps-build.sh"
chmod 755 "$contents/Resources/slopnet-vps-uninstall.sh"

built_at="$(date '+%Y-%m-%d %H:%M')"
cat > "$contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SlopNet</string>
  <key>CFBundleDisplayName</key><string>SlopNet</string>
  <key>CFBundleIdentifier</key><string>com.slopnet.app</string>
  <key>CFBundleVersion</key><string>0.9.0</string>
  <key>CFBundleShortVersionString</key><string>0.9.0</string>
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
