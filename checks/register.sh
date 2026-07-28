#!/bin/sh
# Ensures every commit day has a register day-file (the automatic paper-trail floor).
# Default mode creates and stages today's file if missing; --all requires the day-file
# for HEAD's author date to be tracked (CI use).

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 1
cd "$root" || exit 1

fail() {
  printf 'RULE: %s\nWHY:  %s\nFIX:  %s\n' "$1" "$2" "$3"
  exit 1
}

if [ "${1:-}" = "--all" ]; then
  d=$(git log -1 --format=%ad --date=short HEAD 2>/dev/null)
  [ -n "$d" ] || exit 1
  if git ls-files --error-unmatch "register/$d.md" >/dev/null 2>&1; then
    exit 0
  fi
  fail "no register/$d.md is tracked, but HEAD was authored on $d." \
    "The register is the project memory; a commit without a day-file breaks the trail." \
    "Create register/$d.md with a \"# Register - $d\" header and commit it."
fi

d=$(date +%F)
f="register/$d.md"
if [ ! -f "$f" ]; then
  printf '# Register — %s\n' "$d" > "$f" || exit 1
fi
if ! git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
  git add "$f" >/dev/null 2>&1 || exit 1
fi

exit 0
