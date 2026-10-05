#!/usr/bin/env bash
#
# tmux-bt-popup.sh - connect a Bluetooth device with bt-fix in a tmux-palette-style popup
#
# Clicking the Bluetooth glyph in the status bar (#[range=user|bluetooth] in
# config/tmux/themes/*.conf, handled by MouseDown1Status in tmux.conf) opens it,
# and so does "Bluetooth" in the control panel (tmux-control-panel.sh).
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
# Room for the device list (13 rows inside fzf's margins, borders and padding)
# and, after the pick, the title row, bt-fix's progress lines and the outcome.
DEFAULT_POPUP_HEIGHT=20
POPUP_HEIGHT="${TMUX_BT_POPUP_HEIGHT:-$DEFAULT_POPUP_HEIGHT}"
BT_FIX="${TMUX_BT_FIX:-$SCRIPT_DIR/bt-fix}"

load_theme

if [ "${1:-}" = "--popup" ]; then
    palette_popup "$PALETTE_POPUP_WIDTH" "$POPUP_HEIGHT" "$(printf %q "$SCRIPT_PATH")" "${2:-}"
    exit 0
fi

BT_FIX_FZF_OPTS="$(palette_picker_fzf_opts "$POPUP_TITLE" "$POPUP_HINTS" "$SEARCH_GHOST")"
export BT_FIX_FZF_OPTS
palette_tool_popup "$POPUP_TITLE" "$CONNECTED_TEXT" "$NOT_CONNECTED_TEXT" "$BT_FIX"
