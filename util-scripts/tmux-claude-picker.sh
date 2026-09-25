#!/usr/bin/env bash
#
# tmux-claude-picker.sh - fzf picker over panes running Claude Code; Enter jumps to the pane
#
# Styled after the tmux-palette plugin (the Ctrl+P menu): borderless popup, title
# line, "▌ Search" input, "▌" marker on the current row, hint footer. Colours are
# read at runtime from the palette's active theme (so a theme switch in Ctrl+P
# carries over), falling back to its default "Shades of Purple" theme when bun or
# the plugin is missing.
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

PICKER_TITLE='Claude Sessions'
PICKER_EMPTY_TEXT='No Claude processes running'
PICKER_HINTS='enter jump   j/k move   i filter   esc back/close   ctrl-r refresh'
SEARCH_GHOST='Search'
# Glyphs mirror tmux-palette's src/render.ts
MARKER_GLYPH='▌'
# Nerd Font robot (nf-md-robot, U+F06A9) as UTF-8 bytes; $'\U...' needs bash 4.2+ (macOS ships 3.2)
CLAUDE_ICON=$'\xf3\xb0\x9a\xa9'

# Popup geometry. Width and padX match tmux-palette's defaults (src/cli.ts
# DEFAULT_WIDTH / DEFAULT_PAD_X); the height is a share of the client because,
# unlike the palette, the picker also shows a live preview of the pane.
POPUP_WIDTH=90
POPUP_HEIGHT_PERCENT=70
POPUP_CLIENT_MARGIN_X=4   # same breathing room bin/tmux-palette.sh leaves around the popup
POPUP_CLIENT_MARGIN_Y=2
PAD_X=3
PREVIEW_HEIGHT='60%'

TMUX_PALETTE_DIR="${TMUX_PALETTE_DIR:-$HOME/.tmux/plugins/tmux-palette}"
TMUX_PALETTE_THEME_TS="$TMUX_PALETTE_DIR/src/theme.ts"

# Fallback theme: tmux-palette's default bundled theme "Shades of Purple"
# (src/themes-bundled.ts), pre-derived the same way the loader below derives it.
DEFAULT_THEME_BG='#1e1d40'
DEFAULT_THEME_PANEL='#2d2b55'
DEFAULT_THEME_SELECTED='#504d7a'
DEFAULT_THEME_FG='#ffffff'
DEFAULT_THEME_MUTED='#a599e9'
DEFAULT_THEME_ACCENT='#fad000'
DEFAULT_THEME_ACTIVE_FG="$DEFAULT_THEME_ACCENT"   # current-row marker: theme.selectedFg, else accent
DEFAULT_THEME_CURRENT_FG="$DEFAULT_THEME_FG"      # current-row title: theme.selectedFg, else fg
DEFAULT_THEME_TITLE_FG="$DEFAULT_THEME_FG"        # theme.titleFg, else fg
DEFAULT_THEME_TMUX_BODY_STYLE="bg=$DEFAULT_THEME_PANEL"
DEFAULT_THEME_ANSI_MUTED=$'\e[38;2;165;153;233m'
DEFAULT_THEME_ANSI_ACCENT=$'\e[38;2;250;208;0m'
DEFAULT_THEME_ANSI_TITLE_FG=$'\e[38;2;255;255;255m'
ANSI_RESET=$'\e[0m'
ANSI_BOLD=$'\e[1m'

# Resolve the palette's active theme (~/.config/tmux-palette/theme.json, else its
# default) with the plugin's own helpers, so this stays in sync with Ctrl+P.
# Prints one tab-separated line; every field is non-empty because `read` with a
# whitespace IFS would collapse empty fields. fzf takes the same colour names as
# the theme (hex, "blue", "bright-black"); only "transparent" needs mapping (-1).
read_palette_theme() {
    command -v bun >/dev/null 2>&1 || return 1
    [ -f "$TMUX_PALETTE_THEME_TS" ] || return 1
    THEME_TS="$TMUX_PALETTE_THEME_TS" bun -e '
        const { resolveActiveTheme, makeColors, tmuxBodyStyle } = await import(process.env.THEME_TS);
        const t = resolveActiveTheme(undefined);
        const fzf = (v) => (v === "transparent" ? "-1" : v);
        const ansiFg = (v) => makeColors({ ...t, muted: v }).muted;
        const activeFg = t.selectedFg ?? t.accent;
        const currentFg = t.selectedFg ?? t.fg;
        const titleFg = t.titleFg ?? t.fg;
        console.log([
            fzf(t.bg), fzf(t.panel), fzf(t.selected), fzf(t.fg), fzf(t.muted), fzf(t.accent),
            fzf(activeFg), fzf(currentFg), fzf(titleFg), tmuxBodyStyle(t),
            ansiFg(t.muted), ansiFg(t.accent), ansiFg(titleFg),
        ].join("\t"));
    ' 2>/dev/null
}

