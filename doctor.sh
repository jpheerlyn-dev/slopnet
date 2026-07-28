#!/usr/bin/env bash

set -u

root=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "$root" ]] || ! cd "$root"; then
  printf '%s\n' '[!!] This is not a Git repository. Run ./doctor.sh from the repository root.'
  exit 1
fi

failed=0

ok() {
  printf '[OK] %s\n' "$1"
}

bad() {
  printf '[!!] %s\n' "$1"
  failed=1
}

unknown() {
  printf "[??] Can't check from here — %s\n" "$1"
}

instruction='Turn on branch protection: Settings → Branches → require the slopnet checks. This is the wall nobody can climb.'

hooks_ok=1
for hook in .git/hooks/pre-commit .git/hooks/post-commit; do
  if [[ ! -f "$hook" ]] || ! grep -Fq '# slopnet-armed' "$hook" 2>/dev/null; then
    hooks_ok=0
  fi
done
if [[ "$hooks_ok" -eq 1 ]]; then
  ok 'Hooks are armed.'
else
  bad 'Hooks are not armed — Run ./install.sh.'
fi

if [[ -e .slopnet/bin/lefthook && ! -e .slopnet/fallback ]]; then
  ok 'Fast engine running.'
else
  ok 'Fallback mode — slower, same protection.'
fi

checks=(
  checks/secrets.sh
  checks/protected-paths.sh
  checks/naming.sh
  checks/junk.sh
  checks/slop-lint.sh
  checks/register.sh
)
law_ok=1
for check in "${checks[@]}"; do
  if [[ ! -f "$check" || ! -x "$check" ]]; then
    law_ok=0
  fi
done
if [[ "$law_ok" -eq 1 ]]; then
  ok 'All six law checks are present.'
else
  bad 'Some law checks are missing or not executable.'
fi

manifest_ok=0
if [[ -f MANIFEST.sha256 ]]; then
  if command -v shasum >/dev/null 2>&1; then
    if shasum -a 256 -c MANIFEST.sha256 >/dev/null 2>&1; then
      manifest_ok=1
    fi
  elif command -v sha256sum >/dev/null 2>&1; then
    if sha256sum -c MANIFEST.sha256 >/dev/null 2>&1; then
      manifest_ok=1
    fi
  fi
fi
if [[ "$manifest_ok" -eq 1 ]]; then
  ok 'The manifest matches the machinery.'
else
  bad 'The manifest is missing or does not match the machinery.'
fi

if [[ -f .github/workflows/slopnet.yml ]]; then
  ok 'The CI workflow is present.'
else
  bad 'The CI workflow is missing.'
fi

if ! command -v gh >/dev/null 2>&1; then
  unknown "$instruction"
elif ! gh auth status >/dev/null 2>&1; then
  unknown "$instruction"
else
  repo_info=$(gh repo view --json nameWithOwner,defaultBranchRef \
    --jq '.nameWithOwner + "\n" + .defaultBranchRef.name' 2>/dev/null || true)
  repository=$(printf '%s\n' "$repo_info" | sed -n '1p')
  default_branch=$(printf '%s\n' "$repo_info" | sed -n '2p')

  if [[ -z "$repository" || -z "$default_branch" ]]; then
    unknown "$instruction"
  else
    # Rulesets are how GitHub protects branches now; the older
    # branches/*/protection endpoint cannot see them. Ask about rulesets
    # first, then fall back so older setups still report correctly.
    if required_checks=$(gh api "repos/$repository/rulesets?includes_parents=true" \
      --jq '.[].id' 2>/dev/null | while IFS= read -r ruleset_id; do
        gh api "repos/$repository/rulesets/$ruleset_id" \
          --jq 'select(.enforcement=="active") | .rules[]
                 | select(.type=="required_status_checks")
                 | .parameters.required_status_checks[].context' 2>/dev/null
      done) && [[ -n "$required_checks" ]]; then
      api_status=0
    elif required_checks=$(gh api "repos/$repository/branches/$default_branch/protection" \
      --jq '[ (.required_status_checks.contexts // []), ((.required_status_checks.checks // []) | map(.context)) ] | add | .[]' \
      2>/dev/null); then
      api_status=0
    else
      api_status=$?
      required_checks=''
    fi

    if [[ "$api_status" -ne 0 ]]; then
      bad "$instruction"
    else
      protection_ok=1
      for job in law manifest register-audit; do
        found=1
        while IFS= read -r required; do
          if [[ "$required" == "$job" || "$required" == "SlopNet / $job" ]]; then
            found=0
            break
          fi
        done <<< "$required_checks"
        if [[ "$found" -ne 0 ]]; then
          protection_ok=0
        fi
      done
      if [[ "$protection_ok" -eq 1 ]]; then
        ok 'The server wall requires all three SlopNet checks.'
      else
        bad "$instruction"
      fi
    fi
  fi
fi

register_ok=0
if [[ -d register ]]; then
  while IFS= read -r register_file; do
    if [[ "$register_file" =~ ^register/[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$ ]]; then
      register_ok=1
      break
    fi
  done < <(git ls-files 'register/*.md')
fi
if [[ "$register_ok" -eq 1 ]]; then
  ok 'The register has a tracked day-file.'
else
  bad 'The register has no tracked day-file.'
fi

exit "$failed"
