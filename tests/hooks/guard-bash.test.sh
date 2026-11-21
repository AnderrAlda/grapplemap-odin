#!/usr/bin/env bash
# Table-driven test for .claude/hooks/guard-bash.sh. Exits non-zero on any mismatch.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HOOK="$ROOT/.claude/hooks/guard-bash.sh"
command -v jq >/dev/null || { echo "jq required"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git init -q -b main "$TMP/repo"
git -C "$TMP/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$TMP/repo" branch feat/x

fail=0
total=0
# check <allow|block> <branch> <command>
check() {
	local want=$1 branch=$2 cmd=$3 out got
	git -C "$TMP/repo" switch -q "$branch"
	out=$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$TMP/repo" bash "$HOOK")
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

echo "guard-bash: $((total - fail))/$total passed"
[ "$fail" -eq 0 ]
