#!/usr/bin/env bash
# Build SlopNet.app without a third-party packager.
#
# ./packaging/build_app.sh /Applications
#
# The bundle contains a native Mac control screen and an SSH helper. It never
# contains a provider token or a VPS password.
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pkg="$root/packaging"
# A release app and the root server code it installs are one unit. Resolve the
# exact pinned tag, put its version in Info.plist, and inject its immutable
# commit into the bundled installer. The source helper deliberately has an
# empty commit, so running a mutable tag name by itself fails closed.
slopnet_release=$(sed -n 's/^slopnet_release="\(v[0-9][0-9.]*\)"$/\1/p' \
  "$pkg/slopnet-vps-onboard.sh" | head -1)
if [ -z "$slopnet_release" ]; then
  printf '%s\n' 'The server installer has no valid release tag.' >&2
  exit 1
fi
bundle_paths=(
  SlopNet-Logo.png slopnet crew.py checks
  packaging/SlopNetBrand.h packaging/SlopNetBrand.m
  packaging/SlopNetConsole.h packaging/SlopNetConsole.m
  packaging/SlopNetEntryView.h packaging/SlopNetEntryView.m
  packaging/SlopNetLauncher.m
  packaging/SlopNetSettings.h packaging/SlopNetSettings.m
  packaging/SlopNetTools.h packaging/SlopNetTools.m
  packaging/SlopNetWizard.h packaging/SlopNetWizard.m
  packaging/build_app.sh packaging/build_dmg.sh packaging/make_icon.py
  packaging/slopnet-local-ssh-proof.sh
  packaging/slopnet-vps-onboard.sh packaging/slopnet-vps-project.sh
  packaging/slopnet-vps-local-helper.sh packaging/slopnet-vps-chat.sh
  packaging/slopnet-vps-build.sh packaging/slopnet-vps-coding-app.sh
  packaging/slopnet-vps-uninstall.sh packaging/tools.json
)
if [ "${SLOPNET_ALLOW_UNRELEASED_BUILD:-}" = 1 ]; then
  slopnet_commit=$(git -C "$root" rev-parse HEAD)
  printf '%s\n' 'Building an unreleased local app; server setup will still require the pinned tag.' >&2
else
  git -C "$root" show-ref --verify --quiet "refs/tags/$slopnet_release" || {
    printf 'Release tag %s does not exist; tag and verify it before building the app.\n' \
      "$slopnet_release" >&2
    exit 1
  }
  slopnet_commit=$(git -C "$root" rev-parse --verify \
    "refs/tags/$slopnet_release^{commit}")
  drift=$(git -C "$root" diff --name-only "refs/tags/$slopnet_release" -- \
    "${bundle_paths[@]}")
  untracked=$(git -C "$root" ls-files --others --exclude-standard -- \
    "${bundle_paths[@]}")
  if [ -n "$drift$untracked" ]; then
    printf 'The app inputs do not exactly match release %s; nothing was built:\n' \
      "$slopnet_release" >&2
    printf '%s\n' "$drift" "$untracked" | sed '/^$/d; s/^/  /' >&2
    printf '%s\n' 'Use SLOPNET_ALLOW_UNRELEASED_BUILD=1 only for an explicitly local development build.' >&2
    exit 1
  fi
