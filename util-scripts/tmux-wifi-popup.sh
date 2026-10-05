#!/usr/bin/env bash
#
# tmux-wifi-popup.sh - connect to a Wi-Fi network with wifi-pick in a tmux-palette-style popup
#
# Clicking the Wi-Fi glyph in the status bar (#[range=user|wifi] in
# config/tmux/themes/*.conf, handled by MouseDown1Status in tmux.conf) opens it,
# and so does "Wi-Fi" in the control panel (tmux-control-panel.sh). Same look
# and flow as the Bluetooth popup (tmux-bt-popup.sh): wifi-pick's network list
# is restyled through WIFI_PICK_FZF_OPTS, its progress lines and questions
# (password, disconnect) print under the title row, the outcome waits for a
# key, and Esc in the list closes straight away.
#
# Usage:
#   tmux-wifi-popup.sh --popup [client]   open the popup on [client] (tmux's current client if omitted)
#   tmux-wifi-popup.sh                    run wifi-pick with the palette look (needs a tty; what the popup runs)
#
# Env:
#   TMUX_WIFI_PICK           wifi-pick to run (default: the one next to this script)
#   TMUX_WIFI_POPUP_HEIGHT   popup height in lines (default 20, capped by the client)
#
# Must stay bash 3.2 compatible (macOS), like tmux-palette-style.sh.

set -euo pipefail

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# shellcheck source=tmux-palette-style.sh
source "$SCRIPT_DIR/tmux-palette-style.sh"

POPUP_TITLE='Wi-Fi'
POPUP_HINTS='enter connect (or disconnect)   up/down move   esc close'
SEARCH_GHOST='Search'
DONE_TEXT='Done'
NOT_CONNECTED_TEXT='Not connected'
# Room for the network list and, after the pick, the title row, wifi-pick's
# progress lines, the password question and the outcome.
DEFAULT_POPUP_HEIGHT=20
POPUP_HEIGHT="${TMUX_WIFI_POPUP_HEIGHT:-$DEFAULT_POPUP_HEIGHT}"
WIFI_PICK="${TMUX_WIFI_PICK:-$SCRIPT_DIR/wifi-pick}"

load_theme

if [ "${1:-}" = "--popup" ]; then
    palette_popup "$PALETTE_POPUP_WIDTH" "$POPUP_HEIGHT" "$(printf %q "$SCRIPT_PATH")" "${2:-}"
    exit 0
fi

WIFI_PICK_FZF_OPTS="$(palette_picker_fzf_opts "$POPUP_TITLE" "$POPUP_HINTS" "$SEARCH_GHOST")"
export WIFI_PICK_FZF_OPTS
palette_tool_popup "$POPUP_TITLE" "$DONE_TEXT" "$NOT_CONNECTED_TEXT" "$WIFI_PICK"
