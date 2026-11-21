#!/usr/bin/env bash
# Table-driven test for .claude/hooks/protect-paths.sh. Exits non-zero on any mismatch.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HOOK="$ROOT/.claude/hooks/protect-paths.sh"
command -v jq >/dev/null || { echo "jq required"; exit 1; }
TMP=$(mktemp -d) || exit 1
TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo/reference/GrappleMap" "$TMP/repo/tests/golden" "$TMP/repo/tests/goldenish" "$TMP/repo/src"
ln -s tests/golden "$TMP/repo/link"
P=$TMP/repo
fail=0
total=0
# check <allow|block> <field> <path>
check() {
	local want=$1 field=$2 path=$3 out got
	out=$(jq -n --arg p "$path" "{tool_input:{$field:\$p}}" | CLAUDE_PROJECT_DIR="$P" bash "$HOOK" 2>&1)
	if printf '%s' "$out" | grep -Eq '"permissionDecision": *"deny"'; then got=block; else got=allow; fi
	[ -n "$out" ] && [ "$got" = allow ] && got="crash: $out"
	total=$((total + 1))
	[ "$got" = "$want" ] || { fail=$((fail + 1)); echo "FAIL want=$want got=$got: $field=$path"; }
}
# --- blocked ---
check block file_path reference/GrappleMap/x
check block file_path ./reference/GrappleMap/x
check block file_path "$P/reference/GrappleMap/x"
check block file_path "$P/./reference/GrappleMap/x"
check block file_path "$P//reference///GrappleMap/x"
check block file_path src/../tests/golden/a.png
check block file_path "$P/src/../tests/golden/a.png"
check block file_path link/a.png
check block file_path tests/golden/new/dir/a.png
check block notebook_path reference/GrappleMap/n.ipynb
check block notebook_path link/n.ipynb
# --- allowed ---
check allow file_path src/x.odin
check allow file_path reference_notes.md
check allow file_path tests/goldenish/x
check allow file_path "$P/src/x.odin"
check allow file_path /tmp/x
check allow file_path reference/GrappleMapX/x
check allow notebook_path src/n.ipynb
echo "protect-paths: $((total - fail))/$total passed"
[ "$fail" -eq 0 ]
