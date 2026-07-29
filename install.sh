#!/usr/bin/env bash
# Arms SlopNet's local hooks and fetches pinned optional fast checks.

LEFTHOOK_VERSION="2.1.9"
GITLEAKS_VERSION="8.30.1"
LEFTHOOK_DARWIN_ARM64_SHA256="fd506e05954af2062ce320d59ac1f5bf13fad8d694694a72bc6ef91e8c284e3d"
LEFTHOOK_DARWIN_X64_SHA256="0868b9b5b9cd807b0f9e0135fadaff1bd99fa026cccc15cbfd4510f0ee3b5431"
LEFTHOOK_LINUX_ARM64_SHA256="304321997336c450af6b5c0cc641c59141168866fca0b1fc3767e067812600a9"
LEFTHOOK_LINUX_X64_SHA256="0d60b0d350c923963729574f6431171f0277788884ad0c6284fa0160c36e3877"
GITLEAKS_DARWIN_ARM64_SHA256="b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5"
GITLEAKS_DARWIN_X64_SHA256="dfe101a4db2255fc85120ac7f3d25e4342c3c20cf749f2c20a18081af1952709"
GITLEAKS_LINUX_ARM64_SHA256="e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080"
GITLEAKS_LINUX_X64_SHA256="551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"

root=$(git rev-parse --show-toplevel 2>/dev/null || true)
# --show-prefix is empty exactly at the repo root. Never compare paths as
# strings here: on case-insensitive filesystems (macOS default) the user's
# typed path and git's canonical path can differ by case alone.
if [ -z "$root" ] || [ -n "$(git rev-parse --show-prefix 2>/dev/null)" ]; then
  printf '%s\n' 'RULE: install.sh was not run from the repository root.'
  printf '%s\n' 'WHY:  Hooks and PATH install only make sense at the project root.'
  printf '%s\n' 'FIX:  cd into your SlopNet project root, then run: ./install.sh'
  exit 1
fi
cd "$root" || exit 1

mkdir -p .git/hooks .slopnet/bin || exit 1
cp hooks/pre-commit .git/hooks/pre-commit || exit 1
cp hooks/post-commit .git/hooks/post-commit || exit 1
chmod +x .git/hooks/pre-commit .git/hooks/post-commit || exit 1

sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    return 1
  fi
}

download_and_verify() {
  file=$1
  url=$2
  expected=$3
  curl -fsSL --retry 1 --connect-timeout 10 "$url" -o "$file" >/dev/null 2>&1 || return 1
  actual=$(sha256 "$file") || return 1
  [ "$actual" = "$expected" ]
}

fallback() {
  rm -f .slopnet/bin/lefthook .slopnet/bin/gitleaks .slopnet/bin/.lefthook-download .slopnet/bin/.gitleaks-download
  : > .slopnet/fallback
  printf '%s\n' 'Running in fallback mode — slower, same protection.'
}

os=$(uname -s)
arch=$(uname -m)
case "$os/$arch" in
  Darwin/arm64|Darwin/aarch64)
    lefthook_asset="MacOS_arm64"
    lefthook_sha="$LEFTHOOK_DARWIN_ARM64_SHA256"
    gitleaks_asset="darwin_arm64.tar.gz"
    gitleaks_sha="$GITLEAKS_DARWIN_ARM64_SHA256"
    ;;
  Darwin/x86_64)
    lefthook_asset="MacOS_x86_64"
    lefthook_sha="$LEFTHOOK_DARWIN_X64_SHA256"
    gitleaks_asset="darwin_x64.tar.gz"
    gitleaks_sha="$GITLEAKS_DARWIN_X64_SHA256"
    ;;
  Linux/arm64|Linux/aarch64)
    lefthook_asset="Linux_arm64"
    lefthook_sha="$LEFTHOOK_LINUX_ARM64_SHA256"
    gitleaks_asset="linux_arm64.tar.gz"
    gitleaks_sha="$GITLEAKS_LINUX_ARM64_SHA256"
    ;;
  Linux/x86_64|Linux/amd64)
    lefthook_asset="Linux_x86_64"
    lefthook_sha="$LEFTHOOK_LINUX_X64_SHA256"
    gitleaks_asset="linux_x64.tar.gz"
    gitleaks_sha="$GITLEAKS_LINUX_X64_SHA256"
    ;;
  *)
    fallback
    lefthook_asset=""
    ;;
