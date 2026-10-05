#!/usr/bin/env bash
#
# tmux-claude-picker.sh - fzf picker over panes running Claude Code; Enter jumps to the pane
#
# Styled after the tmux-palette plugin (the Ctrl+P menu): borderless popup, title
# line, "▌ Search" input, "▌" marker on the current row, hint footer. The look
# (theme colours, fzf colour roles, title row, popup) comes from
# tmux-palette-style.sh, shared with the other palette-style popups.
#
# Usage:
#   tmux-claude-picker.sh            # run the picker (needs a tty)
#   tmux-claude-picker.sh --popup    # open the picker in a themed, borderless, centred tmux popup
#                                    #   (what the tmux.conf bindings run via run-shell)
#   tmux-claude-picker.sh --list     # print detected Claude panes as picker lines (used by ctrl-r reload)
#   tmux-claude-picker.sh --hints    # print the hint line + match count (reads $FZF_MATCH_COUNT)
#   tmux-claude-picker.sh --vi <key> # fzf transform helper: vi-modal action for <key> (reads $FZF_PROMPT)
#
# Keybinding: Cmd+e Cmd+i / Cmd+e i (see config/tmux/tmux.conf)
#
# Starts in NORMAL mode (muted "▌": j/k move, i enters filter mode, esc closes).
# In INSERT mode (accent "▌") typing filters; esc returns to NORMAL keeping the filter.

set -euo pipefail

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
TAB=$'\t'

# shellcheck source=tmux-palette-style.sh
source "$(dirname "$SCRIPT_PATH")/tmux-palette-style.sh"

PICKER_TITLE='Claude Sessions'
PICKER_EMPTY_TEXT='No Claude processes running'
PICKER_HINTS='enter jump   j/k move   i filter   esc back/close   ctrl-r refresh'
SEARCH_GHOST='Search'
MARKER_GLYPH="$PALETTE_MARKER_GLYPH"
# Nerd Font robot (nf-md-robot, U+F06A9) as UTF-8 bytes; $'\U...' needs bash 4.2+ (macOS ships 3.2)
CLAUDE_ICON=$'\xf3\xb0\x9a\xa9'

# Popup geometry: the palette's width and padding; the height is a share of the
# client because, unlike the palette, the picker also shows a live preview of the pane.
POPUP_WIDTH="$PALETTE_POPUP_WIDTH"
POPUP_HEIGHT_PERCENT=70
PAD_X="$PALETTE_PAD_X"
PREVIEW_HEIGHT='60%'

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

# Picker lines: "target<TAB>icon  target - label". Field 1 stays the plain target
# (jump + preview); field 2 is what fzf shows and searches (target and label),
# rendered like a palette row: accent icon, title in fzf's fg, muted description.
format_picker_lines() {
    local target label
    while IFS="$TAB" read -r target label; do
        printf '%s\t%s%s%s  %s' "$target" "$THEME_ANSI_ACCENT" "$CLAUDE_ICON" "$ANSI_RESET" "$target"
        [ -n "$label" ] && printf '%s - %s%s' "$THEME_ANSI_MUTED" "$label" "$ANSI_RESET"
        printf '\n'
    done
}

if [ "${1:-}" = "--list" ]; then
    load_theme
    list_claude_panes | format_picker_lines
    exit 0
fi

# Hint line with the live match count, like the palette's
# "enter select   up/down move   N commands".
if [ "${1:-}" = "--hints" ]; then
    count="${FZF_MATCH_COUNT:-0}"
    noun='sessions'
    [ "$count" = 1 ] && noun='session'
    printf '%s   %s %s' "$PICKER_HINTS" "$count" "$noun"
    exit 0
fi

# Mode prompts: the palette's "▌ " search marker, muted in NORMAL and accent in
# INSERT (the palette's own look while typing). The --vi helper keys off exact
# $FZF_PROMPT equality, so both modes must build the prompt from these values.
load_theme
NORMAL_PROMPT="${THEME_ANSI_MUTED}${MARKER_GLYPH} ${ANSI_RESET}"
INSERT_PROMPT="${THEME_ANSI_ACCENT}${MARKER_GLYPH} ${ANSI_RESET}"

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

# Launcher: the palette-style popup (see palette_popup) running the picker.
if [ "${1:-}" = "--popup" ]; then
    palette_popup "$POPUP_WIDTH" "${POPUP_HEIGHT_PERCENT}%" "$(printf %q "$SCRIPT_PATH")"
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
    echo "$PICKER_EMPTY_TEXT"
    sleep 1.5
    exit 0
fi

# The shell env (tmux global env / zshrc) may carry FZF_DEFAULT_OPTS like
# "--tmux center,75%" which makes fzf try to open a nested tmux popup — that
# deadlocks inside display-popup. This picker fully controls its own flags.
unset FZF_DEFAULT_OPTS FZF_DEFAULT_OPTS_FILE FZF_DEFAULT_COMMAND

body_width="$(palette_body_width)"

# Colour roles, borderless layout: see palette_fzf_colors.
fzf_colors="$(palette_fzf_colors)"

selection="$(printf '%s\n' "$panes" | format_picker_lines | fzf \
    --ansi \
    --delimiter="$TAB" \
    --with-nth=2 \
    --layout=reverse \
    --margin="1,$PAD_X" \
    --border=bottom \
    --padding='0,0,1,0' \
    --border-label="$(FZF_MATCH_COUNT="$(wc -l <<<"$panes" | tr -d ' ')" "$SCRIPT_PATH" --hints)" \
    --border-label-pos='1:bottom' \
    --input-border=horizontal \
    --input-label="$(palette_title "$PICKER_TITLE" "$body_width")" \
    --input-label-pos=1 \
    --info=hidden \
    --no-scrollbar \
    --highlight-line \
    --pointer="$MARKER_GLYPH" \
    --gutter=' ' \
    --prompt="$NORMAL_PROMPT" \
    --ghost="$SEARCH_GHOST" \
    --color="$fzf_colors" \
    --preview='tmux capture-pane -ep -t {1}' \
    --preview-window="down,$PREVIEW_HEIGHT,border-top,noinfo" \
    --bind="result:transform-border-label:$SCRIPT_PATH --hints" \
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
