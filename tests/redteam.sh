#!/usr/bin/env bash

set -u
set -o pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 1
source_root=$(cd "$script_dir/.." && pwd) || exit 1
tmp_parent=${TMPDIR:-/tmp}
tmp=$(mktemp -d "$tmp_parent/slopnet-redteam.XXXXXX") || exit 1
trap 'rm -rf -- "$tmp"' EXIT HUP INT TERM

fail_setup() {
  printf 'REDTEAM SETUP FAILED: %s\n' "$1" >&2
  exit 1
}

if ! tar -C "$source_root" \
  --exclude='./.git' \
  --exclude='./build' \
  --exclude='./LOG.md' \
  --exclude='./.slopnet' \
  --exclude='./.DS_Store' \
  --exclude='*/.DS_Store' \
  -cf - . | tar -C "$tmp" -xf -; then
  fail_setup 'could not copy the template into the temporary workspace.'
fi

cd "$tmp" || fail_setup 'could not enter the temporary workspace.'
command -v python3 >/dev/null 2>&1 || fail_setup 'python3 is required for the CLI attacks.'
git init -q || fail_setup 'git init failed.'
git config user.name 'SlopNet Redteam' || fail_setup 'could not set the test author.'
git config user.email 'redteam@example.invalid' || fail_setup 'could not set the test email.'

install_rc=0
./install.sh >/dev/null 2>&1 || install_rc=$?
if [[ ! -f .git/hooks/pre-commit || ! -f .git/hooks/post-commit ]] || \
  ! grep -Fq '# slopnet-armed' .git/hooks/pre-commit || \
  ! grep -Fq '# slopnet-armed' .git/hooks/post-commit; then
  fail_setup "./install.sh did not arm both hooks (exit $install_rc)."
fi

git add -A || fail_setup 'could not stage the baseline.'
if ! git commit -m 'redteam baseline' >/dev/null 2>&1; then
  fail_setup 'the legitimate baseline commit was blocked.'
fi
baseline=$(git rev-parse HEAD) || fail_setup 'could not record the baseline commit.'

score=0

reset_workspace() {
  git reset --hard "$baseline" >/dev/null 2>&1 || return 1
  git clean -fdx >/dev/null 2>&1 || return 1
}

commit_attack() {
  git commit -m 'redteam attack' >/dev/null 2>&1
}

commit_bypass() {
  git commit --no-verify -m 'redteam bypass' >/dev/null 2>&1
}

write_aws_attack() {
  local aws_head='AKIA'
  local aws_tail='ABCDEFGHIJKLMNOP'
  printf '%s%s%s\n' 'AWS_KEY=' "$aws_head" "$aws_tail" > config.py
  git add config.py
}

verify_manifest() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -c MANIFEST.sha256 >/dev/null 2>&1
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c MANIFEST.sha256 >/dev/null 2>&1
  else
    return 1
  fi
}

attack_1() {
  printf '%s\n' 'junk' > .DS_Store || return 1
  git add -f .DS_Store || return 1
  ! commit_attack
}

attack_2() {
  mkdir -p __pycache__ || return 1
  printf '%s\n' 'junk' > __pycache__/x.pyc || return 1
  git add -f __pycache__/x.pyc || return 1
  ! commit_attack
}

attack_3() {
  printf '%s\n' 'debug' > debug.log || return 1
  git add -f debug.log || return 1
  ! commit_attack
}

attack_4() {
  local secret_tail=aaaaaaaaaaaaaaaaaaaaaaaa
  printf '%s%s\n' 'API_KEY=sk-' "$secret_tail" > .env || return 1
  git add -f .env || return 1
  ! commit_attack
}

attack_5() {
  write_aws_attack || return 1
  ! commit_attack
}

attack_6() {
  local private_open='-----BEGIN'
  local private_rest=' PRIVATE KEY-----'
  printf '%s%s\n' "$private_open" "$private_rest" > deploy.pem || return 1
  printf '%s\n' 'fake' >> deploy.pem || return 1
  git add deploy.pem || return 1
  ! commit_attack
}

attack_7() {
  printf '%s\n' 'copy' > 'notes copy.md' || return 1
  git add 'notes copy.md' || return 1
  ! commit_attack
}

attack_8() {
  printf '%s\n' 'untitled' > untitled.txt || return 1
  git add untitled.txt || return 1
  ! commit_attack
}

attack_9() {
  mkdir -p 'New Folder' || return 1
  printf '%s\n' 'new' > 'New Folder/x.txt' || return 1
  git add 'New Folder/x.txt' || return 1
  ! commit_attack
}

attack_10() {
  printf '%s\n' 'report' > report_final_v2.md || return 1
  git add report_final_v2.md || return 1
  ! commit_attack
}

attack_11() {
  printf '%s\n' 'backup' > main.py.bak || return 1
  git add main.py.bak || return 1
  ! commit_attack
}

attack_12() {
  mkdir -p MyStuff || return 1
  printf '%s\n' 'readme' > MyStuff/readme.md || return 1
  git add MyStuff/readme.md || return 1
  ! commit_attack
}

attack_13() {
  {
    printf '%s\n' 'def handle():'
    printf '%s\n' '    try:'
    printf '%s\n' '        pass'
    printf '%s%s\n' '    except' ':'
    printf '%s\n' '        pass'
  } > handler.py || return 1
  git add handler.py || return 1
  ! commit_attack
}

attack_14() {
  local catch_word='catch'
  local catch_args=' (e) '
  local catch_open='{'
  local catch_close='}'
  printf '%s%s%s%s\n' "$catch_word" "$catch_args" "$catch_open" "$catch_close" > api.js || return 1
  git add api.js || return 1
  ! commit_attack
}

