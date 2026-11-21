#!/usr/bin/env bash
# Tests for `./build.sh worktree <branch>` (#31): the path must not depend on the current worktree.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
source "$ROOT/tests/lib/sandbox.sh"
sandbox_init
TMP=$SANDBOX
fail=0
check() { # check <name> <condition exit code>
	if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi
}
G() { sandbox_git "$@"; }

# Throwaway repo: bare origin + clone with origin/main. No network, no submodules.
G init -q --bare -b main "$TMP/origin.git"
G clone -q "$TMP/origin.git" "$TMP/work/main-checkout" 2>/dev/null
MAIN="$TMP/work/main-checkout"
# Safety guard before any write (commit/push/config): the repo must be the throwaway one, never the real one.
sandbox_assert_repo "$MAIN"
cp "$ROOT/build.sh" "$MAIN/build.sh"
G -C "$MAIN" add build.sh
G -C "$MAIN" commit -q -m init
G -C "$MAIN" push -q origin HEAD:main
G -C "$MAIN" fetch -q origin
G -C "$MAIN" branch -q -u origin/main 2>/dev/null
EXPECT_BASE="$TMP/work/grapplemap-odin-wt"

# From the main checkout.
out=$(cd "$MAIN" && ./build.sh worktree feat/one 2>&1)
rc=$?
check "main checkout: exit 0" "$rc"
[ -d "$EXPECT_BASE/feat-one" ]
check "main checkout: <parent>/grapplemap-odin-wt/feat-one" $?

# From inside that worktree (git-common-dir must still point at the main .git).
echo "common-dir from worktree: $(cd "$EXPECT_BASE/feat-one" && git rev-parse --path-format=absolute --git-common-dir)"
out=$(cd "$EXPECT_BASE/feat-one" && ./build.sh worktree fix/two 2>&1)
rc=$?
check "worktree: exit 0" "$rc"
[ -d "$EXPECT_BASE/fix-two" ]
check "worktree: same base dir, fix-two" $?
[ ! -e "$EXPECT_BASE/grapplemap-odin-wt" ]
check "worktree: no nested grapplemap-odin-wt" $?

# Existing local branch is reused.
G -C "$MAIN" branch -q chore/three origin/main
out=$(cd "$EXPECT_BASE/feat-one" && ./build.sh worktree chore/three 2>&1)
rc=$?
check "existing branch: exit 0" "$rc"
[ -d "$EXPECT_BASE/chore-three" ]
check "existing branch: dir created" $?

# A failing git worktree add shows git's error and exits non-zero (branch already checked out).
out=$(cd "$MAIN" && ./build.sh worktree chore/three 2>&1)
rc=$?
[ "$rc" -ne 0 ]
check "failure: non-zero exit" $?
printf '%s' "$out" | grep -qiE "already|fatal"
check "failure: git error visible" $?
exit $fail
