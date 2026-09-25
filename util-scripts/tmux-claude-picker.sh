#!/usr/bin/env bash
#
# tmux-claude-picker.sh - fzf picker over panes running Claude Code; Enter jumps to the pane
#
# Usage:
#   tmux-claude-picker.sh            # run the picker (needs a tty; tmux.conf wraps it in display-popup)
#   tmux-claude-picker.sh --list     # print detected Claude panes (used by fzf ctrl-r reload)
#   tmux-claude-picker.sh --json     # print Claude panes as a tmux-palette Item JSON array (needs jq;
#                                    #   used by config/tmux-palette/palettes/claude.json)
#   tmux-claude-picker.sh --vi <key> # fzf transform helper: vi-modal action for <key> (reads $FZF_PROMPT)
#
# Keybinding: Cmd+e Cmd+i / Cmd+e i opens the tmux-palette "claude" palette, which runs --json
# (see config/tmux/tmux.conf). The fzf mode below remains usable standalone.
#
# Starts in NORMAL mode (j/k move, i enters filter mode, esc closes).
# In INSERT mode typing filters; esc returns to NORMAL keeping the filter.

set -euo pipefail

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
TAB=$'\t'
NORMAL_PROMPT='[N] '
INSERT_PROMPT='[I] '
# Nerd Font robot glyph (nf-md-robot, U+F06A9) as a JSON escape, so jq emits it
CLAUDE_ICON_JSON='"\udb81\udea9"'

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

# tmux-palette plugin source: one Item per Claude pane. The palette wrapper
# (bin/tmux-palette.sh) runs `eval "tmux <action>"`, so each target is shell
# single-quoted with jq's @sh and commands are chained with an escaped `\;`
# that survives eval as a literal tmux command separator.
if [ "${1:-}" = "--json" ]; then
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: jq not found. Install with: ./install.sh --tools" >&2
        exit 1
    fi
    list_claude_panes | jq -R -s -c --argjson icon "$CLAUDE_ICON_JSON" '
        split("\n")
        | map(select(length > 0) | split("\t") | {target: .[0], label: (.[1] // "")})
        | map(
            (.target | sub("\\.[^.]*$"; "")) as $window
            | (.target | sub(":.*$"; "")) as $session
            | {
                icon: $icon,
                title: .target,
                description: .label,
                action: {
                    tmux: "select-window -t \($window | @sh) \\; select-pane -t \(.target | @sh) \\; switch-client -t \($session | @sh)"
                }
            }
        )'
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
