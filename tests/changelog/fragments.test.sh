#!/usr/bin/env bash
# Tests for `./build.sh changelog-check [dir]` (#98): fragments need a known Keep a Changelog heading.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
fail=0
expect() { # expect <0|1> <name>
	local want=$1 name=$2 got=0
	"$ROOT/build.sh" changelog-check "$TMP" >/dev/null 2>&1 || got=1
	if [ "$got" -eq "$want" ]; then echo "ok   $name"; else echo "FAIL $name (exit $got, wanted $want)"; fail=1; fi
}
reset() { rm -f "$TMP"/*.md; }

reset; printf '%s\n' '# Fragments' >"$TMP/README.md"; expect 0 "README only"
reset; printf '%s\n' '### Added' '- thing (#1).' >"$TMP/1-a.md"; expect 0 "valid Added"
reset; printf '%s\n' '### Added' '- a' '### Fixed' '- b' >"$TMP/1-a.md"; expect 0 "two valid headings"
reset; printf '%s\n' '- thing (#1).' >"$TMP/1-a.md"; expect 1 "no heading"
reset; printf '%s\n' '### Stuff' '- thing' >"$TMP/1-a.md"; expect 1 "unknown heading"
reset; printf '%s\n' '### Added' '- ok' >"$TMP/1-a.md"; printf '%s\n' 'x' >"$TMP/2-b.md"; expect 1 "one good, one bad"
reset; : >"$TMP/1-a.md"; expect 1 "empty fragment"
reset; printf '%s\n' '- orphan' '### Added' '- x' >"$TMP/1-a.md"; expect 1 "text before first heading"
exit $fail
