#!/usr/bin/env bash
# GrappleMap-Odin build driver. Usage: ./build.sh <target> [args]
set -euo pipefail
cd "$(dirname "$0")"

COLLECTION="-collection:app=src"
VET="-vet -strict-style -warnings-as-errors"
OUT="build"
BIN="$OUT/grapplemap"
TEST_PKGS=(src src/core src/ui src/editor)

sanitize_flag() {
	case "$(uname -s)" in
	Linux | Darwin) echo "-sanitize:address" ;;
	*) echo "" ;;
	esac
}

odin_files() { git ls-files '*.odin' 2>/dev/null || find src -name '*.odin'; }

cmd_setup() {
	git config core.hooksPath .githooks
	chmod +x .githooks/* .claude/hooks/*.sh 2>/dev/null || true
	echo "Git hooks activated (core.hooksPath=.githooks)."
	command -v odin >/dev/null || echo "WARN: odin not found; install $(cat .odin-version) (see README)."
	command -v odinfmt >/dev/null || echo "WARN: odinfmt not found (build it from github.com/DanielGavin/ols)."
	command -v jq >/dev/null || echo "WARN: jq not found (needed by Claude Code hooks)."
}

cmd_check() { odin check src $COLLECTION $VET; }

cmd_fmt() { odinfmt -w src; }

cmd_fmt_check() {
	local bad=0 f
	for f in $(odin_files | grep '^src/' || true); do
		if ! odinfmt -stdin <"$f" | diff -q - "$f" >/dev/null; then
			echo "needs formatting: $f"
			bad=1
		fi
	done
	return $bad
}

cmd_debug() {
	mkdir -p "$OUT"
	# shellcheck disable=SC2046
	odin build src $COLLECTION $VET -debug $(sanitize_flag) -out:"$BIN-debug"
}

cmd_release() {
	mkdir -p "$OUT"
	odin build src $COLLECTION $VET -o:speed -out:"$BIN"
}

cmd_run() {
	cmd_debug
	"$BIN-debug" "$@"
}

cmd_test() {
	mkdir -p "$OUT"
	local pkg
	for pkg in "${TEST_PKGS[@]}"; do
		[ -d "$pkg" ] || continue
		ls "$pkg"/*.odin >/dev/null 2>&1 || continue
		# shellcheck disable=SC2046
		odin test "$pkg" $COLLECTION $VET -debug $(sanitize_flag) -out:"$OUT/test-$(basename "$pkg")"
	done
}

cmd_test_golden() {
	[ -d tests/golden_runner ] || { echo "golden tests arrive in phase 3; nothing to run."; return 0; }
	odin test tests/golden_runner $COLLECTION $VET -define:GOLDEN_UPDATE="${1:-}" -out:"$OUT/test-golden"
}

cmd_bench() {
	[ -d bench ] && ls bench/*.odin >/dev/null 2>&1 || { echo "no benchmarks yet."; return 0; }
	odin run bench $COLLECTION -o:speed -out:"$OUT/bench"
}

cmd_ci() {
	cmd_fmt_check
	cmd_check
	cmd_test
	cmd_debug
	cmd_release
}

cmd_worktree() {
	local branch="${1:?usage: ./build.sh worktree <branch>}"
	local dir="../grapplemap-odin-wt/${branch//\//-}"
	mkdir -p ../grapplemap-odin-wt
	git worktree add -b "$branch" "$dir" origin/main 2>/dev/null || git worktree add "$dir" "$branch"
	echo "Worktree ready: $dir"
}

target="${1:-}"
[ $# -gt 0 ] && shift
case "$target" in
setup) cmd_setup ;;
check) cmd_check ;;
fmt) cmd_fmt ;;
fmt-check) cmd_fmt_check ;;
debug) cmd_debug ;;
release) cmd_release ;;
run) cmd_run "$@" ;;
test) cmd_test ;;
test-golden) cmd_test_golden "$@" ;;
bench) cmd_bench ;;
ci) cmd_ci ;;
worktree) cmd_worktree "$@" ;;
*)
	echo "usage: ./build.sh {setup|check|fmt|fmt-check|debug|release|run|test|test-golden|bench|ci|worktree <branch>}"
	exit 2
	;;
esac
