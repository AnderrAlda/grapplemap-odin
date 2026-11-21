#!/usr/bin/env bash
# Shared helpers for Claude Code hooks. Reads the hook JSON from stdin into $INPUT.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
INPUT=$(cat)
jqr() { printf '%s' "$INPUT" | jq -r "$1" 2>/dev/null; }
# deny_pretool <reason>: block a PreToolUse call.
deny_pretool() {
	jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
	exit 0
}

# norm_path <path> [base]: absolute, normalized path (`.`, `..`, repeated `/`; symlinks resolved when realpath
# exists). Relative paths are resolved against base (default $PWD). Does not need the path to exist.
norm_path() {
	local p=$1 base=${2:-$PWD}
	[[ $p == /* ]] || p="$base/$p"
	if realpath -m -- / >/dev/null 2>&1; then
		realpath -m -- "$p"
		return
	fi
	# Fallback (macOS without GNU realpath): walk the components, resolving symlinks with readlink.
	local -a out=()
	local seg cur hops=0 rest=$p tgt
	while [ -n "$rest" ]; do
		seg=${rest%%/*}
		[[ $rest == */* ]] && rest=${rest#*/} || rest=""
		case $seg in
		'' | .) continue ;;
		..)
			[ ${#out[@]} -gt 0 ] && unset 'out[${#out[@]}-1]'
			continue
			;;
		esac
		cur="/$(IFS=/ && printf '%s' "${out[*]-}")"
		cur="${cur%/}/$seg"
		if [ -L "$cur" ] && [ $hops -lt 40 ]; then
			hops=$((hops + 1))
			tgt=$(readlink "$cur")
			if [[ $tgt == /* ]]; then
				out=()
				rest="${tgt#/}${rest:+/$rest}"
			else
				rest="$tgt${rest:+/$rest}"
			fi
			continue
		fi
		out+=("$seg")
	done
	printf '/%s\n' "$(IFS=/ && printf '%s' "${out[*]-}")"
}

# is_protected_path <path> [base]: succeeds when the path is inside reference/GrappleMap/ or tests/golden/ of the
# project (or is one of those directories).
is_protected_path() {
	local root p r
	root=$(norm_path "$PWD" /)
	p=$(norm_path "$1" "${2:-$PWD}")
	for r in "$root/reference/GrappleMap" "$root/tests/golden"; do
		[[ $p == "$r" || $p == "$r"/* ]] && return 0
	done
	return 1
}
