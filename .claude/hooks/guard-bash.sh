#!/usr/bin/env bash
# PreToolUse(Bash): block git commit/push on main and destructive commands.
#
# The command is split into segments (on && || ; | & and newlines) and each segment is judged on its own,
# so `git push origin feat && git log main` is not confused with a push to main. Git global options
# (-C <dir>, -c k=v, --git-dir=..., --no-pager, ...) are skipped before reading the subcommand.
#
# It also blocks writes into reference/GrappleMap/ and tests/golden/: output redirection, tee, sed/perl -i, cp/mv/
# install/rsync, rm, truncate, touch, ln, chmod/chown, dd of=, patch, writing git subcommands (checkout, restore,
# apply, -C <protected dir> ...). Operands are normalized (`./`, `..`, `$PWD`, symlinks) and a preceding `cd` is
# tracked. Read-only use stays allowed. Edit/Write/NotebookEdit are covered by protect-paths.sh.
#
# Known limits (fail-closed unless noted): quotes are deleted, not parsed, so a separator inside a quoted string
# (e.g. `;` in a commit message) or a message line that starts with a dangerous command over-blocks. Fail-open and
# accepted: variable expansion (other than $PWD), command substitution as an argument, git aliases, globs
# (tests/gol*), and interpreters writing from inside scripts (python -c, node -e, awk system()).
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

# Directory the command is believed to run in: $PWD, or the target of a preceding `cd` (segments are judged in order).
vpwd=$PWD

# protected <token> [ancestors]: the word names reference/GrappleMap/ or tests/golden/ (normalized: `./`, `..`,
# `$PWD`, symlinks). A `-opt=path` / `of=path` prefix is stripped. With a second argument, `reference` and `tests`
# (parents that a delete or move would take along) count too. Unresolvable words (other `$`, `~`) fail open.
protected() {
	local t=$1 root
	t=${t#-*=}
	t=${t#of=}
	t=${t//\$\{PWD\}/$vpwd}
	t=${t//\$PWD/$vpwd}
	[[ -z $t || $t == *'$'* || $t == '~'* ]] && return 1
	is_protected_path "$t" "$vpwd" && return 0
	if [ -n "${2:-}" ]; then
		root=$(norm_path "$PWD" /)
		t=$(norm_path "$t" "$vpwd")
		[[ $t == "$root/reference" || $t == "$root/tests" ]] && return 0
	fi
	return 1
}

# check_writes <cmd> <args...>: block write commands whose operands name a protected path. Read-only use
# (cat, grep, sed -n, cp *from* reference/, git log/show) stays allowed.
check_writes() {
	local cmd=$1 t last="" inplace=0 prev=""
	shift
	local msg="Writes to reference/GrappleMap/ (read-only original) and tests/golden/ are blocked (golden images change only via './build.sh test-golden --update' when the user asks)."
	case $cmd in
	sed | perl)
		for t in "$@"; do
			[[ $t == --in-place* || ($t == -*i* && $t != --*) ]] && inplace=1
		done
		[ $inplace = 1 ] || return 0
		for t in "$@"; do protected "$t" && deny_pretool "$msg"; done
		;;
	cp | install | rsync | scp)
		for t in "$@"; do
			case $t in
			--target-directory=*) protected "$t" && deny_pretool "$msg" ;;
			-*) ;;
			*)
				[ "$prev" = -t ] && protected "$t" && deny_pretool "$msg"
				last=$t
				;;
			esac
			prev=$t
		done
		[ -n "$last" ] && protected "$last" && deny_pretool "$msg"
		;;
	mv | rm | unlink | rmdir)
		for t in "$@"; do protected "$t" ancestors && deny_pretool "$msg"; done
		;;
	tee | truncate | touch | ln | chmod | chown | chgrp | patch | dd | shred)
		for t in "$@"; do protected "$t" && deny_pretool "$msg"; done
		;;
	esac
}

# check_redirects <words...>: `>`, `>>`, `&>`, `2>`, `>|` followed by (or glued to) a protected target.
check_redirects() {
	local t target
	while [ $# -gt 0 ]; do
		t=$1
		shift
		if [[ $t =~ ^[0-9]*\>\>?(.*)$ ]]; then
			target=${BASH_REMATCH[1]}
			[ -z "$target" ] && target=${1:-}
			[ -n "$target" ] && protected "$target" &&
				deny_pretool "Writes to reference/GrappleMap/ (read-only original) and tests/golden/ are blocked (redirection)."
		fi
	done
}

# check_git <args...>: args after the `git` word.
check_git() {
	local t gdir=$vpwd
	# Skip global options.
	while [ $# -gt 0 ]; do
		case $1 in
		-C)
			[ -n "${2:-}" ] && gdir=$(norm_path "$2" "$gdir")
			shift $(($# < 2 ? $# : 2))
			;;
		-c | --git-dir | --work-tree | --config-env | --exec-path | --namespace | --super-prefix) shift $(($# < 2 ? $# : 2)) ;;
		-*) shift ;;
		*) break ;;
		esac
	done
	local sub=${1:-}
	[ $# -gt 0 ] && shift
	if [ "$branch" = "main" ] && { [ "$sub" = commit ] || [ "$sub" = push ]; }; then
		deny_pretool "On 'main': commits and pushes are blocked. Create a branch first (git switch -c feat/...)."
	fi
	# Writing subcommands: inside the protected trees (cwd or -C), or naming protected paths / --directory.
	case $sub in
	log | show | diff | status | rev-parse | rev-list | ls-files | ls-tree | cat-file | blame | describe | grep | \
		shortlog | show-ref | name-rev | merge-base | remote | config | submodule | help | version | "") ;;
	*)
		local wmsg="Writes to reference/GrappleMap/ (read-only original) and tests/golden/ are blocked (git $sub)."
		protected "$gdir" && deny_pretool "$wmsg"
		case $sub in
		checkout | restore | rm | mv | clean | reset | apply | stash | switch | commit | merge | rebase | am | cherry-pick | revert)
			for t in "$@"; do protected "$t" && deny_pretool "$wmsg"; done
			;;
		esac
		;;
	esac
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
	check_redirects "${w[@]}"
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
	cd)
		# Track the directory so that `cd reference/GrappleMap && rm x` is judged against it.
		if [ -n "${w[1]:-}" ] && [[ ${w[1]} != -* && ${w[1]} != *'$'* ]]; then
			vpwd=$(norm_path "${w[1]}" "$vpwd")
		fi
		;;
	sed | perl | cp | install | rsync | scp | mv | tee | truncate | touch | ln | chmod | chown | chgrp | patch | dd | shred | unlink | rmdir)
		check_writes "$first" "${w[@]:1}"
		;;
	rm)
		check_rm "${w[@]:1}"
		check_writes rm "${w[@]:1}"
		;;
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
cmd=${cmd//>|/>}
cmd=${cmd// -exec / ; }
cmd=${cmd// -execdir / ; }
while IFS= read -r seg; do
	check_segment "$seg"
done < <(printf '%s\n' "$cmd" | tr -d "\"'" | tr ';|&`()' '\n')
exit 0
