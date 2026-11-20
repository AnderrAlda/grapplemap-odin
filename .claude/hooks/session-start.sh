#!/usr/bin/env bash
# SessionStart: show branch, git status and the issue/phase in progress.
source "$(dirname "$0")/_common.sh"
branch=$(git branch --show-current 2>/dev/null)
status=$(git status --short 2>/dev/null | head -10)
issue=$(printf '%s' "$branch" | grep -oE '[0-9]+' | head -1)
ctx="Branch: ${branch:-detached}
Git status:
${status:-clean}"
[ -n "$issue" ] && command -v gh >/dev/null && ctx="$ctx
Issue #$issue: $(gh issue view "$issue" --json title,labels --jq '.title + " [" + ([.labels[].name]|join(",")) + "]"' 2>/dev/null)"
[ "$branch" = "main" ] && ctx="$ctx
WARNING: on main. Create a branch before committing."
jq -n --arg c "$ctx" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
