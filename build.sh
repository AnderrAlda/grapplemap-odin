#!/usr/bin/env bash
# GrappleMap-Odin build driver. Usage: ./build.sh <target> [args]
set -euo pipefail
cd "$(dirname "$0")"

COLLECTION="-collection:app=src"
VET="-vet -strict-style -warnings-as-errors"
OUT="build"
BIN="$OUT/grapplemap"
TEST_PKGS=(src src/core src/ui src/editor)

# AddressSanitizer: Linux and macOS. Skipped on macOS CI runners, where the Odin-bundled
# LLVM and Apple's ASan runtime disagree on the ASan ABI version (link error).
sanitize_flag() {
	case "$(uname -s)" in
	Linux) echo "-sanitize:address" ;;
	Darwin) [ -n "${CI:-}" ] || echo "-sanitize:address" ;;
	*) echo "" ;;
	esac
}

odin_files() { git ls-files '*.odin' 2>/dev/null || find src -name '*.odin'; }

cmd_setup() {
	git config core.hooksPath .githooks
	chmod +x .githooks/* .claude/hooks/*.sh 2>/dev/null || true
	echo "Git hooks activated (core.hooksPath=.githooks)."
	git submodule update --init || echo "WARN: could not init submodules (offline?); run: git submodule update --init"
	command -v odin >/dev/null || echo "WARN: odin not found; install $(cat .odin-version) (see README)."
	command -v odinfmt >/dev/null || echo "WARN: odinfmt not found (build it from github.com/DanielGavin/ols)."
	command -v jq >/dev/null || echo "WARN: jq not found (needed by Claude Code hooks)."
}

# changelog-check [dir]: every fragment in changelog.d/ (README.md excluded) must be non-empty, start with a Keep a
# Changelog heading and use only known headings (#98). Format check only.
cmd_changelog_check() {
	local dir="${1:-changelog.d}" f bad=0 first
	for f in "$dir"/*.md; do
		[ -e "$f" ] || continue
		[ "$(basename "$f")" = "README.md" ] && continue
		first=$(grep -m1 -v '^[[:space:]]*$' "$f" || true)
		if [ -z "$first" ]; then
			echo "changelog fragment $f is empty" >&2
			bad=1
		elif ! [[ "$first" =~ ^###\ (Added|Changed|Deprecated|Removed|Fixed|Security)$ ]]; then
			echo "changelog fragment $f must start with a '### <Added|Changed|Deprecated|Removed|Fixed|Security>' heading" >&2
			bad=1
		fi
		if grep -E '^### ' "$f" | grep -q -v -E '^### (Added|Changed|Deprecated|Removed|Fixed|Security)$'; then
			echo "changelog fragment $f has an unknown '###' heading" >&2
			bad=1
		fi
	done
	return $bad
}

cmd_check() {
	cmd_changelog_check
	odin check src $COLLECTION $VET
}

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
	# Git hooks (pre-push) and the Stop hook export GIT_DIR & co.; every git call below would hit the real repo (#111).
	local v
	while IFS= read -r v; do unset "$v"; done < <(git rev-parse --local-env-vars)
	mkdir -p "$OUT"
	bash tests/hooks/guard-bash.test.sh
	bash tests/hooks/protect-paths.test.sh
	bash tests/changelog/fragments.test.sh
	bash tests/worktree/worktree.test.sh
	# The sandbox regression test runs this function nested; the nested run skips it and the Odin packages.
	[ -n "${GM_IN_SANDBOX_REGRESSION:-}" ] && return 0
	bash tests/lib/sandbox.test.sh
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
	# Base dir comes from the main worktree (<main>/.git -> <main> -> parent), not from $PWD, so running this
	# from another worktree gives the same path.
	local common main base dir
	common="$(git rev-parse --path-format=absolute --git-common-dir)"
	main="$(dirname "$common")"
	base="$(dirname "$main")/grapplemap-odin-wt"
	dir="$base/${branch//\//-}"
	mkdir -p "$base"
	if git show-ref --verify --quiet "refs/heads/$branch"; then
		git worktree add "$dir" "$branch"
	else
		git worktree add -b "$branch" "$dir" origin/main
	fi
	git -C "$dir" submodule update --init || echo "WARN: could not init submodules in $dir (offline?)"
	echo "Worktree ready: $dir"
}

# worktree-remove <branch>: removes the worktree of <branch> and the local branch, only if the worktree and its submodules
# have no changes (untracked included; ignored build outputs do not count). Works from any worktree: paths come from
# `git worktree list --porcelain`, not from $PWD. --force is needed because git refuses to remove worktrees with submodules.
cmd_worktree_remove() {
	local branch="${1:?usage: ./build.sh worktree-remove <branch>}" wt="" path="" line
	case "$branch" in
	main* | master*) echo "error: refusing to remove protected branch '$branch'" >&2; return 1 ;;
	esac
	while IFS= read -r line; do
		case "$line" in
		"worktree "*) path="${line#worktree }" ;;
		"branch refs/heads/$branch") wt="$path" ;;
		esac
	done < <(git worktree list --porcelain)
	if [ -z "$wt" ]; then
		if git show-ref --verify --quiet "refs/heads/$branch"; then
			echo "error: branch '$branch' has no worktree; nothing removed" >&2
		else
			echo "error: branch '$branch' does not exist; nothing removed" >&2
		fi
		return 1
	fi
	if [ "$wt" = "$(git worktree list --porcelain | sed -n '1s/^worktree //p')" ]; then
		echo "error: '$wt' is the main worktree; nothing removed" >&2
		return 1
	fi
	case "$PWD/" in
	"$wt"/*) echo "error: build.sh was run from inside '$wt'; run this from another worktree. Nothing removed" >&2; return 1 ;;
	esac
	local dirty sub_dirty
	dirty=$(git -C "$wt" status --short --untracked-files=all --ignore-submodules=none) || return 1
	sub_dirty=$(git -C "$wt" submodule foreach --recursive --quiet 'git status --short --untracked-files=all | sed "s|^|$displaypath: |"') || return 1
	if [ -n "$dirty$sub_dirty" ]; then
		echo "error: worktree '$wt' has uncommitted changes; nothing removed:" >&2
		[ -z "$dirty" ] || printf '%s\n' "$dirty" >&2
		[ -z "$sub_dirty" ] || { echo "submodules:" >&2; printf '%s\n' "$sub_dirty" >&2; }
		return 1
	fi
	git worktree remove --force "$wt"
	git worktree prune
	git branch -D "$branch"
	echo "Removed worktree $wt and branch $branch"
}

# space-id <branch>: stable Herdr space id ("sp" + 32 hex) derived from the branch name, so a worker relaunched for the
# same branch lands in the same space. Used by /orchestrate as the herdr.space label.
cmd_space_id() {
	local branch="${1:?usage: ./build.sh space-id <branch>}" hash
	hash=$(printf '%s' "$branch" | git hash-object --stdin) || return 1
	printf 'sp%s\n' "${hash:0:32}"
}

# oracle --full|--test: runs the oracle dumper (tools/oracle, #34) in Docker. --full dumps the whole original DB to
# build/oracle/full/ (wiped first, so reruns give the same bytes); --test dumps tools/oracle/dump/testdata/*.txt and
# diffs each against its committed expected directory. Not part of `ci`: it needs Docker (amd64 image).
ORACLE_IMAGE="grapplemap-oracle"
ORACLE_TESTDATA="tools/oracle/dump/testdata"

oracle_image() {
	command -v docker >/dev/null || { echo "error: docker not found; ./build.sh oracle needs Docker" >&2; return 1; }
	docker info >/dev/null 2>&1 || { echo "error: cannot reach the Docker daemon (is it running?)" >&2; return 1; }
	echo "building the oracle image (cached after the first time; the first build takes minutes)..." >&2
	docker build --quiet --platform linux/amd64 -f tools/oracle/Dockerfile -t "$ORACLE_IMAGE" . >/dev/null
}

oracle_run() { docker run --rm --platform linux/amd64 -u "$(id -u):$(id -g)" "$@"; }

oracle_full() {
	local out="$OUT/oracle/full" commit
	oracle_image
	commit=$(git -C reference/GrappleMap rev-parse HEAD) || { echo "error: reference/GrappleMap not initialised" >&2; return 1; }
	rm -r -f "$out"
	mkdir -p "$out"
	oracle_run -v "$PWD/$out:/out" "$ORACLE_IMAGE" \
		grapplemap-oracle-dump /oracle/GrappleMap.txt /out --versions /oracle/VERSIONS --commit "$commit"
	(cd "$out" && sha256sum -- *)
}

oracle_test() {
	local f name out fail=0 n=0 status expect_fail
	oracle_image
	for f in "$ORACLE_TESTDATA"/*.txt; do
		name=$(basename "$f" .txt)
		out="$OUT/oracle/test/$name"
		rm -r -f "$out"
		mkdir -p "$out"
		n=$((n + 1))
		# A DB the original rejects is expected to fail: its expected directory holds only meta.json (with errors).
		status=0
		expect_fail=0
		[ -f "$ORACLE_TESTDATA/$name/graph.ndjson" ] || expect_fail=1
		oracle_run -v "$PWD/$ORACLE_TESTDATA:/testdata:ro" -v "$PWD/$out:/out" "$ORACLE_IMAGE" \
			grapplemap-oracle-dump "/testdata/$name.txt" /out 2>"$out.stderr" || status=$?
		if { [ "$status" -ne 0 ] && [ "$expect_fail" -eq 0 ]; } || { [ "$status" -eq 0 ] && [ "$expect_fail" -eq 1 ]; }; then
			echo "FAIL $name: dumper exit status $status (expected $([ "$expect_fail" -eq 1 ] && echo non-zero || echo 0))" >&2
			cat "$out.stderr" >&2
			fail=1
		elif ! diff -r "$ORACLE_TESTDATA/$name" "$out"; then
			echo "FAIL $name: output differs from $ORACLE_TESTDATA/$name/" >&2
			fail=1
		else
			echo "ok   $name"
		fi
	done
	[ "$n" -gt 0 ] || { echo "error: no $ORACLE_TESTDATA/*.txt" >&2; return 1; }
	return $fail
}

cmd_oracle() {
	case "${1:-}" in
	--full) oracle_full ;;
	--test) oracle_test ;;
	--sample | --images | --update-full-hashes) echo "error: ./build.sh oracle $1 arrives with #35" >&2; return 2 ;;
	*) echo "usage: ./build.sh oracle --full|--test" >&2; return 2 ;;
	esac
}

target="${1:-}"
[ $# -gt 0 ] && shift
case "$target" in
setup) cmd_setup ;;
check) cmd_check ;;
changelog-check) cmd_changelog_check "$@" ;;
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
worktree-remove) cmd_worktree_remove "$@" ;;
space-id) cmd_space_id "$@" ;;
oracle) cmd_oracle "$@" ;;
*)
	echo "usage: ./build.sh {setup|check|changelog-check [dir]|fmt|fmt-check|debug|release|run|test|test-golden|bench|ci|worktree <branch>|worktree-remove <branch>|space-id <branch>|oracle --full|--test}"
	exit 2
	;;
esac
