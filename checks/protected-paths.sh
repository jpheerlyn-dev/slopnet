#!/bin/sh
# Blocks commits that touch operator-sealed paths listed in PROTECTED.txt.
# Default mode checks staged paths; --all is a no-op (protection is about changes).

[ "${1:-}" = "--all" ] && exit 0

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

[ -f PROTECTED.txt ] || exit 0
prefixes=$(grep -v -E '^[[:space:]]*(#|$)' PROTECTED.txt || true)
[ -n "$prefixes" ] || exit 0

hits=$(git diff --cached --name-only -z | tr '\0' '\n' | while IFS= read -r p; do
  # shellcheck disable=SC2086
  for pre in $prefixes; do
    # Quoted removal is literal: if the prefix comes off, the path is sealed.
    if [ "${p#"$pre"}" != "$p" ]; then
      printf '%s\n' "$p"
      break
    fi
  done
done)

if [ -n "$hits" ]; then
  fail "$(printf '%s\n' "$hits" | summarize) sit under a sealed path from PROTECTED.txt that agents must not change." \
    "Sealed paths are the operator's building blocks; silent edits there break the whole build." \
    "Unstage with git rm --cached <file> and ask the operator before touching that path."
fi

exit 0
