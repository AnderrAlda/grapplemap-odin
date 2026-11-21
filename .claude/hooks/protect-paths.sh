#!/usr/bin/env bash
# PreToolUse(Edit|Write|NotebookEdit): block writes to reference/GrappleMap/ and tests/golden/.
# The path is normalized first (absolute or relative, `./`, `..`, repeated `/`, symlinks).
# Tests: tests/hooks/protect-paths.test.sh.
source "$(dirname "$0")/_common.sh"
f=$(jqr '.tool_input.file_path // .tool_input.notebook_path // empty')
[ -z "$f" ] && exit 0
if is_protected_path "$f"; then
	deny_pretool "Writes to reference/GrappleMap/ (read-only original) and tests/golden/ are blocked. Golden images change only via './build.sh test-golden --update' when the user asks."
fi
exit 0
