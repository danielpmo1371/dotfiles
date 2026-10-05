#!/usr/bin/env bash
#
# tmux-control-panel.sh - a palette-style control panel for the machine's quick settings
#
# prefix + C-c (tmux.conf) opens it: a list in the Ctrl+P palette look (see
# tmux-palette-style.sh) whose entries open the matching tool in the same popup
# or flip a status-bar toggle:
#   Wi-Fi          wifi-pick in the palette look (tmux-wifi-popup.sh)
#   Bluetooth      bt-fix in the palette look (tmux-bt-popup.sh)
#   tmux theme     the theme picker (tmux-theme.sh --pick; live preview, Enter saves)
#   Weather        swap the battery segment for today's weather and back (@power_weather)
#   Clock          collapse the date/time to an icon and back (@datetime_collapsed)
#   Control hub    toggle the desktop hub card (hub-shell; listed only when installed)
# The Wi-Fi and Bluetooth entries are the same popups the status-bar glyphs open.
#
# Usage:
#   tmux-control-panel.sh --popup [client]   open the panel on [client] (tmux's current client if omitted)
#   tmux-control-panel.sh [client]           run the panel (needs a tty; what the popup runs)
#
# Env:
#   TMUX_CONTROL_PANEL_HEIGHT   popup height in lines (default 20, capped by the client;
#                               the Wi-Fi and Bluetooth tools run in it)
#
# Must stay bash 3.2 compatible (macOS), like tmux-palette-style.sh.

set -euo pipefail

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# shellcheck source=tmux-palette-style.sh
source "$SCRIPT_DIR/tmux-palette-style.sh"

POPUP_TITLE='Control panel'
POPUP_HINTS='enter open   up/down move   esc close'
SEARCH_GHOST='Search'
# Same height as the Wi-Fi and Bluetooth popups, which run inside this one.
DEFAULT_POPUP_HEIGHT=20
POPUP_HEIGHT="${TMUX_CONTROL_PANEL_HEIGHT:-$DEFAULT_POPUP_HEIGHT}"
NAME_WIDTH=16

WIFI_POPUP="$SCRIPT_DIR/tmux-wifi-popup.sh"
BT_POPUP="$SCRIPT_DIR/tmux-bt-popup.sh"
THEME_PICKER="$SCRIPT_DIR/tmux-theme.sh"
HUB_SHELL="hub-shell"

load_theme

if [ "${1:-}" = "--popup" ]; then
    client="${2:-}"
    command="$(printf %q "$SCRIPT_PATH")"
    [ -n "$client" ] && command="$command $(printf %q "$client")"
    palette_popup "$PALETTE_POPUP_WIDTH" "$POPUP_HEIGHT" "$command" "$client"
    exit 0
fi

CLIENT="${1:-}"

# One entry per line: action <tab> label (glyph, name, muted description).
entry() {
    printf '%s\t%s  %-*s %s%s%s\n' "$1" "$2" "$NAME_WIDTH" "$3" "$THEME_ANSI_MUTED" "$4" "$ANSI_RESET"
}

entries() {
    entry wifi      '󰖩'    'Wi-Fi'       'connect, switch or disconnect a network'
    entry bluetooth '󰂯'      'Bluetooth'   'connect or re-pair a device'
    entry theme     '󰏘'   'tmux theme'  'pick the status bar colours'
    entry weather   '󰖐' 'Weather'     'swap the battery for the weather and back'
    entry clock     '󰥔'   'Clock'       'collapse the date and time to an icon and back'
    if command -v "$HUB_SHELL" >/dev/null 2>&1; then
        entry hub   '󰕮'     'Control hub' 'show or hide the desktop hub'
    fi
    return 0
}

# Flip a 0/1 tmux option the status bar reads, and redraw the status line.
toggle_option() {
    tmux set -gF "$1" "#{?$1,0,1}"
    if [ -n "$CLIENT" ]; then
        tmux refresh-client -t "$CLIENT" -S
    else
        tmux refresh-client -S
    fi
}

# The shell env may carry FZF_DEFAULT_OPTS like "--tmux center,75%", which makes
# fzf open a nested popup and deadlock inside display-popup (see the Claude picker).
unset FZF_DEFAULT_OPTS FZF_DEFAULT_OPTS_FILE FZF_DEFAULT_COMMAND

fzf_opts=()
while IFS= read -r opt; do
    fzf_opts+=("$opt")
done <<EOF
$(palette_picker_fzf_opts "$POPUP_TITLE" "$POPUP_HINTS" "$SEARCH_GHOST")
EOF

choice="$(entries | fzf "${fzf_opts[@]}" --delimiter="$PALETTE_FIELD_SEPARATOR" --with-nth=2..)" || exit 0
action="${choice%%"$PALETTE_FIELD_SEPARATOR"*}"

case "$action" in
    wifi)      exec "$WIFI_POPUP" ;;
    bluetooth) exec "$BT_POPUP" ;;
    theme)     exec "$THEME_PICKER" --pick ;;
    weather)   toggle_option @power_weather ;;
    clock)     toggle_option @datetime_collapsed ;;
    hub)       "$HUB_SHELL" toggle >/dev/null 2>&1 || true ;;
esac
