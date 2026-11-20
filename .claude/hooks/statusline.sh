#!/usr/bin/env bash
# Status line: [model] (branch) NN% context
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
input=$(cat)
model=$(printf '%s' "$input" | jq -r '.model.display_name // "?"')
pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // "."')
branch=$(git -C "$dir" branch --show-current 2>/dev/null)
echo "[$model] ${branch:+($branch) }${pct}% ctx"
