#!/bin/sh
# Blocks silent error handlers and fake-work phrases in source code.
# Default mode scans staged added lines; --all scans whole tracked source files (CI use).
# Ideas reimplemented from scratch after the unlicensed "grain" project; no grain code here.

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

src_globs='*.py *.pyi *.js *.jsx *.ts *.tsx *.mjs *.cjs *.sh *.bash *.zsh *.rb *.go *.rs *.java *.c *.h *.cc *.hh *.cpp *.hpp *.cs *.php *.swift *.kt *.kts'

# Phrase literals are split so this script never matches its own pattern list.
re_except='except[[:space:]]*:[[:space:]]*(pass|\.\.\.)?[[:space:]]*$'
re_catch='catch[[:space:]]*(\([^)]*\))?[[:space:]]*\{[[:space:]]*\}'
phrases='simplified vers''ion|in a real impleme''ntation|placeholder implem''entation|left as an exer''cise|would norm''ally|for now, j''ust'
pat="$re_except|$re_catch|$phrases"

if [ "${1:-}" = "--all" ]; then
  # shellcheck disable=SC2086
  hits=$(git grep -I -i -E -l -e "$pat" -- $src_globs 2>/dev/null || true)
else
  hits=""
  # shellcheck disable=SC2086
  if git diff --cached -U0 -- $src_globs | grep '^+' | grep -v '^+++' | grep -q -i -E "$pat"; then
    # shellcheck disable=SC2086
    hits=$(git diff --cached --name-only -z -- $src_globs | tr '\0' '\n' | while IFS= read -r f; do
      if git diff --cached -U0 -- "$f" | grep '^+' | grep -v '^+++' | grep -q -i -E "$pat"; then
        printf '%s\n' "$f"
      fi
    done)
  fi
fi

if [ -n "$hits" ]; then
  fail "$(printf '%s\n' "$hits" | summarize) contain silent error handlers or shortcut phrases." \
    "Swallowed errors and fake work pass review, then explode in production." \
    "Handle the error honestly or write the real code, then restage the file."
fi

exit 0