# Populate (and export, so fzf's reload/transform children reuse them) the THEME_* vars.
load_theme() {
    [ -n "${THEME_LOADED:-}" ] && return 0
    local line=""
    line="$(read_palette_theme)" || line=""
    if [ -n "$line" ]; then
        IFS="$TAB" read -r THEME_BG THEME_PANEL THEME_SELECTED THEME_FG THEME_MUTED THEME_ACCENT \
            THEME_ACTIVE_FG THEME_CURRENT_FG THEME_TITLE_FG THEME_TMUX_BODY_STYLE \
            THEME_ANSI_MUTED THEME_ANSI_ACCENT THEME_ANSI_TITLE_FG <<<"$line"
    else
        THEME_BG="$DEFAULT_THEME_BG"
        THEME_PANEL="$DEFAULT_THEME_PANEL"
        THEME_SELECTED="$DEFAULT_THEME_SELECTED"
        THEME_FG="$DEFAULT_THEME_FG"
        THEME_MUTED="$DEFAULT_THEME_MUTED"
        THEME_ACCENT="$DEFAULT_THEME_ACCENT"
        THEME_ACTIVE_FG="$DEFAULT_THEME_ACTIVE_FG"
        THEME_CURRENT_FG="$DEFAULT_THEME_CURRENT_FG"
        THEME_TITLE_FG="$DEFAULT_THEME_TITLE_FG"
        THEME_TMUX_BODY_STYLE="$DEFAULT_THEME_TMUX_BODY_STYLE"
        THEME_ANSI_MUTED="$DEFAULT_THEME_ANSI_MUTED"
        THEME_ANSI_ACCENT="$DEFAULT_THEME_ANSI_ACCENT"
        THEME_ANSI_TITLE_FG="$DEFAULT_THEME_ANSI_TITLE_FG"
    fi
    THEME_LOADED=1
    export THEME_LOADED THEME_BG THEME_PANEL THEME_SELECTED THEME_FG THEME_MUTED THEME_ACCENT \
        THEME_ACTIVE_FG THEME_CURRENT_FG THEME_TITLE_FG THEME_TMUX_BODY_STYLE \
        THEME_ANSI_MUTED THEME_ANSI_ACCENT THEME_ANSI_TITLE_FG
}

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

# Title row like the palette header: bold title left, muted "esc" right, padded
# to the full body width so the (invisible) border line under it never shows.
picker_title() {
    local width="$1"
    local esc_hint='esc'
    local gap=$(( width - ${#PICKER_TITLE} - ${#esc_hint} ))
    (( gap < 1 )) && gap=1
    printf '%s%s%s%s%*s%s%s%s' "$ANSI_BOLD" "$THEME_ANSI_TITLE_FG" "$PICKER_TITLE" "$ANSI_RESET" \
        "$gap" '' "$THEME_ANSI_MUTED" "$esc_hint" "$ANSI_RESET"
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

# Launcher: size the popup like bin/tmux-palette.sh (fixed width capped by the
# client, centred, borderless with the theme's panel as body) and run the picker in it.
if [ "${1:-}" = "--popup" ]; then
    client_width="$(tmux display-message -p '#{client_width}')"
    client_height="$(tmux display-message -p '#{client_height}')"
    width=$(( POPUP_WIDTH < client_width - POPUP_CLIENT_MARGIN_X ? POPUP_WIDTH : client_width - POPUP_CLIENT_MARGIN_X ))
    height=$(( client_height * POPUP_HEIGHT_PERCENT / 100 ))
    max_height=$(( client_height - POPUP_CLIENT_MARGIN_Y ))
    (( height > max_height )) && height=$max_height
    tmux display-popup -B -s "$THEME_TMUX_BODY_STYLE" -w "$width" -h "$height" -E "$(printf %q "$SCRIPT_PATH")"
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

term_width="$(tput cols 2>/dev/null || echo "$POPUP_WIDTH")"
body_width=$(( term_width - PAD_X * 2 ))

# Colour roles follow the palette's render.ts: rows muted, current row bold fg on
# the selected bg, accent prompt/marker, and the darker theme bg for the preview
# panel. The popup has no visible borders: fzf's border lines are only used to
# place the title (input border label) and the hints (outer border label), so
# they are drawn in the panel colour and read as the palette's blank rows.
fzf_colors="bg:$THEME_PANEL,list-bg:$THEME_PANEL,input-bg:$THEME_PANEL,preview-bg:$THEME_BG"
fzf_colors+=",gutter:$THEME_PANEL,border:$THEME_PANEL,input-border:$THEME_PANEL"
fzf_colors+=",fg:$THEME_MUTED,current-fg:regular:bold:$THEME_CURRENT_FG,current-bg:$THEME_SELECTED"
fzf_colors+=",hl:$THEME_ACCENT,current-hl:$THEME_ACCENT,query:$THEME_FG,ghost:$THEME_MUTED"
fzf_colors+=",pointer:$THEME_ACTIVE_FG,prompt:regular:$THEME_ACCENT,label:$THEME_MUTED,spinner:$THEME_ACCENT"
fzf_colors+=",preview-fg:-1,preview-border:$THEME_SELECTED"

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
    --input-label="$(picker_title "$body_width")" \
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
