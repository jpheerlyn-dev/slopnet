#!/usr/bin/env bash
# Applies the JSON rulesets in this folder to the current GitHub repo —
# the SERVER-side wall: enforced by GitHub itself, immune to --no-verify,
# hook tampering, and force pushes.
#
# Needs: the gh CLI, logged in, with admin rights on this repo.
#   ./rulesets/apply-rulesets.sh          apply every ruleset here
#   ./rulesets/apply-rulesets.sh --check  list what is already active
#
# Plain truth about plans: GitHub ENFORCES rulesets on public repos for
# free; on private repos enforcement needs a paid plan. Applying them on
# a free private repo saves the configuration but it will not bite until
# the repo goes public or the plan changes. doctor.sh tells you which
# state you are in.

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
    echo "No rulesets active on $repo. Run ./rulesets/apply-rulesets.sh to raise the wall."
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
