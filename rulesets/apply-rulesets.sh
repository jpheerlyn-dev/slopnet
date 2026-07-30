#!/usr/bin/env bash
# Applies the JSON rulesets in this folder to the current GitHub repo —
# the SERVER-side check: enforced by GitHub itself, immune to --no-verify,
# hook tampering, and force pushes.
#
# Needs: the gh CLI, logged in, with admin rights on this repo.
#   ./rulesets/apply-rulesets.sh          apply every ruleset here
#   ./rulesets/apply-rulesets.sh --check  list what is already active
#
# Plain truth, verified against the API on 2026-07-28:
#   * BRANCH rulesets (required checks, no force-push, no deletion) work
#     on any public repo for free. This is the important one.
#   * PUSH rulesets (blocking junk paths/extensions/big files at the
#     server) are ORG-OWNED repos only — GitHub refuses them on
#     user-owned repos, public or private: "Source only org-owned repos
#     can have push rules". Nothing you can configure changes that.
#     Until this repo lives in an organisation, those same rules are
#     enforced by checks/junk.sh + checks/naming.sh locally and in CI,
#     which is why SlopNet never relied on the push check alone.

set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)

repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || {
  echo "This needs the gh CLI, logged in, run inside the repo."
  exit 1
}

if [ "${1:-}" = "--check" ]; then
  active=$(gh api "repos/$repo/rulesets" --jq '.[].name' 2>/dev/null || true)
  if [ -n "$active" ]; then
    echo "Active rulesets on $repo:"
    printf '  %s\n' $active
  else
    echo "No rulesets active on $repo. Run ./rulesets/apply-rulesets.sh to turn the checks on."
  fi
  exit 0
fi

for f in "$here"/*.json; do
  name=$(basename "$f")
  if gh api "repos/$repo/rulesets" --method POST --input "$f" >/dev/null 2>/tmp/slopnet-ruleset-err; then
    echo "[OK] applied $name"
  else
    echo "[!!] GitHub refused $name:"
    sed 's/^/     /' /tmp/slopnet-ruleset-err
    echo "     Common reasons: the ruleset already exists (delete or edit it"
    echo "     under Settings -> Rules), this plan does not support that rule"
    echo "     type yet, or the token lacks admin rights."
  fi
done
