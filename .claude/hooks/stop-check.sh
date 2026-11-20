#!/usr/bin/env bash
# Stop: run check + fast tests. Block completion on failure (once per stop cycle).
source "$(dirname "$0")/_common.sh"
# Already continued because of this hook: let Claude stop and report the failure instead of looping.
[ "$(jqr '.stop_hook_active // false')" = "true" ] && exit 0
ls src/*.odin >/dev/null 2>&1 || exit 0
out=$(./build.sh check 2>&1 && ./build.sh test 2>&1)
if [ $? -ne 0 ]; then
	tail=$(printf '%s' "$out" | tail -40)
	jq -n --arg r "Not done: ./build.sh check/test failed. Fix and re-run.
$tail" '{decision:"block",reason:$r}'
fi
exit 0
