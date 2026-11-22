#!/usr/bin/env bash
# Sourced (not executed) by the shell tests that run `git`. Guarantees they never touch the real repo (#111):
# git hooks (pre-push) export GIT_DIR & co., which would make every `git` call of a test hit the real repository.
#
# Usage:
#   source "$ROOT/tests/lib/sandbox.sh"
#   sandbox_init                      # $SANDBOX = fresh temp dir (physical path), repo env cleared
#   git init -q "$SANDBOX/repo"; sandbox_assert_repo "$SANDBOX/repo"   # before any write
#
# EXIT trap convention: the helper owns the EXIT trap. A test that needs extra cleanup/tripwires defines a
# function `sandbox_on_exit` (optional); it runs first, then $SANDBOX is removed, and a non-zero return
# from the function becomes the exit status of the test. Do not set your own `trap ... EXIT`.

_sandbox_fatal() {
	echo "FATAL: $*" >&2
	exit 1
}

# Unsets every variable git exports to its hooks (GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE, ...).
sandbox_clear_git_env() {
	local v
	while IFS= read -r v; do unset "$v"; done < <(git rev-parse --local-env-vars)
}

_sandbox_cleanup() {
	local rc=$?
	if declare -F sandbox_on_exit >/dev/null; then
		sandbox_on_exit || rc=$?
	fi
	[ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"
	exit "$rc"
}

sandbox_init() {
	sandbox_clear_git_env
	SANDBOX=$(mktemp -d) || _sandbox_fatal "mktemp failed"
	SANDBOX=$(cd "$SANDBOX" && pwd -P)
	export GIT_CEILING_DIRECTORIES="$SANDBOX"
	trap _sandbox_cleanup EXIT
}

# git with a fixed identity; local-path clones/submodules allowed.
sandbox_git() {
	git -c user.name=t -c user.email=t@t -c protocol.file.allow=always "$@"
}

# sandbox_assert_repo <dir>: aborts the test (exit 1) unless <dir> is a repo whose git-common-dir is inside
# $SANDBOX and whose origin (if any) is a local path inside $SANDBOX. Call before any commit/push/config.
sandbox_assert_repo() {
	local dir=${1:?usage: sandbox_assert_repo <dir>} common url
	[ -n "${SANDBOX:-}" ] || _sandbox_fatal "sandbox_init was not called"
	[ -z "${GIT_DIR:-}${GIT_WORK_TREE:-}" ] || _sandbox_fatal "GIT_DIR/GIT_WORK_TREE set in the test environment"
	common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) ||
		_sandbox_fatal "'$dir' is not a git repo"
	common=$(cd "$common" && pwd -P)
	case $common in
	"$SANDBOX"/*) ;;
	*) _sandbox_fatal "git-common-dir '$common' is outside $SANDBOX" ;;
	esac
	if url=$(git -C "$dir" remote get-url origin 2>/dev/null); then
		case $url in
		*://* | *@*:*) _sandbox_fatal "origin '$url' is a remote URL" ;;
		"$SANDBOX"/*) ;;
		*) _sandbox_fatal "origin '$url' is outside $SANDBOX" ;;
		esac
	fi
	return 0
}