attack_15() {
  local short_word='simplified'
  local version_word='version'
  local time_words='for now'
  printf '%s %s %s\n' "# $short_word" "$version_word" "$time_words" > service.py || return 1
  git add service.py || return 1
  ! commit_attack
}

attack_16() {
  git rm -r --cached -q register >/dev/null 2>&1 || return 1
  rm -rf -- register || return 1
  printf '%s\n' 'source' > missing-register.py || return 1
  git add missing-register.py || return 1
  if ! commit_attack; then
    return 0
  fi
  git ls-files --error-unmatch "register/$(date +%F).md" >/dev/null 2>&1
}

attack_17() {
  printf '%s\n' 'sealed/' >> PROTECTED.txt || return 1
  mkdir -p sealed || return 1
  printf '%s\n' 'sealed' > sealed/core.py || return 1
  git add PROTECTED.txt sealed/core.py || return 1
  ! commit_attack
}

attack_18() {
  write_aws_attack || return 1
  if ! commit_bypass; then
    return 0
  fi
  ! sh checks/secrets.sh --all >/dev/null 2>&1
}

attack_19() {
  printf '\n# tamper\n' >> checks/junk.sh || return 1
  git add checks/junk.sh || return 1
  if ! commit_bypass; then
    return 0
  fi
  ! verify_manifest
}

attack_20() {
  printf '%s\n' 'odd' > 'weird name (1).txt' || return 1
  git add 'weird name (1).txt' || return 1
  ! commit_attack
}

attack_21() {
  # The CLI must refuse an orbit whose name breaks the naming law,
  # and must create nothing.
  if python3 ./slopnet orbit new 'Bad Name' >/dev/null 2>&1; then
    return 1
  fi
  [ ! -e '../Bad Name' ]
}

attack_22() {
  # The MCP server must survive a call to a tool that does not exist:
  # respond with isError, keep serving, exit cleanly. A crashed guard
  # is an open gate.
  local out
  out=$(printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"drop_all_walls","arguments":{}}}' \
    '{"jsonrpc":"2.0","id":3,"method":"ping"}' \
    | python3 ./slopnet mcp) || return 1
  printf '%s' "$out" | grep -q '"isError": true' || return 1
  printf '%s' "$out" | grep -c '"jsonrpc"' | grep -qx '3'
}

attack_23() {
  # The CLI's own check verb must report staged junk exactly like the
  # hook would — one door, one law.
  printf 'x' > .DS_Store || return 1
  git add -f .DS_Store || return 1
  ! python3 ./slopnet check >/dev/null 2>&1
}

attack_24() {
  # Garbage on stdin must not kill the MCP server: it skips the junk
  # line and still answers the ping that follows.
  local out
  out=$(printf '%s\n' \
    'this is not json {{{' \
    '{"jsonrpc":"2.0","id":1,"method":"ping"}' \
    | python3 ./slopnet mcp) || return 1
  printf '%s' "$out" | grep -q '"id": 1'
}

attack_25() {
  # A tool call missing its required argument must come back as isError,
  # and the server must keep serving afterwards. A crashed guard is an
  # open gate.
  local out
  out=$(printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"sign_register","arguments":{}}}' \
    '{"jsonrpc":"2.0","id":3,"method":"ping"}' \
    | python3 ./slopnet mcp) || return 1
  printf '%s' "$out" | grep -q '"isError": true' || return 1
  printf '%s' "$out" | grep -c '"jsonrpc"' | grep -qx '3'
}

record_landed() {
  local number=$1
  local label=$2
  printf 'LANDED %s %s\n' "$number" "$label"
  {
    printf '\n## Redteam — attack %s landed\n\n' "$number"
    printf -- '- %s landed in the temporary workspace; inspect the failing check before changing this script.\n' "$label"
  } >> register/PENDING_OPERATOR.md
  printf 'SCORE: %s/25\n' "$score"
  exit 1
}

run_attack() {
  local number=$1
  local label=$2
  local function=$3
  if "$function"; then
    score=$((score + 1))
    printf 'BLOCKED %s %s\n' "$number" "$label"
  else
    record_landed "$number" "$label"
  fi
  reset_workspace || fail_setup "could not reset after attack $number."
}

run_attack 1 '.DS_Store' attack_1
run_attack 2 '__pycache__/x.pyc' attack_2
run_attack 3 'debug.log' attack_3
run_attack 4 '.env secret' attack_4
run_attack 5 'AWS key' attack_5
run_attack 6 'private-key block' attack_6
run_attack 7 'notes copy.md' attack_7
run_attack 8 'untitled.txt' attack_8
run_attack 9 'New Folder/x.txt' attack_9
run_attack 10 'report_final_v2.md' attack_10
run_attack 11 'main.py.bak' attack_11
run_attack 12 'MyStuff/readme.md' attack_12
run_attack 13 'naked except' attack_13
run_attack 14 'empty catch' attack_14
run_attack 15 'shortcut phrase' attack_15
run_attack 16 'register auto-restore' attack_16
run_attack 17 'sealed path' attack_17
run_attack 18 'AWS key (CI-layer)' attack_18
run_attack 19 'manifest tamper (CI-layer)' attack_19
run_attack 20 'weird name (1).txt' attack_20
run_attack 21 'orbit bad name (CLI)' attack_21
run_attack 22 'MCP unknown tool' attack_22
run_attack 23 'staged junk via CLI check' attack_23
run_attack 24 'MCP garbage input (fuzz)' attack_24
run_attack 25 'MCP missing argument (fuzz)' attack_25

printf 'SCORE: %s/25\n' "$score"
[[ "$score" -eq 25 ]]
