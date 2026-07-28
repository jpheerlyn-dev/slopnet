#!/bin/sh
# Blocks banned, backup-style, and sloppy file and directory names.
# Default mode checks staged paths; --all checks every tracked path (CI use).

set -f

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 1
cd "$root" || exit 1

fail() {
  printf 'RULE: %s\nWHY:  %s\nFIX:  %s\n' "$1" "$2" "$3"
  exit 1
}

summarize() {
  awk 'NR<=3 { s = s (NR > 1 ? ", " : "") $0; n++ } NR > 3 { n++ }
       END { if (n > 3) printf "%s and %d more", s, n - 3; else printf "%s", s }'
}

all=0
[ "${1:-}" = "--all" ] && all=1

globs=""
[ -f banned-names.txt ] && globs=$(grep -v -E '^[[:space:]]*(#|$)' banned-names.txt || true)

violates() {
  nm_path=$1
  nm_base=${nm_path##*/}
  case $nm_base in
    README.md|AGENTS.md|HUMANS.md|MAP.md|SLOPNET.md|LICENSE|LOG.md|PROTECTED.txt|MANIFEST.sha256|Makefile|Dockerfile) return 1 ;;
  esac
  case $nm_path in
    *" "*) return 0 ;;
  esac
  nm_lowbase=$(printf '%s' "$nm_base" | tr 'A-Z' 'a-z')
  case $nm_lowbase in
    *.bak|*.orig|*.tmp) return 0 ;;
  esac
  nm_oldifs=$IFS
  IFS='/'
  # shellcheck disable=SC2086
  set -- $nm_path
  IFS=$nm_oldifs
  nm_last=$#
  nm_n=0
  for nm_seg do
    nm_n=$((nm_n + 1))
    nm_low=$(printf '%s' "$nm_seg" | tr 'A-Z' 'a-z')
    # Test the stem (segment minus extensions) so "report-final.md" is
    # caught just like an extensionless "report-final".
    nm_stem=${nm_low%%.*}
    case $nm_stem in
      *untitled|*temp|*tmp|*misc|*stuff|*copy|*new-folder|*-old|*_old|*-final|*_final|*-v2|*_v2|*"(1)") return 0 ;;
    esac
    if [ "$nm_n" -lt "$nm_last" ]; then
      case $nm_seg in
        *[!a-z0-9._-]*) return 0 ;;
      esac
    fi
  done
  if [ -n "$globs" ]; then
    # shellcheck disable=SC2086
    for nm_g in $globs; do
      case $nm_path in
        $nm_g) return 0 ;;
      esac
    done
  fi
  return 1
}

if [ "$all" -eq 1 ]; then
  hits=$(git ls-files -z | tr '\0' '\n' | while IFS= read -r p; do
    violates "$p" && printf '%s\n' "$p"
  done)
else
  hits=$(git diff --cached --name-only -z | tr '\0' '\n' | while IFS= read -r p; do
    violates "$p" && printf '%s\n' "$p"
  done)
fi

if [ -n "$hits" ]; then
  fail "$(printf '%s\n' "$hits" | summarize) break the naming law (spaces, banned words, backup suffixes, or non-lowercase directories)." \
    "Messy names make files unfindable and hide which version is the real one." \
    "Rename to one clear lowercase hyphenated name and restage; the operator owns all naming."
fi

exit 0