fi
slopnet_version=${slopnet_release#v}
destination="${1:-/Applications}"
work="$(mktemp -d "${TMPDIR:-/tmp}/slopnet-app.XXXXXX")"
app="$work/SlopNet.app"
contents="$app/Contents"
published_app="$destination/SlopNet.app"
icon_file="$work/AppIcon.icns"
trap 'rm -rf "$work"' EXIT

# Release inputs come from one immutable tag snapshot. The worktree check above
# still catches a forgotten fix, while the snapshot prevents a concurrent edit
# between that check and a later compile/copy from creating a mixed-identity
# app. Local development builds intentionally use the live checkout.
source_root="$root"
source_pkg="$pkg"
if [ "${SLOPNET_ALLOW_UNRELEASED_BUILD:-}" != 1 ]; then
  source_root="$work/release-source"
  mkdir "$source_root"
  git -C "$root" archive --format=tar "refs/tags/$slopnet_release" | \
    tar -x -C "$source_root"
  source_pkg="$source_root/packaging"
  grep -qx "slopnet_release=\"$slopnet_release\"" \
    "$source_pkg/slopnet-vps-onboard.sh" || {
      printf '%s\n' 'The immutable release snapshot has a different server pin.' >&2
      exit 1
    }
fi

command -v clang >/dev/null 2>&1 || { printf '%s\n' 'SlopNet.app needs the macOS clang compiler.' >&2; exit 1; }

# The app icon comes from the operator's SlopNet-Logo.png when it exists;
# the generated placeholder icon remains the fallback so a checkout without
# the logo still builds. The PNG is 2048x2086 — sips resamples each square
# size directly (the 1.8% squeeze is invisible at icon sizes).
logo="$source_root/SlopNet-Logo.png"
if [ -f "$logo" ]; then
  iconset="$work/AppIcon.iconset"
  mkdir -p "$iconset"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$logo" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$logo" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  # iconutil on current macOS rejects an otherwise standard iconset produced
  # by sips. Pack the same PNG payloads into the documented ICNS chunk format;
  # the fallback generator below uses that format too and round-trips through
  # iconutil successfully.
  python3 "$source_pkg/make_icon.py" "$icon_file" "$iconset"
else
  printf 'No SlopNet-Logo.png at the repo root; using the generated icon.\n'
  python3 "$source_pkg/make_icon.py" "$icon_file"
fi

mkdir -p "$contents/MacOS" "$contents/Resources"
clang -fobjc-arc -Wall -Wextra -mmacosx-version-min=13.0 \
  -framework AppKit -framework CoreText -framework QuartzCore \
  -I "$source_pkg" "$source_pkg/SlopNetLauncher.m" "$source_pkg/SlopNetConsole.m" \
  "$source_pkg/SlopNetEntryView.m" \
  "$source_pkg/SlopNetSettings.m" "$source_pkg/SlopNetTools.m" \
  "$source_pkg/SlopNetBrand.m" \
  "$source_pkg/SlopNetWizard.m" \
  -o "$contents/MacOS/SlopNet"
cp "$icon_file" "$contents/Resources/AppIcon.icns"

# The colour badge font (Menlo + full-colour provider logos). Optional: when
# the terminal-visuals package is absent the app still builds and falls back
# to plain Unicode marks. Licence: a Menlo derivative may ship inside this
# local app but must never be published as a standalone download — which is
# also why the font stays out of git (see packaging/terminal-visuals/README.md).
badge_font="$pkg/terminal-visuals/packaging-fonts/Menlo-StormCode-Color.ttf"
badge_font_digest="ce279a1c5591c2799d26ee58495bda1bbc8aca66b58dc44138ac77599b0b4fbb"
if [ -f "$badge_font" ]; then
  actual_badge_digest=$(shasum -a 256 "$badge_font" | awk '{print $1}')
  if [ "$actual_badge_digest" != "$badge_font_digest" ]; then
    printf '%s\n' 'The optional colour badge font differs from the proved bundle input; refusing to package it.' >&2
    exit 1
  fi
  cp "$badge_font" "$contents/Resources/Menlo-StormCode-Color.ttf"
else
  printf 'No colour badge font at %s — building with plain marks.\n' "$badge_font"
fi
sed "s/^slopnet_commit=\"\"$/slopnet_commit=\"$slopnet_commit\"/" \
  "$source_pkg/slopnet-vps-onboard.sh" > "$contents/Resources/slopnet-vps-onboard.sh"
grep -qx "slopnet_commit=\"$slopnet_commit\"" \
  "$contents/Resources/slopnet-vps-onboard.sh" || {
    printf '%s\n' 'Could not bind the server installer to the verified release commit.' >&2
    exit 1
  }
cp "$source_pkg/slopnet-vps-project.sh" "$contents/Resources/slopnet-vps-project.sh"
cp "$source_pkg/slopnet-vps-local-helper.sh" "$contents/Resources/slopnet-vps-local-helper.sh"
cp "$source_pkg/slopnet-vps-chat.sh" "$contents/Resources/slopnet-vps-chat.sh"
cp "$source_pkg/slopnet-vps-build.sh" "$contents/Resources/slopnet-vps-build.sh"
cp "$source_pkg/slopnet-vps-coding-app.sh" "$contents/Resources/slopnet-vps-coding-app.sh"
cp "$source_pkg/slopnet-vps-uninstall.sh" "$contents/Resources/slopnet-vps-uninstall.sh"
cp "$source_pkg/slopnet-local-ssh-proof.sh" "$contents/Resources/slopnet-local-ssh-proof.sh"
cp "$source_pkg/tools.json" "$contents/Resources/tools.json"
chmod 755 "$contents/Resources/slopnet-vps-onboard.sh"
chmod 755 "$contents/Resources/slopnet-vps-project.sh"
chmod 755 "$contents/Resources/slopnet-vps-local-helper.sh"
chmod 755 "$contents/Resources/slopnet-vps-chat.sh"
chmod 755 "$contents/Resources/slopnet-vps-build.sh"
chmod 755 "$contents/Resources/slopnet-vps-coding-app.sh"
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
  <key>CFBundleVersion</key><string>${slopnet_version}</string>
  <key>CFBundleShortVersionString</key><string>${slopnet_version}</string>
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

codesign --force --deep --sign - "$app" >/dev/null
codesign --verify --deep --strict "$app" >/dev/null

# Build completely in the private staging directory. Only after every input,
# compile and signature step succeeds do we move the existing app aside and
# publish this one. A dangling symlink counts as an existing app and is moved
# as a link; it is never followed.
mkdir -p "$destination"
previous=""
if [ -e "$published_app" ] || [ -L "$published_app" ]; then
  stamp=$(date '+%Y%m%d-%H%M%S')
  previous="$destination/SlopNet-previous-$stamp.app"
  suffix=0
  while [ -e "$previous" ] || [ -L "$previous" ]; do
    suffix=$((suffix + 1))
    previous="$destination/SlopNet-previous-$stamp-$suffix.app"
  done
  mv -n -- "$published_app" "$previous" || {
    printf 'Could not archive the existing app: %s\n' "$published_app" >&2
    printf 'Close SlopNet if it is running, then build again.\n' >&2
    exit 1
  }
  if [ -e "$published_app" ] || [ -L "$published_app" ]; then
    printf 'The archive destination changed while publishing; the existing app was left in place.\n' >&2
    exit 1
  fi
  printf 'Existing app kept as %s\n' "$previous"
fi
if ! mv -n -- "$app" "$published_app" || [ -e "$app" ] || [ -L "$app" ]; then
  if [ -n "$previous" ] && [ ! -e "$published_app" ] && [ ! -L "$published_app" ]; then
    mv -- "$previous" "$published_app" || true
  fi
  printf 'Could not publish the new app at %s.\n' "$published_app" >&2
  exit 1
fi

lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$lsregister" -f "$published_app" >/dev/null 2>&1 || true
printf 'Built %s\n' "$published_app"
