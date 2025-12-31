#!/usr/bin/env bash
#
# show-claude-processes.sh - Display Claude Code processes in tmux
# Usage: Can be called standalone or integrated into tmux corner pane
#

# Compact Claude process monitor
echo "CLAUDE PROCESSES - $(date '+%H:%M:%S')"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Find Claude in tmux panes - compact format with titles
found=0
while IFS='|' read -r session window pane pid pane_title window_name; do
    if pgrep -P "$pid" 2>/dev/null | xargs -I {} ps -p {} -o comm= 2>/dev/null | grep -q "claude\|node.*claude"; then
        # Format: session:window.pane - title
        printf "%-15s" "$session:$window.$pane"

        # Show pane title if available, otherwise window name
        if [ -n "$pane_title" ] && [ "$pane_title" != "$session:$window.$pane" ]; then
            echo " - $pane_title"
        elif [ -n "$window_name" ]; then
            echo " - $window_name"
        else
            echo ""
        fi

        found=1
    fi
done < <(tmux list-panes -a -F "#{session_name}|#{window_index}|#{pane_index}|#{pane_pid}|#{pane_title}|#{window_name}")

[ $found -eq 0 ] && echo "None running"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Cmd+e [ then j/k to scroll | Cmd+e i to close"
