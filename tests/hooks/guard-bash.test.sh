#!/usr/bin/env bash
# Table-driven test for .claude/hooks/guard-bash.sh. Exits non-zero on any mismatch.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HOOK="$ROOT/.claude/hooks/guard-bash.sh"
command -v jq >/dev/null || { echo "jq required"; exit 1; }

# Fail-safe isolation. An inherited GIT_DIR (pointing at a linked worktree) makes `git init` below rewrite
# core.bare=true in the SHARED config of the real repo, so: clear all repo-redirecting env, forbid upward discovery,
# refuse to run if the scratch repo resolves inside the real one, and fail if the real .git/config changes.
while IFS= read -r v; do unset "$v"; done < <(git rev-parse --local-env-vars)
REAL_COMMON=$(cd "$ROOT" && cd "$(git rev-parse --git-common-dir)" && pwd -P) || { echo "no real repo"; exit 1; }
REAL_CONFIG_SUM=$(cksum <"$REAL_COMMON/config")
TMP=$(mktemp -d) || exit 1
TMP=$(cd "$TMP" && pwd -P)
export GIT_CEILING_DIRECTORIES="$TMP"
real_config_unchanged() { [ "$(cksum <"$REAL_COMMON/config")" = "$REAL_CONFIG_SUM" ]; }
cleanup() {
	real_config_unchanged || { echo "FATAL: real repo config ($REAL_COMMON/config) changed during the test"; exit 1; }
	rm -rf "$TMP"
}
trap cleanup EXIT
git init -q -b main "$TMP/repo"
if ! real_config_unchanged; then echo "FATAL: git init modified the real repo config"; exit 1; fi
SCRATCH_COMMON=$(cd "$TMP/repo" && cd "$(git rev-parse --git-common-dir)" && pwd -P)
case $SCRATCH_COMMON in
"$TMP"/repo/*) ;;
*) echo "FATAL: scratch repo not isolated (common dir: $SCRATCH_COMMON, real: $REAL_COMMON)"; exit 1 ;;
esac
git -C "$TMP/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$TMP/repo" branch feat/x

TMO=""
command -v timeout >/dev/null && TMO="timeout 10"
fail=0
total=0
# check <allow|block> <branch> <command>
check() {
	local want=$1 branch=$2 cmd=$3 out got
	git -C "$TMP/repo" switch -q "$branch"
	out=$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$TMP/repo" $TMO bash "$HOOK" 2>&1)
	# Any output that is not a deny decision (e.g. a crash message) must not count as allow.
	if [ -n "$out" ] && ! printf '%s' "$out" | grep -Eq '"permissionDecision": *"(deny|allow)"'; then
		fail=$((fail + 1)); total=$((total + 1)); echo "FAIL [$branch] hook crashed: $cmd: $out"; return
	fi
	if printf '%s' "$out" | grep -Eq '"permissionDecision": *"deny"'; then got=block; else got=allow; fi
	total=$((total + 1))
	if [ "$got" != "$want" ]; then
		fail=$((fail + 1))
		echo "FAIL [$branch] want=$want got=$got: $cmd"
	fi
}

F=feat/x
# --- allowed ---
check allow $F 'git push origin feat && git log main'
check allow $F 'git push -u origin feat/x'
check allow $F 'git push -u origin HEAD'
check allow $F 'git status; git log main..HEAD'
check allow $F 'git log --oneline main'
check allow $F 'git commit -m "feat: x"'
check allow $F 'git -C dir commit -m x'
check allow $F 'git -c core.pager=cat log'
check allow $F 'git --no-pager diff main'
check allow $F 'git reset --soft HEAD~1'
check allow $F 'git clean -n'
check allow $F 'rm -r dir'
check allow $F 'rm -f file'
check allow $F 'gh pr create --draft --title t --body b'
check allow $F 'gh pr view 3'
check allow $F 'hc list'
check allow $F './build.sh ci'
check allow $F 'git fetch origin main'
check allow $F 'git pull origin main'
check allow main 'git log main'
check allow main 'git status'
check allow main 'git switch -c feat/y'
# --- blocked: on main ---
check block main 'git commit -m x'
check block main 'git -C dir commit -m x'
check block main 'git push origin feat'
check block main 'ls && git commit -m x'
# --- blocked: push to main ---
check block $F 'git push origin main'
check block $F 'git push origin HEAD:main'
check block $F 'git push origin feat:main'
check block $F 'git push origin HEAD:refs/heads/main'
check block $F 'git push origin refs/heads/main'
check block $F 'git -C dir push origin main'
check block $F 'git push origin feat && git push origin main'
# --- blocked: force / delete / mirror / all ---
check block $F 'git push --force origin feat'
check block $F 'git push origin feat --force'
check block $F 'git push --force-with-lease origin feat'
check block $F 'git push -f origin feat'
check block $F 'git push -fu origin x'
check block $F 'git push -uf origin x'
check block $F 'git push origin x -f'
check block $F 'git push origin +feat'
check block $F 'git push origin :feat'
check block $F 'git push -d origin feat'
check block $F 'git push --delete origin feat'
check block $F 'git push --mirror'
check block $F 'git push --all'
check block $F 'git -C dir push -f origin x'
check block $F 'git -c k=v push --force origin x'
check block $F 'git --git-dir=.git push -f origin x'
check block $F 'git --no-pager push -f origin x'
check block $F 'ls | git push -f origin x'
# --- blocked: reset / clean / rm / sudo / merge / no-verify ---
check block $F 'git reset --hard'
check block $F 'git reset --hard HEAD~1'
check block $F 'git -C dir reset --hard'
check block $F 'git clean -f'
check block $F 'git clean -fd'
check block $F 'git clean -df'
check block $F 'git clean -x -f'
check block $F 'git clean --force'
check block $F 'rm -rf dir'
check block $F 'rm -fr dir'
check block $F 'rm -r -f dir'
check block $F 'rm -f -r dir'
check block $F 'rm -R -f dir'
check block $F 'rm -Rf dir'
check block $F 'rm --recursive --force dir'
check block $F 'rm -r --force dir'
check block $F 'rm --recursive -f dir'
check block $F 'ls && rm -rf dir'
check block $F 'sudo ls'
check block $F 'ls && sudo rm x'
check block $F 'gh pr merge 3'
check block $F 'gh pr merge --squash 3'
check block $F 'git commit --no-verify -m x'
check block $F 'git push --no-verify origin feat'

check allow $F 'git push -u origin fix/guard-main'
check allow $F 'git push origin feat 2>&1 | tail -3'
check block $F 'git --git-dir .git push -f origin x'
check block $F 'bash -c "git push --force origin x"'
check block $F "sh -c 'rm -rf x'"
check block $F 'bash -c "sudo ls"'
check block $F 'eval "git push origin main"'
check block $F 'find . -exec rm -rf {} +'
check block $F 'echo $(git push -f origin x)'
check block $F 'echo `git push -f origin x`'
check block $F '/usr/bin/git push -f origin x'
check block $F '/bin/rm -rf x'
check block $F 'if true; then git push -f origin x; fi'
check block $F 'timeout 5 git push -f origin x'
check block $F 'env -u X git push -f origin x'
check block $F 'xargs -n1 rm -rf'
check block $F 'nice sudo ls'
check block main 'bash -c "git commit -m x"'
check allow $F 'timeout 5 git log main'
check allow $F 'git -C "/some/dir" status'
check allow $F 'git -c "a=b c" log'
check allow $F 'git -C'
check allow $F 'hc send foo "git push origin main"'
check allow $F 'git commit -m "avoid git push -f"'
check block $F 'git push origin "feat/x" -f'
check block $F 'git push -u origin "feat/x" --force'
check block $F 'git push origin "main"'
check block $F "git push origin 'main'"
check block $F 'eval git push -f origin x'
check block $F '\git push -f origin x'
check block $F 'git -C "/x" push -f origin x'

# --- writes into reference/GrappleMap and tests/golden (#21) ---
mkdir -p "$TMP/repo/reference/GrappleMap/src" "$TMP/repo/tests/golden"
check block $F 'echo x > reference/GrappleMap/a'
check block $F 'echo x >> ./reference/GrappleMap/a'
check block $F 'echo x >reference/GrappleMap/a'
check block $F 'echo x &> tests/golden/a'
check block $F 'echo x 2> tests/golden/a'
check block $F 'echo x >| tests/golden/a'
check block $F 'echo x > "$PWD/tests/golden/a.png"'
check block $F 'sed -i s/a/b/ ./reference/GrappleMap/a'
check block $F 'sed -ni s/a/b/p reference/GrappleMap/a'
check block $F 'sed --in-place s/a/b/ reference/GrappleMap/a'
check block $F 'perl -pi -e s/a/b/ reference/GrappleMap/a'
check block $F 'cp a tests/golden/b.png'
check block $F 'cp -t tests/golden a'
check block $F 'mv a tests/golden/b.png'
check block $F 'mv tests/golden/a.png /tmp/x'
check block $F 'install a reference/GrappleMap/b'
check block $F 'rsync -a a tests/golden/'
check block $F 'rm tests/golden/x.png'
check block $F 'rm -r tests'
check block $F 'truncate -s 0 reference/GrappleMap/a'
check block $F 'touch tests/golden/a'
check block $F 'ln -sf a reference/GrappleMap/b'
check block $F 'chmod +x reference/GrappleMap/a'
check block $F 'dd if=/dev/zero of=tests/golden/a.png'
check block $F 'patch reference/GrappleMap/a < p.diff'
check block $F 'patch -d reference/GrappleMap -p1 < p.diff'
check block $F 'git apply --directory=reference/GrappleMap p.diff'
check block $F 'git -C reference/GrappleMap checkout -- .'
check block $F 'git -C reference/GrappleMap reset HEAD~1'
check block $F 'git checkout -- tests/golden/a.png'
check block $F 'git restore reference/GrappleMap/a'
check block $F 'tee -a src/../reference/GrappleMap/a'
check block $F 'echo x | tee tests/golden/a'
check block $F 'cd reference/GrappleMap && rm src/a.cpp'
check block $F 'cd tests/golden; echo x > a.png'
check block $F 'cd reference/GrappleMap/src && sed -i s/a/b/ a.cpp'
check block $F 'bash -c "echo x > tests/golden/a"'
check allow $F 'cat reference/GrappleMap/src/a.cpp'
check allow $F 'grep -n x reference/GrappleMap/src/*.hpp'
check allow $F 'sed -n 1,5p reference/GrappleMap/a'
check allow $F 'cp reference/GrappleMap/a /tmp/x'
check allow $F 'cp reference/GrappleMap/a tests/fixtures/x'
check allow $F 'ls tests/golden'
check allow $F 'diff tests/golden/a.png build/a.png'
check allow $F 'echo x > build/out.txt'
check allow $F 'echo x > tests/goldenish/a'
check allow $F 'echo x 2>&1'
check allow $F 'cd reference/GrappleMap/src && grep -n x a.cpp'
check allow $F 'cd reference/GrappleMap && cd .. && echo x > a'
check allow $F 'git submodule update --init'
check allow $F 'git -C reference/GrappleMap log --oneline'
check allow $F 'git -C reference/GrappleMap show HEAD:README.md'
check allow $F 'git -C reference/GrappleMap rev-parse HEAD'
check allow $F 'git checkout -- src/a.odin'
check allow $F './build.sh test-golden --update'
check allow $F 'rm build/x.o'

echo "guard-bash: $((total - fail))/$total passed"
[ "$fail" -eq 0 ]
