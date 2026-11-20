#!/usr/bin/env bash
# Shared helpers for Claude Code hooks. Reads the hook JSON from stdin into $INPUT.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
INPUT=$(cat)
jqr() { printf '%s' "$INPUT" | jq -r "$1" 2>/dev/null; }
# deny_pretool <reason>: block a PreToolUse call.
deny_pretool() {
	jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
	exit 0
}
