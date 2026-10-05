#!/usr/bin/env bash
#
# tmux-palette-style.sh - the tmux-palette (Ctrl+P menu) look for fzf popups. Sourced, not run.
#
# Shared by tmux-claude-picker.sh, tmux-bt-popup.sh, tmux-wifi-popup.sh and
# tmux-control-panel.sh so every popup looks like
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
#   palette_picker_fzf_opts <title> <hints> <ghost>
#                                       print fzf options (one per line) for a picker in the
#                                       palette look: title row, hints label, no header
#   palette_stream_indent               copy stdin to stdout indented to the body and muted
#   palette_tool_popup <title> <ok text> <fail text> <command...>
#                                       run a picker tool (bt-fix, wifi-pick) under the title
#                                       row, then show its outcome until a key is pressed;
#                                       exit 130 from the tool (Esc) closes straight away
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
PALETTE_CLOSE_HINT='press any key to close'
PALETTE_EXIT_CANCELLED=130   # fzf's Esc, passed through by bt-fix and wifi-pick
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

# fzf options for a tool's picker, one per line (the format BT_FIX_FZF_OPTS and
# WIFI_PICK_FZF_OPTS take): the Claude picker's layout and colour roles (muted
# rows, bold current row on the selected bg, accent prompt and pointer, panel
# bg) with the palette title row and hints. --header= drops the tool's own
# header; the title row says what this is.
palette_picker_fzf_opts() {
    local title="$1" hints="$2" ghost="$3"
    printf '%s\n' \
        '--ansi' \
        '--layout=reverse' \
        "--margin=1,$PALETTE_PAD_X" \
        '--border=bottom' \
        '--padding=0,0,1,0' \
        "--border-label=$hints" \
        '--border-label-pos=1:bottom' \
        '--input-border=horizontal' \
        "--input-label=$(palette_title "$title" "$(palette_body_width)")" \
        '--input-label-pos=1' \
        '--info=hidden' \
        '--no-scrollbar' \
        '--highlight-line' \
        "--pointer=$PALETTE_MARKER_GLYPH" \
        '--gutter= ' \
        "--prompt=${THEME_ANSI_ACCENT}${PALETTE_MARKER_GLYPH} ${ANSI_RESET}" \
        "--ghost=$ghost" \
        '--header=' \
        "--color=$(palette_fzf_colors)"
}

# Copy a tool's output through character by character (a question has no
# newline yet and must show at once), indented to the body and muted like the
# palette's descriptions. A line ending in "] " or "> " is a question waiting
# for input ("[y/N] ", select's "device number> ", wifi-pick's "password> "):
# the terminal echoes the answer's Enter, so the next output starts a new line
# and gets indented.
palette_stream_indent() {
    local char line='' indent
    indent="$(printf '%*s' "$PALETTE_PAD_X" '')"
    while IFS= read -r -n 1 -d '' char; do
        [ -z "$line" ] && printf '%s%s' "$indent" "$THEME_ANSI_MUTED"
        if [ "$char" = $'\n' ]; then
            printf '%s\n' "$ANSI_RESET"
            line=''
            continue
        fi
        printf '%s' "$char"
        line="$line$char"
        case "$line" in
            *"] "|*"> ") printf '%s' "$ANSI_RESET"; line='' ;;
        esac
    done
    [ -n "$line" ] && printf '%s\n' "$ANSI_RESET"
    return 0
}

# Run <command...> (a tool that takes its picker options from the caller's env)
# below the title row, with its stdout and stderr through palette_stream_indent.
# Exit 0 shows <ok text>, anything but Esc (130) shows <fail text>; both wait
# for a key so the outcome can be read before the popup closes.
palette_tool_popup() {
    local title="$1" ok_text="$2" fail_text="$3" status outcome indent errexit=''
    shift 3
    indent="$(printf '%*s' "$PALETTE_PAD_X" '')"

    # The shell env may carry FZF_DEFAULT_OPTS like "--tmux center,75%", which makes
    # fzf open a nested popup and deadlock inside display-popup (see the Claude picker).
    unset FZF_DEFAULT_OPTS FZF_DEFAULT_OPTS_FILE FZF_DEFAULT_COMMAND

    # Same spot as fzf's title row, so it stays put while the tool works after the pick.
    printf '\n%s%s\n\n' "$indent" "$(palette_title "$title" "$(palette_body_width)")"

    # The tool's failure is an outcome to show, not a reason for the caller's set -e to exit.
    case "$-" in *e*) errexit=1 ;; esac
    set +e
    "$@" 2>&1 | palette_stream_indent
    status="${PIPESTATUS[0]}"
    [ -n "$errexit" ] && set -e

    [ "$status" -eq "$PALETTE_EXIT_CANCELLED" ] && return 0

    if [ "$status" -eq 0 ]; then
        outcome="${ANSI_BOLD}${THEME_ANSI_ACCENT}${ok_text}${ANSI_RESET}"
    else
        outcome="${ANSI_BOLD}${THEME_ANSI_TITLE_FG}${fail_text}${ANSI_RESET}"
    fi
    printf '\n%s%s   %s%s%s' "$indent" "$outcome" "$THEME_ANSI_MUTED" "$PALETTE_CLOSE_HINT" "$ANSI_RESET"
    IFS= read -r -s -n 1 _ || true
    printf '\n'
}
