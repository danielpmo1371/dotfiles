#!/usr/bin/env bash
#
# show-claude-processes.sh - Display Claude Code processes in tmux
# Usage: Can be called standalone or integrated into tmux corner pane
#

# Compact Claude process monitor
echo "CLAUDE PROCESSES - $(date '+%H:%M:%S')"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Find Claude in tmux panes - compact format
found=0
while IFS='|' read -r session window pane pid; do
    if pgrep -P "$pid" 2>/dev/null | xargs -I {} ps -p {} -o comm= 2>/dev/null | grep -q "claude\|node.*claude"; then
        printf "%s:%s.%s\n" "$session" "$window" "$pane"
        found=1
    fi
done < <(tmux list-panes -a -F "#{session_name}|#{window_index}|#{pane_index}|#{pane_pid}")

[ $found -eq 0 ] && echo "None running"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
