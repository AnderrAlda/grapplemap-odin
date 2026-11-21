#!/usr/bin/env bash
# PreToolUse(Bash): block git commit/push on main and destructive commands.
source "$(dirname "$0")/_common.sh"
cmd=$(jqr '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0
branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
if [ "$branch" = "main" ] && printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+(commit|push)\b'; then
	deny_pretool "On 'main': commits and pushes are blocked. Create a branch first (git switch -c feat/...)."
fi
# Any push that targets main (explicit refspec/arg), from any branch. Merges happen only on GitHub.
if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push([[:space:]].*)?[[:space:]:](refs/heads/)?main([[:space:]]|$)'; then
	deny_pretool "Pushing to main is blocked. Push a feature branch and merge the PR on GitHub."
fi
if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push[[:space:]].*(--force|-f\b|--delete|--mirror|--all|[[:space:]]\+[^[:space:]])|git[[:space:]]+reset[[:space:]]+--hard|git[[:space:]]+clean[[:space:]]+-[a-z]*f|rm[[:space:]]+-[a-z]*r[a-z]*f|rm[[:space:]]+-[a-z]*f[a-z]*r|(^|[;&|[:space:]])sudo[[:space:]]|gh[[:space:]]+pr[[:space:]]+merge|--no-verify'; then
	deny_pretool "Destructive or forbidden command blocked (force push, reset --hard, clean -f, rm -rf, sudo, gh pr merge, --no-verify)."
fi
exit 0
