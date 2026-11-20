#!/usr/bin/env bash
# PreToolUse(Edit|Write): block writes to reference/ and tests/golden/.
source "$(dirname "$0")/_common.sh"
f=$(jqr '.tool_input.file_path // empty')
[ -z "$f" ] && exit 0
rel="${f#"$PWD"/}"
case "$rel" in
reference/* | tests/golden/*)
	deny_pretool "Writes to reference/ and tests/golden/ are blocked. Golden images change only via './build.sh test-golden --update' when the user asks."
	;;
esac
exit 0
