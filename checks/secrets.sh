#!/bin/sh
# Blocks leaked secrets and .env files from entering the repo.
# Default mode scans staged added lines; --all scans the whole tracked tree (CI use).

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

# 1. Environment files are never committable (only .env.example is allowed).
if [ "$all" -eq 1 ]; then
  env_hits=$(git ls-files -z | tr '\0' '\n' | grep -E '(^|/)\.env(\..+)?$' | grep -v -E '(^|/)\.env\.example$' || true)
else
  env_hits=$(git diff --cached --name-only -z | tr '\0' '\n' | grep -E '(^|/)\.env(\..+)?$' | grep -v -E '(^|/)\.env\.example$' || true)
fi
if [ -n "$env_hits" ]; then
  fail "$(printf '%s\n' "$env_hits" | summarize) must not be committed: .env files hold live secrets." \
    "Environment files stay in history forever and get scraped within minutes of a push." \
    "Unstage with git rm --cached <file> and keep secrets in a local, ignored .env."
fi

# 2. Use gitleaks when a binary is available; it reads .gitleaks.toml in the
#    repo root by itself when that config exists.
gl=""
if [ -x .slopnet/bin/gitleaks ]; then
  gl=.slopnet/bin/gitleaks
elif command -v gitleaks >/dev/null 2>&1; then
  gl=$(command -v gitleaks)
fi

if [ -n "$gl" ]; then
  if [ "$all" -eq 1 ]; then
    "$gl" detect --redact --no-banner >/dev/null 2>&1
  else
    "$gl" protect --staged --redact --no-banner >/dev/null 2>&1
  fi
  if [ $? -ne 0 ]; then
    fail "gitleaks found a likely secret in the changes under test." \
      "A committed secret is public forever and gets scraped within minutes." \
      "Remove and rotate the secret; run gitleaks yourself to see the exact file and line."
  fi
  exit 0
fi

# 3. Pure-shell fallback: a fixed set of high-signal secret patterns.
pat="AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36,}|sk-[A-Za-z0-9]{20,}|-----BEGIN( [A-Z]+)? PRIVATE KEY-----|(api[_-]?key|secret|token|passwd|password)[\"']?[[:space:]]*[:=][[:space:]]*[\"'][^\"']{12,}"

if [ "$all" -eq 1 ]; then
  hits=$(git grep -I -E -l -e "$pat" 2>/dev/null || true)
else
  hits=""
  if git diff --cached -U0 | grep '^+' | grep -v '^+++' | grep -qE "$pat"; then
    hits=$(git diff --cached --name-only -z | tr '\0' '\n' | while IFS= read -r f; do
      if git diff --cached -U0 -- "$f" | grep '^+' | grep -v '^+++' | grep -qE "$pat"; then
        printf '%s\n' "$f"
      fi
    done)
  fi
fi

if [ -n "$hits" ]; then
  fail "$(printf '%s\n' "$hits" | summarize) contain what looks like a committed secret." \
    "A committed secret is public forever and gets scraped within minutes." \
    "Remove and rotate the secret, and move it into a local, ignored .env file."
fi

exit 0
