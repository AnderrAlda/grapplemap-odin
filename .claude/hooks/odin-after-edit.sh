#!/usr/bin/env bash
# PostToolUse(Edit|Write): format the edited .odin file, then quick-check its package.
source "$(dirname "$0")/_common.sh"
f=$(jqr '.tool_input.file_path // empty')
case "$f" in *.odin) ;; *) exit 0 ;; esac
[ -f "$f" ] || exit 0
command -v odinfmt >/dev/null && odinfmt -w "$f" >/dev/null 2>&1
pkg=$(dirname "$f")
out=$(odin check "$pkg" -collection:app=src -vet -strict-style -warnings-as-errors -no-entry-point 2>&1)
if [ $? -ne 0 ]; then
	jq -n --arg r "odin check failed for $pkg:
$out" '{decision:"block",reason:$r}'
fi
exit 0
