#!/usr/bin/env bash
# GrappleMap-Odin build driver. Usage: ./build.sh <target> [args]
set -euo pipefail
cd "$(dirname "$0")"

COLLECTION="-collection:app=src"
VET="-vet -strict-style -warnings-as-errors"
OUT="build"
BIN="$OUT/grapplemap"
TEST_PKGS=(src src/core src/ui src/editor tests/fidelity)
# Odin dirs formatted and fmt-checked besides src/ (bench/ only once it exists).
FMT_DIRS=(src tests/fidelity bench)

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

# core-trig-check: `core` computes atan2/sin/cos only with its correctly rounded `cr_*` functions, never with
# `math.atan2`/`math.sin`/`math.cos` or the libm (ADR 0003, amendment #161).
cmd_core_trig_check() {
	if grep -nE '(^|[^A-Za-z0-9_])math\.(atan2|sin|cos)[a-z0-9_]*[[:space:]]*\(' src/core/*.odin; then
		echo "src/core must use cr_atan2/cr_sin/cr_cos, not math.atan2/sin/cos (ADR 0003, amendment #161)" >&2
		return 1
	fi
}

cmd_check() {
	cmd_changelog_check
	cmd_core_trig_check
	odin check src $COLLECTION $VET
	odin check tests/fidelity $COLLECTION $VET -no-entry-point
}

cmd_fmt() {
	local d
	for d in "${FMT_DIRS[@]}"; do
		[ -d "$d" ] && odinfmt -w "$d"
	done
	return 0
}

cmd_fmt_check() {
	local bad=0 f re
	re="^($(IFS='|'; echo "${FMT_DIRS[*]}"))/"
	for f in $(odin_files | grep -E "$re" || true); do
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
		# Leaks and bad frees fail the test, not only a log line (#151).
		# shellcheck disable=SC2046
		odin test "$pkg" $COLLECTION $VET -debug $(sanitize_flag) -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -out:"$OUT/test-$(basename "$pkg")"
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

# oracle [--sample]|--full|--update-full-hashes|--test|--images: runs the oracle dumper (tools/oracle, #34, #35) in
# Docker; --sample is the default (spec, "UX / behaviour").
# --full dumps the whole original DB to build/oracle/full/ (wiped first, so reruns give the same bytes) and checks it
# against tests/fixtures/oracle/FULL.sha256 when that exists; --update-full-hashes rewrites FULL.sha256 instead.
# --sample dumps the blocks of tools/oracle/sample.tsv and rewrites tests/fixtures/oracle/ (every file but
# FULL.sha256; images/ is never touched) plus MANIFEST.sha256. --test dumps tools/oracle/dump/testdata/*.txt and
# diffs each against its committed expected directory. --images renders the positions of tools/oracle/images.tsv
# with the original's ImageMaker into tests/fixtures/oracle/images/ (+ meta.json) and rewrites MANIFEST.sha256.
# Not part of `ci`: it needs Docker (amd64 image); PNGs also depend on Mesa (ADR 0002), so never in CI.
ORACLE_IMAGE="grapplemap-oracle"
ORACLE_TESTDATA="tools/oracle/dump/testdata"
ORACLE_FIXTURES="tests/fixtures/oracle"
ORACLE_IMAGES_LIST="tools/oracle/images.tsv"

oracle_image() {
	command -v docker >/dev/null || { echo "error: docker not found; ./build.sh oracle needs Docker" >&2; return 1; }
	docker info >/dev/null 2>&1 || { echo "error: cannot reach the Docker daemon (is it running?)" >&2; return 1; }
	echo "building the oracle image (cached after the first time; the first build takes minutes)..." >&2
	# ORACLE_BUILD_FLAGS (empty by default): extra `docker build` flags; the oracle workflow passes the layer cache.
	# shellcheck disable=SC2086
	docker build --quiet --platform linux/amd64 ${ORACLE_BUILD_FLAGS:-} -f tools/oracle/Dockerfile -t "$ORACLE_IMAGE" . >/dev/null
}

oracle_run() { docker run --rm --platform linux/amd64 -u "$(id -u):$(id -g)" "$@"; }

# oracle_dump OUT [dumper options]: dumps the original DB to OUT (wiped first).
oracle_dump() {
	local out="$1" commit mounts=()
	shift
	# sample.tsv is mounted only for --sample (a missing file would make Docker create a root-owned directory).
	[ "${1:-}" = --sample ] && mounts=(-v "$PWD/tools/oracle/sample.tsv:/sample.tsv:ro")
	oracle_image
	commit=$(git -C reference/GrappleMap rev-parse HEAD) || { echo "error: reference/GrappleMap not initialised" >&2; return 1; }
	rm -r -f "$out"
	mkdir -p "$out"
	oracle_run -v "$PWD/$out:/out" ${mounts[@]+"${mounts[@]}"} "$ORACLE_IMAGE" \
		grapplemap-oracle-dump /oracle/GrappleMap.txt /out --versions /oracle/VERSIONS --commit "$commit" "$@"
}

# oracle_full [update]: with "update", rewrites FULL.sha256; otherwise checks the dump against it when it exists
# (diff of the whole list: same file set and hashes).
oracle_full() {
	local out="$OUT/oracle/full" hashes="$ORACLE_FIXTURES/FULL.sha256"
	oracle_dump "$out"
	(cd "$out" && sha256sum -- *) >"$out.sha256"
	cat "$out.sha256"
	if [ "${1:-}" = update ]; then
		mkdir -p "$ORACLE_FIXTURES"
		cp "$out.sha256" "$hashes"
		echo "wrote $hashes"
	elif [ -f "$hashes" ]; then
		diff "$hashes" "$out.sha256" || { echo "FAIL: the full dump differs from $hashes" >&2; return 1; }
		echo "ok   full dump matches $hashes"
	fi
}

# The sample is dumped to build/ first, so a failing dumper never leaves tests/fixtures/oracle/ half written.
oracle_sample() {
	local out="$OUT/oracle/sample"
	oracle_dump "$out" --sample /sample.tsv
	mkdir -p "$ORACLE_FIXTURES"
	find "$ORACLE_FIXTURES" -maxdepth 1 -type f ! -name FULL.sha256 -delete
	cp "$out"/* "$ORACLE_FIXTURES"/
	oracle_manifest
}

# Every fixture but the manifests, images/ included (written by --images only), in C-locale path order.
oracle_manifest() {
	(cd "$ORACLE_FIXTURES" && find . -type f ! -name '*.sha256' | sed 's|^\./||' | LC_ALL=C sort \
		| while read -r f; do sha256sum -- "$f"; done >MANIFEST.sha256 && cat MANIFEST.sha256)
}

# oracle_images_check DIR [manifest]: DIR holds exactly one p<node>-480x360.png per row of images.tsv plus meta.json,
# meta.json lists exactly those PNGs and the blocks of images.tsv in its order; with "manifest", MANIFEST.sha256 also
# lists every file of DIR (as images/<file>) with its current hash.
oracle_images_check() {
	local dir="$1" rows files pngs listed line f
	rows=$(tail -n +2 "$ORACLE_IMAGES_LIST" | grep -c .) || true
	[ -f "$dir/meta.json" ] || { echo "FAIL images: no $dir/meta.json" >&2; return 1; }
	files=$(cd "$dir" && find . -type f ! -name meta.json | sed 's|^\./||' | LC_ALL=C sort)
	pngs=$(printf '%s\n' "$files" | grep -x 'p[0-9]*-480x360\.png') || true
	listed=$(jq -r '.images[].file' "$dir/meta.json" | LC_ALL=C sort)
	if [ "$files" != "$pngs" ] || [ "$(printf '%s\n' "$pngs" | grep -c .)" -ne "$rows" ]; then
		echo "FAIL images: expected $rows p<node>-480x360.png + meta.json in $dir, got: $files" >&2
		return 1
	fi
	[ "$pngs" = "$listed" ] || { echo "FAIL images: meta.json lists '$listed', $dir has '$pngs'" >&2; return 1; }
	[ "$(jq -r '.images[].block' "$dir/meta.json")" = "$(tail -n +2 "$ORACLE_IMAGES_LIST" | cut -f1)" ] \
		|| { echo "FAIL images: the blocks of meta.json differ from $ORACLE_IMAGES_LIST" >&2; return 1; }
	[ "${2:-}" = manifest ] || return 0
	for f in meta.json $pngs; do
		line="$(cd "$dir" && sha256sum -- "$f" | cut -d' ' -f1)  images/$f"
		grep -qxF "$line" "$ORACLE_FIXTURES/MANIFEST.sha256" \
			|| { echo "FAIL images: MANIFEST.sha256 does not list images/$f with its hash" >&2; return 1; }
	done
	echo "ok   images: $rows PNGs + meta.json, listed in MANIFEST.sha256"
}

# Rendered in build/ first, then tests/fixtures/oracle/images/ is rewritten from scratch. GALLIUM_DRIVER=softpipe:
# OSMesa's default llvmpipe writes 4-byte pixels into the OSMESA_RGB (3-byte) buffer ImageMaker uses, and its output
# changes from run to run and with the host's SIMD width (tools/oracle/README.md, "Reference images").
oracle_images() {
	local out="$OUT/oracle/images" commit
	oracle_image
	commit=$(git -C reference/GrappleMap rev-parse HEAD) || { echo "error: reference/GrappleMap not initialised" >&2; return 1; }
	rm -r -f "$out"
	mkdir -p "$out"
	oracle_run -e GALLIUM_DRIVER=softpipe -v "$PWD/$out:/out" -v "$PWD/$ORACLE_IMAGES_LIST:/images.tsv:ro" "$ORACLE_IMAGE" \
		grapplemap-images --db /oracle/GrappleMap.txt --list /images.tsv --out /out --versions /oracle/VERSIONS \
		--commit "$commit"
	oracle_images_check "$out" # before touching the fixtures
	rm -r -f "$ORACLE_FIXTURES/images"
	mkdir -p "$ORACLE_FIXTURES/images"
	cp "$out"/* "$ORACLE_FIXTURES/images/"
	oracle_manifest
	oracle_images_check "$ORACLE_FIXTURES/images" manifest
}

oracle_test() {
	local f name out fail=0 n=0 status expect_fail sample_args
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
		# <name>.sample.tsv next to <name>.txt (often a symlink to basic.txt): run that case with --sample.
		sample_args=()
		[ -f "$ORACLE_TESTDATA/$name.sample.tsv" ] && sample_args=(--sample "/testdata/$name.sample.tsv")
		oracle_run -v "$PWD/$ORACLE_TESTDATA:/testdata:ro" -v "$PWD/$out:/out" "$ORACLE_IMAGE" \
			grapplemap-oracle-dump "/testdata/$name.txt" /out ${sample_args[@]+"${sample_args[@]}"} 2>"$out.stderr" || status=$?
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
	--update-full-hashes) oracle_full update ;;
	--sample | "") oracle_sample ;;
	--test) oracle_test ;;
	--images) oracle_images ;;
	*) echo "usage: ./build.sh oracle [--sample]|--full|--update-full-hashes|--test|--images (default: --sample)" >&2; return 2 ;;
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
	echo "usage: ./build.sh {setup|check|changelog-check [dir]|fmt|fmt-check|debug|release|run|test|test-golden|bench|ci|worktree <branch>|worktree-remove <branch>|space-id <branch>|oracle [--sample]|--full|--update-full-hashes|--test|--images}"
	exit 2
	;;
esac
