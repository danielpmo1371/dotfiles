#!/usr/bin/env bash
#
# tmux-bt-popup.sh - connect a Bluetooth device with bt-fix in a tmux-palette-style popup
#
# Clicking the Bluetooth glyph in the status bar (#[range=user|bluetooth] in
# config/tmux/themes/*.conf, handled by MouseDown1Status in tmux.conf) opens it.
# The popup looks like the Ctrl+P palette and the Claude picker (borderless,
# centred, panel-coloured body; see tmux-palette-style.sh): bt-fix's device list
# is restyled through BT_FIX_FZF_OPTS, and bt-fix's progress lines (scanning,
# pairing, the "[y/N]" question) print in the popup under the title row. When
# bt-fix finishes, its outcome stays on screen until a key is pressed; Esc in
# the device list (bt-fix exit 130) closes the popup straight away.
#
# Usage:
#   tmux-bt-popup.sh --popup [client]   open the popup on [client] (tmux's current client if omitted)
#   tmux-bt-popup.sh                    run bt-fix with the palette look (needs a tty; what the popup runs)
#
# Env:
#   TMUX_BT_FIX            bt-fix to run (default: the one next to this script)
#   TMUX_BT_POPUP_HEIGHT   popup height in lines (default 20, capped by the client)
#
# Must stay bash 3.2 compatible (macOS), like tmux-palette-style.sh.

set -euo pipefail

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# shellcheck source=tmux-palette-style.sh
source "$SCRIPT_DIR/tmux-palette-style.sh"

POPUP_TITLE='Bluetooth'
POPUP_HINTS='enter connect   up/down move   esc close'
SEARCH_GHOST='Search'
CONNECTED_TEXT='Connected'
NOT_CONNECTED_TEXT='Not connected'
CLOSE_HINT='press any key to close'
# Room for the device list (13 rows inside fzf's margins, borders and padding)
# and, after the pick, the title row, bt-fix's progress lines and the outcome.
DEFAULT_POPUP_HEIGHT=20
POPUP_HEIGHT="${TMUX_BT_POPUP_HEIGHT:-$DEFAULT_POPUP_HEIGHT}"
BT_FIX="${TMUX_BT_FIX:-$SCRIPT_DIR/bt-fix}"

# bt-fix exit codes (see its header)
BT_FIX_EXIT_CONNECTED=0
BT_FIX_EXIT_CANCELLED=130

load_theme

if [ "${1:-}" = "--popup" ]; then
    palette_popup "$PALETTE_POPUP_WIDTH" "$POPUP_HEIGHT" "$(printf %q "$SCRIPT_PATH")" "${2:-}"
    exit 0
fi

INDENT="$(printf '%*s' "$PALETTE_PAD_X" '')"
body_width="$(palette_body_width)"

# The fzf options bt-fix appends to its own, one per line: the Claude picker's
# layout and colour roles (muted rows, bold current row on the selected bg,
# accent prompt and pointer, panel bg) with the palette title row and hints.
# --header= drops bt-fix's own header; the title row says what this is.
palette_fzf_opts() {
    printf '%s\n' \
        '--ansi' \
        '--layout=reverse' \
        "--margin=1,$PALETTE_PAD_X" \
        '--border=bottom' \
        '--padding=0,0,1,0' \
        "--border-label=$POPUP_HINTS" \
        '--border-label-pos=1:bottom' \
        '--input-border=horizontal' \
        "--input-label=$(palette_title "$POPUP_TITLE" "$body_width")" \
        '--input-label-pos=1' \
        '--info=hidden' \
        '--no-scrollbar' \
        '--highlight-line' \
        "--pointer=$PALETTE_MARKER_GLYPH" \
        '--gutter= ' \
        "--prompt=${THEME_ANSI_ACCENT}${PALETTE_MARKER_GLYPH} ${ANSI_RESET}" \
        "--ghost=$SEARCH_GHOST" \
        '--header=' \
        "--color=$(palette_fzf_colors)"
}

# Copy bt-fix's output through character by character (a question has no
# newline yet and must show at once), indented to the body and muted like the
# palette's descriptions. A line ending in "] " or "> " is a question waiting
# for input (bt-fix's "[y/N] ", select's "device number> "): the terminal echoes
# the answer's Enter, so the next output starts a new line and gets indented.
indent_stream() {
    local char line=''
    while IFS= read -r -n 1 -d '' char; do
        [ -z "$line" ] && printf '%s%s' "$INDENT" "$THEME_ANSI_MUTED"
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

# The shell env may carry FZF_DEFAULT_OPTS like "--tmux center,75%", which makes
# fzf open a nested popup and deadlock inside display-popup (see the Claude picker).
unset FZF_DEFAULT_OPTS FZF_DEFAULT_OPTS_FILE FZF_DEFAULT_COMMAND

# Same spot as fzf's title row, so it stays put while bt-fix works after the pick.
printf '\n%s%s\n\n' "$INDENT" "$(palette_title "$POPUP_TITLE" "$body_width")"

set +e
BT_FIX_FZF_OPTS="$(palette_fzf_opts)" "$BT_FIX" 2>&1 | indent_stream
bt_fix_status="${PIPESTATUS[0]}"
set -e

[ "$bt_fix_status" -eq "$BT_FIX_EXIT_CANCELLED" ] && exit 0

if [ "$bt_fix_status" -eq "$BT_FIX_EXIT_CONNECTED" ]; then
    outcome="${ANSI_BOLD}${THEME_ANSI_ACCENT}${CONNECTED_TEXT}${ANSI_RESET}"
else
    outcome="${ANSI_BOLD}${THEME_ANSI_TITLE_FG}${NOT_CONNECTED_TEXT}${ANSI_RESET}"
fi
printf '\n%s%s   %s%s%s' "$INDENT" "$outcome" "$THEME_ANSI_MUTED" "$CLOSE_HINT" "$ANSI_RESET"
IFS= read -r -s -n 1 _ || true
printf '\n'
