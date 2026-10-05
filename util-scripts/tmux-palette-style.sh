#!/usr/bin/env bash
#
# tmux-palette-style.sh - the tmux-palette (Ctrl+P menu) look for fzf popups. Sourced, not run.
#
# Shared by tmux-claude-picker.sh and tmux-bt-popup.sh so every popup looks like
# the palette: borderless centred popup whose body is the theme's panel colour,
# fzf coloured with the palette's roles, a bold title row with a muted "esc".
# Colours are read at runtime from the palette's active theme (so a theme switch
# in Ctrl+P carries over), falling back to its default "Shades of Purple" theme
# when bun or the plugin is missing.
#
# Provides:
#   load_theme                          set and export the THEME_* vars (once per process tree)
#   palette_fzf_colors                  print the fzf --color string with the palette's roles
#   palette_title <title> <width>       print the palette header row, padded to <width>
#   palette_body_width                  print the width inside fzf's PALETTE_PAD_X margins
#   palette_popup <width> <height> <command> [client]
#                                       open a borderless, centred popup with the panel body;
#                                       <height> is lines or "<n>%" of the client height,
#                                       both are capped by the client size; <command> is
#                                       passed to display-popup as is (quote it yourself)
#
# Must stay bash 3.2 compatible (macOS): no mapfile, no $'\U...', no empty-array expansion.

# The constants are read by the scripts that source this file.
# shellcheck disable=SC2034

# Glyphs mirror tmux-palette's src/render.ts
PALETTE_MARKER_GLYPH='▌'
PALETTE_ESC_HINT='esc'

# Popup geometry. Width and padX match tmux-palette's defaults (src/cli.ts
# DEFAULT_WIDTH / DEFAULT_PAD_X).
PALETTE_POPUP_WIDTH=90
PALETTE_PAD_X=3
PALETTE_CLIENT_MARGIN_X=4   # same breathing room bin/tmux-palette.sh leaves around the popup
PALETTE_CLIENT_MARGIN_Y=2

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

PALETTE_FIELD_SEPARATOR=$'\t'

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
        IFS="$PALETTE_FIELD_SEPARATOR" read -r THEME_BG THEME_PANEL THEME_SELECTED THEME_FG THEME_MUTED THEME_ACCENT \
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

# Colour roles follow the palette's render.ts: rows muted, current row bold fg on
# the selected bg, accent prompt/marker, and the darker theme bg for a preview
# panel. Popups have no visible borders: fzf's border lines are only used to
# place the title (input border label) and the hints (outer border label), so
# they are drawn in the panel colour and read as the palette's blank rows.
palette_fzf_colors() {
    local colors
    colors="bg:$THEME_PANEL,list-bg:$THEME_PANEL,input-bg:$THEME_PANEL,preview-bg:$THEME_BG"
    colors+=",gutter:$THEME_PANEL,border:$THEME_PANEL,input-border:$THEME_PANEL"
    colors+=",fg:$THEME_MUTED,current-fg:regular:bold:$THEME_CURRENT_FG,current-bg:$THEME_SELECTED"
    colors+=",hl:$THEME_ACCENT,current-hl:$THEME_ACCENT,query:$THEME_FG,ghost:$THEME_MUTED"
    colors+=",pointer:$THEME_ACTIVE_FG,prompt:regular:$THEME_ACCENT,label:$THEME_MUTED,spinner:$THEME_ACCENT"
    colors+=",preview-fg:-1,preview-border:$THEME_SELECTED"
    printf '%s' "$colors"
}

# Title row like the palette header: bold title left, muted "esc" right, padded
# to the full body width so the (invisible) border line under it never shows.
palette_title() {
    local title="$1" width="$2"
    local gap=$(( width - ${#title} - ${#PALETTE_ESC_HINT} ))
    (( gap < 1 )) && gap=1
    printf '%s%s%s%s%*s%s%s%s' "$ANSI_BOLD" "$THEME_ANSI_TITLE_FG" "$title" "$ANSI_RESET" \
        "$gap" '' "$THEME_ANSI_MUTED" "$PALETTE_ESC_HINT" "$ANSI_RESET"
}

# Width of the body inside fzf's --margin of PALETTE_PAD_X on each side.
palette_body_width() {
    local term_width
    term_width="$(tput cols 2>/dev/null || echo "$PALETTE_POPUP_WIDTH")"
    printf '%s' $(( term_width - PALETTE_PAD_X * 2 ))
}

# Size the popup like bin/tmux-palette.sh (requested size capped by the client,
# centred, borderless with the theme's panel as body) and run <command> in it.
# With [client], the size is read from and the popup opened on that client;
# without it tmux works out the current client.
palette_popup() {
    local want_width="$1" want_height="$2" command="$3" client="${4:-}"
    local client_width client_height width height max_height
    if [ -n "$client" ]; then
        set -- -c "$client"
    else
        set --
    fi
    client_width="$(tmux display-message "$@" -p '#{client_width}')"
    client_height="$(tmux display-message "$@" -p '#{client_height}')"
    width=$(( want_width < client_width - PALETTE_CLIENT_MARGIN_X ? want_width : client_width - PALETTE_CLIENT_MARGIN_X ))
    case "$want_height" in
        *%) height=$(( client_height * ${want_height%\%} / 100 )) ;;
        *)  height="$want_height" ;;
    esac
    max_height=$(( client_height - PALETTE_CLIENT_MARGIN_Y ))
    (( height > max_height )) && height=$max_height
    tmux display-popup "$@" -B -s "$THEME_TMUX_BODY_STYLE" -w "$width" -h "$height" -E "$command"
}
