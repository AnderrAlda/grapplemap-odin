#!/usr/bin/env bash
# PreToolUse(Bash): block git commit/push on main and destructive commands.
#
# The command is split into segments (on && || ; | & and newlines) and each segment is judged on its own,
# so `git push origin feat && git log main` is not confused with a push to main. Git global options
# (-C <dir>, -c k=v, --git-dir=..., --no-pager, ...) are skipped before reading the subcommand.
#
# Known limits (fail-closed unless noted): quotes are deleted, not parsed, so a separator inside a quoted string
# (e.g. `;` in a commit message) or a message line that starts with a dangerous command over-blocks. Fail-open and
# accepted: variable expansion, command substitution as an argument, git aliases.
# Tests: tests/hooks/guard-bash.test.sh.
source "$(dirname "$0")/_common.sh"
cmd=$(jqr '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0
branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")

# Skipped before the real command: env assignments, shell keywords and transparent wrappers.
is_wrapper() {
	[[ $1 == *=* || $1 == env || $1 == command || $1 == exec || $1 == time || $1 == nohup || $1 == xargs ||
		$1 == timeout || $1 == nice || $1 == then || $1 == do || $1 == else || $1 == elif || $1 == if ||
		$1 == while || $1 == until || $1 == '!' || $1 == '{' || $1 == '(' ]]
}

# check_git <args...>: args after the `git` word.
check_git() {
	local t
	# Skip global options.
	while [ $# -gt 0 ]; do
		case $1 in
		-C | -c | --git-dir | --work-tree | --config-env | --exec-path | --namespace | --super-prefix) shift $(($# < 2 ? $# : 2)) ;;
		-*) shift ;;
		*) break ;;
		esac
	done
	local sub=${1:-}
	[ $# -gt 0 ] && shift
	if [ "$branch" = "main" ] && { [ "$sub" = commit ] || [ "$sub" = push ]; }; then
		deny_pretool "On 'main': commits and pushes are blocked. Create a branch first (git switch -c feat/...)."
	fi
	case $sub in
	push)
		for t in "$@"; do
			case $t in
			--force* | --delete | --mirror | --all)
				deny_pretool "Destructive or forbidden command blocked (force push, delete/mirror/all push)."
				;;
			--*) ;;
			-*[fd]*)
				deny_pretool "Destructive or forbidden command blocked (force push, delete push)."
				;;
			+* | :*)
				deny_pretool "Destructive or forbidden command blocked (forced or delete refspec)."
				;;
			main | refs/heads/main | *:main | *:refs/heads/main)
				deny_pretool "Pushing to main is blocked. Push a feature branch and merge the PR on GitHub."
				;;
			esac
		done
		;;
	reset)
		for t in "$@"; do
			[ "$t" = "--hard" ] && deny_pretool "Destructive command blocked (git reset --hard)."
		done
		;;
	clean)
		for t in "$@"; do
			case $t in
			--force) deny_pretool "Destructive command blocked (git clean --force)." ;;
			--*) ;;
			-*f*) deny_pretool "Destructive command blocked (git clean -f)." ;;
			esac
		done
		;;
	esac
}

# check_rm <args...>: blocks recursive + force in any spelling.
check_rm() {
	local t rec=0 force=0
	for t in "$@"; do
		case $t in
		--recursive) rec=1 ;;
		--force) force=1 ;;
		--*) ;;
		-*)
			[[ $t == *[rR]* ]] && rec=1
			[[ $t == *f* ]] && force=1
			;;
		esac
	done
	[ $rec = 1 ] && [ $force = 1 ] && deny_pretool "Destructive command blocked (recursive forced rm)."
}

check_segment() {
	local -a w
	read -r -a w <<<"$1"
	# Drop leading wrappers/keywords together with their options (env -u X, xargs -n1, timeout 5, ...).
	while [ ${#w[@]} -gt 0 ]; do
		if is_wrapper "${w[0]}"; then
			w=("${w[@]:1}")
		elif [[ ${w[0]} == -* || ${w[0]} =~ ^[0-9]+[smhd]?$ ]] && [ "$stripped" = 1 ]; then
			# Options of the wrapper just removed; those taking a separate argument also drop it.
			case ${w[0]} in -u | -C | -S | -n | -I | -L | -P | -a | -s | -k) w=("${w[@]:1}") ;; esac
			w=("${w[@]:1}")
		else
			break
		fi
		stripped=1
	done
	stripped=0
	[ ${#w[@]} -eq 0 ] && return 0
	local first=${w[0]#\\}
	first=${first##*/}
	case $first in
	sudo) deny_pretool "Privilege escalation blocked (sudo)." ;;
	bash | sh | zsh | dash | eval)
		# `bash -c "<cmd>"`, `eval <cmd>`: judge the inner command (quotes are already stripped).
		local -a inner=("${w[@]:1}")
		while [ ${#inner[@]} -gt 0 ] && [[ ${inner[0]} == -* ]]; do inner=("${inner[@]:1}"); done
		[ ${#inner[@]} -gt 0 ] && check_segment "${inner[*]}"
		;;
	git) check_git "${w[@]:1}" ;;
	rm) check_rm "${w[@]:1}" ;;
	gh)
		[ "${w[1]:-}" = "pr" ] && [ "${w[2]:-}" = "merge" ] &&
			deny_pretool "gh pr merge is blocked: merging is always done by the user."
		;;
	esac
	return 0
}
stripped=0

set -f # no globbing while splitting words
# Hook-skipping flag, wherever it appears.
if printf '%s' "$cmd" | grep -Eq '(^|[[:space:]])--no-verify([[:space:]=]|$)'; then
	deny_pretool "Skipping git hooks (--no-verify) is blocked."
fi
# Segments: quote characters are deleted first (so a quoted argument before a flag keeps the flag visible and
# a quoted "main" is seen), then the command is split on separators, backticks and parens so that `$(...)`
# and `find -exec` expose the inner command; `bash -c`/`eval` are judged recursively. tr (not sed \n) for macOS.
cmd=${cmd// -exec / ; }
cmd=${cmd// -execdir / ; }
while IFS= read -r seg; do
	check_segment "$seg"
done < <(printf '%s\n' "$cmd" | tr -d "\"'" | tr ';|&`()' '\n')
exit 0