esac

if [ -n "$lefthook_asset" ]; then
  lefthook_url="https://github.com/evilmartians/lefthook/releases/download/v${LEFTHOOK_VERSION}/lefthook_${LEFTHOOK_VERSION}_${lefthook_asset}"
  gitleaks_url="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_${gitleaks_asset}"
  if download_and_verify .slopnet/bin/.lefthook-download "$lefthook_url" "$lefthook_sha" \
    && download_and_verify .slopnet/bin/.gitleaks-download "$gitleaks_url" "$gitleaks_sha" \
    && mv .slopnet/bin/.lefthook-download .slopnet/bin/lefthook \
    && tar -xzf .slopnet/bin/.gitleaks-download -C .slopnet/bin gitleaks \
    && chmod +x .slopnet/bin/lefthook .slopnet/bin/gitleaks; then
    rm -f .slopnet/bin/.gitleaks-download .slopnet/fallback
  else
    fallback
  fi
fi

# --- PATH: type `slopnet` from any folder (default macOS zsh) ---
# Symlink this checkout's slopnet into ~/.local/bin and ensure that
# directory is on PATH via the user's own ~/.zshrc. Idempotent. Never
# edits files outside the user's home profile.
install_user_path() {
  bin_dir="${HOME}/.local/bin"
  link="${bin_dir}/slopnet"
  target="${root}/slopnet"
  profile="${HOME}/.zshrc"
  path_line='export PATH="$HOME/.local/bin:$PATH"  # slopnet'

  # Never rewrite the user's global `slopnet` from a throwaway tree
  # (red-team, mktemp clones). Those checkouts vanish and would leave
  # a broken command on PATH.
  case "$root" in
    /tmp/*|*/tmp/*|"${TMPDIR%/}"/*|*slopnet-redteam*|*j06-break*)
      printf '%s\n' "[OK] Skipping user PATH install for temporary checkout"
      return 0
      ;;
  esac
  if [ -n "${SLOPNET_SKIP_USER_PATH:-}" ]; then
    printf '%s\n' "[OK] Skipping user PATH install (SLOPNET_SKIP_USER_PATH is set)"
    return 0
  fi

  if [ ! -f "$target" ]; then
    printf '%s\n' 'RULE: Could not put slopnet on PATH.'
    printf '%s\n' 'WHY:  No slopnet program in this repository root.'
    printf '%s\n' 'FIX:  Run ./install.sh from the root of a full SlopNet checkout.'
    return 1
  fi
  if [ ! -x "$target" ]; then
    chmod +x "$target" || true
  fi

  mkdir -p "$bin_dir" || return 1

  if [ -L "$link" ] || [ -e "$link" ]; then
    current=$(readlink "$link" 2>/dev/null || true)
    if [ "$current" = "$target" ]; then
      printf '%s\n' "[OK] PATH link already points at this checkout: ${link}"
    else
      ln -sfn "$target" "$link"
      printf '%s\n' "[OK] Updated symlink ${link} -> ${target}"
    fi
  else
    ln -sfn "$target" "$link"
    printf '%s\n' "[OK] Linked ${link} -> ${target}"
  fi

  # Only edit the user's own zsh profile (macOS default shell).
  if [ -f "$profile" ] && grep -Fq '.local/bin' "$profile" 2>/dev/null; then
    printf '%s\n' "[OK] ${profile} already puts ~/.local/bin on PATH"
  else
    {
      printf '\n'
      printf '%s\n' '# Added by SlopNet install.sh so you can type `slopnet` from any folder.'
      printf '%s\n' "$path_line"
    } >> "$profile"
    printf '%s\n' "[OK] Appended PATH line to ${profile}"
    printf '%s\n' "     Open a new Terminal window, or run: source ${profile}"
  fi

  printf '%s\n' "You can now type: slopnet doctor"
  printf '%s\n' "(If that says command not found, run: source ${profile})"
}

install_user_path

if [ -x ./doctor.sh ]; then
  ./doctor.sh
else
  printf '%s\n' 'Armed. Run ./doctor.sh after Wave 1 completes.'
fi
