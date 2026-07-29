#!/bin/sh
# Run me whenever machinery legitimately changes; commit the result in the same commit.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf '%s\n' 'Run ./update-manifest.sh from inside a Git repository.' >&2
  exit 1
}
cd "$root" || exit 1

paths=$(
  {
    for path in checks/*.sh hooks/* rulesets/*; do
      printf '%s\n' "$path"
    done
    printf '%s\n' \
      lefthook.yml \
      .gitleaks.toml \
      install.sh \
      doctor.sh \
      Dockerfile \
      compose.yml \
      .dockerignore \
      slopnet \
      crew.py \
      packaging/SlopNetLauncher.m \
      packaging/build_app.sh \
      packaging/make_icon.py \
      packaging/slopnet-vps-onboard.sh \
      packaging/slopnet-vps-project.sh \
      tests/redteam.sh \
      update-manifest.sh \
      .github/workflows/slopnet.yml \
      .github/workflows/watchman.yml \
      .github/workflows/selftest.yml
  } | LC_ALL=C sort
)

missing=$(
  printf '%s\n' "$paths" | while IFS= read -r path; do
    [ -f "$path" ] || printf '%s\n' "$path"
  done
)
if [ -n "$missing" ]; then
  printf 'Cannot regenerate MANIFEST.sha256; required machinery is missing: %s\n' \
    "$(printf '%s\n' "$missing" | awk 'BEGIN { ORS=" " } { print }')" >&2
  exit 1
fi

checksum() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1"
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1"
  else
    printf '%s\n' 'Cannot regenerate MANIFEST.sha256; sha256sum or shasum is required.' >&2
    return 1
  fi
}

temporary="MANIFEST.sha256.tmp.$$"
trap 'rm -f "$temporary"' EXIT HUP INT TERM
{
  printf '%s\n' '# Run me whenever machinery legitimately changes; commit the result in the same commit.'
  printf '%s\n' "$paths" | while IFS= read -r path; do
    checksum "$path"
  done
} > "$temporary"
mv "$temporary" MANIFEST.sha256
trap - EXIT HUP INT TERM
