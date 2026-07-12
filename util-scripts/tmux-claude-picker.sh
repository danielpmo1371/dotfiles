#!/usr/bin/env bash
#
# tmux-claude-picker.sh - fzf picker over panes running Claude Code; Enter jumps to the pane
#
# Usage:
#   tmux-claude-picker.sh          # run the picker (needs a tty; tmux.conf wraps it in display-popup)
#   tmux-claude-picker.sh --list   # print detected Claude panes (used by fzf ctrl-r reload)
#
# Keybinding: Cmd+e Cmd+i / Cmd+e i (see config/tmux/tmux.conf)

set -euo pipefail

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
TAB=$'\t'

# Print one line per pane with a claude child process: "session:window.pane<TAB>label"
list_claude_panes() {
    while IFS="$TAB" read -r session window pane pid pane_title window_name; do
        if pgrep -P "$pid" 2>/dev/null | xargs -I {} ps -p {} -o comm= 2>/dev/null | grep -q "claude\|node.*claude"; then
            local target="$session:$window.$pane"
            local label="$window_name"
            if [ -n "$pane_title" ] && [ "$pane_title" != "$target" ]; then
                label="$pane_title"
            fi
            printf '%s\t%s\n' "$target" "$label"
        fi
    done < <(tmux list-panes -a -F "#{session_name}${TAB}#{window_index}${TAB}#{pane_index}${TAB}#{pane_pid}${TAB}#{pane_title}${TAB}#{window_name}")
}

if [ "${1:-}" = "--list" ]; then
    list_claude_panes
    exit 0
fi

if ! command -v fzf >/dev/null 2>&1; then
    # display-popup shells can miss brew paths; try the common install locations
    for dir in /opt/homebrew/bin /usr/local/bin; do
        [ -x "$dir/fzf" ] && PATH="$PATH:$dir" && break
    done
    if ! command -v fzf >/dev/null 2>&1; then
        echo "Error: fzf not found. Install with: ./install.sh --tools"
        sleep 2
        exit 1
    fi
fi

panes="$(list_claude_panes)"
if [ -z "$panes" ]; then
    echo "No Claude processes running"
    sleep 1.5
    exit 0
fi

selection="$(printf '%s\n' "$panes" | fzf \
    --delimiter="$TAB" \
    --with-nth=1,2 \
    --prompt='claude> ' \
    --header='enter: jump · ctrl-r: refresh · esc: close' \
    --preview='tmux capture-pane -ep -t {1}' \
    --preview-window='down,65%,border-top' \
    --bind="ctrl-r:reload($SCRIPT_PATH --list)")" || exit 0

target="$(printf '%s' "$selection" | cut -f1)"
[ -z "$target" ] && exit 0

tmux select-window -t "${target%.*}"
tmux select-pane -t "$target"
tmux switch-client -t "${target%%:*}"
