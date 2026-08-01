#!/bin/sh
# Every shell script this app ships has to parse.
#
# Five of them did not. One bad edit left a literal "\n+" at the start of a
# line in slopnet-vps-chat.sh and four others, so the assistant, the coding-app
# setup, the build helper and the project helper all died on a syntax error the
# moment they ran. Nothing caught it: the existing check reads the *remote*
# payload each script sends, never the script itself.
failed=0
for script in packaging/*.sh checks/*.sh; do
  [ -f "$script" ] || continue
  if ! bash -n "$script" 2>/dev/null; then
    echo "FAILED to parse: $script"
    bash -n "$script" 2>&1 | head -2
    failed=1
  fi
done
[ "$failed" = 0 ] && echo "every shipped shell script parses"
exit "$failed"
