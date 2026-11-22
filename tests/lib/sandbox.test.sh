#!/usr/bin/env bash
# Regression test for #111 (shell tests must not inherit the hook's GIT_* environment).
#  1. sandbox_assert_repo aborts on repos outside $SANDBOX and on remote/foreign origins.
#  2. Positive control: a test that runs git without isolation DOES write through an inherited GIT_DIR;
#     the same probe after sandbox_init does not.
#  3. The whole shell-test suite (`./build.sh test`) run with GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE pointing at a
#     victim repo leaves the victim's config, refs and worktree list untouched.
# Recursion: step 3 runs `./build.sh test` with GM_IN_SANDBOX_REGRESSION=1, which makes cmd_test skip this
# test and the Odin packages in the nested run (they cannot touch git and would only slow it down).
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=tests/lib/sandbox.sh
source "$ROOT/tests/lib/sandbox.sh"
sandbox_init
fail=0
check() { # check <name> <condition exit code>
	if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi
}
OUTSIDE=""
sandbox_on_exit() {
	[ -n "$OUTSIDE" ] && rm -rf "$OUTSIDE"
	return $fail
}

# --- 1. sandbox_assert_repo ---
mkdir -p "$SANDBOX/outside"
OUTSIDE=$(mktemp -d) # a real temp dir outside $SANDBOX
sandbox_git init -q -b main "$SANDBOX/inside"
sandbox_git init -q -b main "$OUTSIDE/repo"
(sandbox_assert_repo "$SANDBOX/inside") 2>/dev/null
check "assert_repo: accepts repo inside sandbox" $?
(sandbox_assert_repo "$OUTSIDE/repo") 2>/dev/null
[ $? -eq 1 ]
check "assert_repo: aborts on repo outside sandbox" $?
(sandbox_assert_repo "$SANDBOX/outside") 2>/dev/null
[ $? -eq 1 ]
check "assert_repo: aborts on non-repo dir (GIT_CEILING stops discovery)" $?
git -C "$SANDBOX/inside" remote add origin "git@github.com:x/y.git"
(sandbox_assert_repo "$SANDBOX/inside") 2>/dev/null
[ $? -eq 1 ]
check "assert_repo: aborts on ssh origin" $?
git -C "$SANDBOX/inside" remote set-url origin "https://github.com/x/y.git"
(sandbox_assert_repo "$SANDBOX/inside") 2>/dev/null
[ $? -eq 1 ]
check "assert_repo: aborts on https origin" $?
git -C "$SANDBOX/inside" remote set-url origin "$OUTSIDE/repo"
(sandbox_assert_repo "$SANDBOX/inside") 2>/dev/null
[ $? -eq 1 ]
check "assert_repo: aborts on local origin outside sandbox" $?
git -C "$SANDBOX/inside" remote set-url origin "$SANDBOX/inside"
(sandbox_assert_repo "$SANDBOX/inside") 2>/dev/null
check "assert_repo: accepts local origin inside sandbox" $?
(GIT_DIR="$SANDBOX/inside/.git" sandbox_assert_repo "$SANDBOX/inside") 2>/dev/null
[ $? -eq 1 ]
check "assert_repo: aborts when GIT_DIR is set" $?
rm -rf "$OUTSIDE"

# --- victim repo (own sandbox state, never $ROOT) ---
VICTIM="$SANDBOX/victim"
sandbox_git init -q -b main "$VICTIM"
sandbox_git -C "$VICTIM" commit -q --allow-empty -m init
sandbox_git -C "$VICTIM" branch feat/x
sandbox_git init -q --bare -b main "$SANDBOX/victim-origin.git"
sandbox_git -C "$VICTIM" remote add origin "$SANDBOX/victim-origin.git"
sandbox_assert_repo "$VICTIM"
victim_state() {
	cksum <"$VICTIM/.git/config"
	git -C "$VICTIM" for-each-ref
	git -C "$VICTIM" worktree list --porcelain
}
BEFORE=$(victim_state)

# --- 2. positive control: an unisolated probe writes through an inherited GIT_DIR ---
PROBE="$SANDBOX/probe.sh"
cat >"$PROBE" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = isolated ]; then
	source "$2/tests/lib/sandbox.sh"
	sandbox_init
	git init -q "$SANDBOX/r"
fi
git config probe.touched yes
EOF
(cd "$SANDBOX" && GIT_DIR="$VICTIM/.git" GIT_WORK_TREE="$VICTIM" bash "$PROBE" raw 2>/dev/null)
[ "$(victim_state)" != "$BEFORE" ]
check "control: unisolated probe modifies the victim via GIT_DIR (the incident)" $?
git -C "$VICTIM" config --unset probe.touched
BEFORE=$(victim_state)
(cd "$SANDBOX" && GIT_DIR="$VICTIM/.git" GIT_WORK_TREE="$VICTIM" bash "$PROBE" isolated "$ROOT" 2>/dev/null)
[ "$(victim_state)" = "$BEFORE" ]
check "probe after sandbox_init leaves the victim untouched" $?

# --- 3. the whole suite under an inherited hook environment ---
# Never export the victim env unless it points inside the sandbox.
case $VICTIM in "$SANDBOX"/*) ;; *) echo "FATAL: victim outside sandbox" >&2; exit 1 ;; esac
(cd "$ROOT" && GM_IN_SANDBOX_REGRESSION=1 GIT_DIR="$VICTIM/.git" GIT_WORK_TREE="$VICTIM" \
	GIT_INDEX_FILE="$VICTIM/.git/index" ./build.sh test >"$SANDBOX/nested.log" 2>&1)
check "nested ./build.sh test passes under inherited GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE" $?
[ "$(victim_state)" = "$BEFORE" ]
check "victim config, refs and worktree list unchanged after the suite" $?
[ "$fail" -eq 0 ] || tail -30 "$SANDBOX/nested.log"
exit $fail
