#!/usr/bin/env bash
#
# tmux-claude-picker.sh - fzf picker over panes running Claude Code; Enter jumps to the pane
#
# Usage:
#   tmux-claude-picker.sh            # run the picker (needs a tty; tmux.conf wraps it in display-popup)
#   tmux-claude-picker.sh --list     # print detected Claude panes (used by fzf ctrl-r reload)
#   tmux-claude-picker.sh --vi <key> # fzf transform helper: vi-modal action for <key> (reads $FZF_PROMPT)
#
# Keybinding: Cmd+e Cmd+i / Cmd+e i (see config/tmux/tmux.conf)
#
# Starts in NORMAL mode (j/k move, i enters filter mode, esc closes).
# In INSERT mode typing filters; esc returns to NORMAL keeping the filter.

set -euo pipefail

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
TAB=$'\t'
NORMAL_PROMPT='[N] '
INSERT_PROMPT='[I] '

# Print one line per pane with a claude child process: "session:window.pane<TAB>label"
list_claude_panes() {
    # Single ps pass: parent pids that have a claude-ish child (vs pgrep/ps per pane)
    local claude_ppids
    claude_ppids="$(ps -axo ppid=,comm= | awk '/claude|node.*claude/ {print $1}' | sort -u)"
    [ -z "$claude_ppids" ] && return 0

    while IFS="$TAB" read -r session window pane pid pane_title window_name; do
        if grep -qxF "$pid" <<<"$claude_ppids"; then
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

# fzf `transform` helper: prints the action for a key based on the current
# mode, which is tracked in the prompt ($FZF_PROMPT is exported by fzf).
if [ "${1:-}" = "--vi" ]; then
    key="${2:-}"
    if [ "${FZF_PROMPT:-}" = "$NORMAL_PROMPT" ]; then
        case "$key" in
            j)   echo "down" ;;
            k)   echo "up" ;;
            i)   echo "change-prompt($INSERT_PROMPT)" ;;
            esc) echo "abort" ;;
        esac
    else
        case "$key" in
            esc) echo "change-prompt($NORMAL_PROMPT)" ;;
            *)   echo "put($key)" ;;
        esac
    fi
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

# The shell env (tmux global env / zshrc) may carry FZF_DEFAULT_OPTS like
# "--tmux center,75%" which makes fzf try to open a nested tmux popup — that
# deadlocks inside display-popup. This picker fully controls its own flags.
unset FZF_DEFAULT_OPTS FZF_DEFAULT_OPTS_FILE FZF_DEFAULT_COMMAND

selection="$(printf '%s\n' "$panes" | fzf \
    --delimiter="$TAB" \
    --with-nth=1,2 \
    --prompt="$NORMAL_PROMPT" \
    --header='j/k: move · i: filter · esc: normal/close · enter: jump · ctrl-r: refresh' \
    --preview='tmux capture-pane -ep -t {1}' \
    --preview-window='down,65%,border-top' \
    --bind="j:transform:$SCRIPT_PATH --vi j" \
    --bind="k:transform:$SCRIPT_PATH --vi k" \
    --bind="i:transform:$SCRIPT_PATH --vi i" \
    --bind="esc:transform:$SCRIPT_PATH --vi esc" \
    --bind="ctrl-r:reload($SCRIPT_PATH --list)")" || exit 0

target="$(printf '%s' "$selection" | cut -f1)"
[ -z "$target" ] && exit 0

tmux select-window -t "${target%.*}"
tmux select-pane -t "$target"
tmux switch-client -t "${target%%:*}"
