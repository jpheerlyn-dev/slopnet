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
      .gitignore \
      .gitleaks.toml \
      banned-names.txt \
      PROTECTED.txt \
      install.sh \
      doctor.sh \
      Dockerfile \
      compose.yml \
      .dockerignore \
      SlopNet-Logo.png \
      slopnet \
      crew.py \
      adapters/claude-code/README.md \
      adapters/claude-code/hooks/guard_protected.py \
      adapters/claude-code/hooks/log_prompt.py \
      adapters/claude-code/settings.json \
      adapters/claude-code/skills/slopnet-session/SKILL.md \
      packaging/SlopNetBrand.h \
      packaging/SlopNetBrand.m \
      packaging/SlopNetConsole.h \
      packaging/SlopNetConsole.m \
      packaging/SlopNetEntryView.h \
      packaging/SlopNetEntryView.m \
      packaging/SlopNetLauncher.m \
      packaging/SlopNetSettings.h \
      packaging/SlopNetSettings.m \
      packaging/SlopNetWizard.h \
      packaging/SlopNetWizard.m \
      packaging/build_app.sh \
      packaging/build_dmg.sh \
      packaging/reset-for-testing.sh \
      packaging/make_icon.py \
      packaging/slopnet-local-ssh-proof.sh \
      packaging/slopnet-vps-onboard.sh \
      packaging/slopnet-vps-project.sh \
      packaging/slopnet-vps-local-helper.sh \
      packaging/slopnet-vps-chat.sh \
      packaging/slopnet-vps-build.sh \
      packaging/slopnet-vps-coding-app.sh \
      packaging/slopnet-vps-uninstall.sh \
      packaging/tools.json \
      tests/redteam.sh \
      tests/trial.sh \
      tests/agy_chat_recording.bin \
      tests/agy_login_recording.bin \
      tests/agy_picker_recording.bin \
      tests/agy_recordings.md \
      tests/top_recording.bin \
      tests/zellij_recording.bin \
      tests/brand_striped_probe.m \
      tests/capture_login_recording.py \
      tests/crew_unit_probe.py \
      tests/console_colour_probe.m \
      tests/console_grow_probe.m \
      tests/console_keys_probe.m \
      tests/console_menu_probe.m \
      tests/console_picture.m \
      tests/console_prompt_probe.m \
      tests/console_render.m \
      tests/console_replay_probe.m \
      tests/console_resize_oracle.py \
      tests/console_scroll_probe.m \
      tests/launcher_tool_probe.m \
      tests/menu_fixture.py \
      tests/pty_probe.c \
      tests/reference_screen.py \
      tests/server_safety_probe.py \
      tests/settings_resize_probe.m \
      tests/wizard_step_probe.m \
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
