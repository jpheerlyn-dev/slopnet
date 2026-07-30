#!/bin/sh
# Blocks OS droppings, caches, and logs from ever being committed.
# Default mode checks staged paths; --all checks every tracked path (CI use).

set -f

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 1

fail() {
  printf 'RULE: %s\nWHY:  %s\nFIX:  %s\n' "$1" "$2" "$3"
  exit 1
}

summarize() {
  awk 'NR<=3 { s = s (NR > 1 ? ", " : "") $0; n++ } NR > 3 { n++ }
       END { if (n > 3) printf "%s and %d more", s, n - 3; else printf "%s", s }'
}

is_junk() {
  case $1 in
    .DS_Store|*/.DS_Store|Thumbs.db|*/Thumbs.db|*.pyc|*.swp|*.log|__pycache__/*|*/__pycache__/*|node_modules/*|*/node_modules/*|.idea/*|*/.idea/*) return 0 ;;
  esac
  return 1
}

if [ "${1:-}" = "--all" ]; then
  hits=$(git ls-files -z | tr '\0' '\n' | while IFS= read -r p; do
    is_junk "$p" && printf '%s\n' "$p"
  done)
else
  hits=$(git diff --cached --diff-filter=d --name-only -z | tr '\0' '\n' | while IFS= read -r p; do
    is_junk "$p" && printf '%s\n' "$p"
  done)
fi

if [ -n "$hits" ]; then
  fail "$(printf '%s\n' "$hits" | summarize) are junk files that must never be committed." \
    "Junk files bloat the repo, leak local paths, and cause pointless conflicts." \
    "Unstage with git rm --cached <file>; .gitignore already ignores these."
fi

exit 0
