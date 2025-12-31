#!/usr/bin/env bash
#
# tmux-corner-pane.sh - Toggle a floating corner info display in top-right
# Usage: tmux-corner-pane.sh <command_script> [refresh_interval] [width] [height]
#
# Parameters:
#   command_script    - Path to script that outputs content to display
#   refresh_interval  - Seconds between refreshes (default: 60)
#   width            - Popup width percentage (default: 25%)
#   height           - Popup height percentage (default: 30%)
#
# Example:
#   tmux-corner-pane.sh ~/scripts/show-info.sh 30 20% 25%
#

# Parameters
COMMAND_SCRIPT="${1:-}"
REFRESH_INTERVAL="${2:-60}"
POPUP_WIDTH="${3:-25%}"
POPUP_HEIGHT="${4:-30%}"

# Validate command script
if [ -z "$COMMAND_SCRIPT" ]; then
    echo "Error: No command script provided"
    echo "Usage: $0 <command_script> [refresh_interval] [width] [height]"
    exit 1
fi

if [ ! -f "$COMMAND_SCRIPT" ] || [ ! -x "$COMMAND_SCRIPT" ]; then
    echo "Error: Command script '$COMMAND_SCRIPT' not found or not executable"
    exit 1
fi

# Configuration
POPUP_MARKER="/tmp/tmux-corner-popup-$(basename "$COMMAND_SCRIPT")-active"

# Position: top-right corner
POPUP_X="100%"
POPUP_Y="0"

# Check if popup is currently running
popup_exists() {
    [ -f "$POPUP_MARKER" ]
}

# Kill the popup
kill_popup() {
    if [ -f "$POPUP_MARKER" ]; then
        local popup_pid=$(cat "$POPUP_MARKER")
        kill "$popup_pid" 2>/dev/null
        rm -f "$POPUP_MARKER"
    fi
}

# Create the floating popup
create_popup() {
    # Create a temporary script that will run in the popup
    local temp_script="/tmp/tmux-corner-info-$$"

    cat > "$temp_script" <<POPUP_SCRIPT
#!/usr/bin/env bash

# Save PID for tracking
echo \$\$ > "$POPUP_MARKER"

# Cleanup on exit
trap 'rm -f "$POPUP_MARKER"' EXIT

# Use watch with the command script for auto-refresh
# -t: no title, -n: interval in seconds
exec watch -t -n $REFRESH_INTERVAL "$COMMAND_SCRIPT"
POPUP_SCRIPT

    chmod +x "$temp_script"

    # Launch floating popup in top-right corner (non-blocking)
    # -E flag closes popup when command exits
    # For scrolling: Use Cmd+e [ to enter copy mode, then j/k to scroll
    tmux display-popup \
        -x "$POPUP_X" \
        -y "$POPUP_Y" \
        -w "$POPUP_WIDTH" \
        -h "$POPUP_HEIGHT" \
        -E \
        -d "#{pane_current_path}" \
        "$temp_script; rm -f $temp_script" &
}

# Toggle the popup
toggle_popup() {
    if popup_exists; then
        kill_popup
    else
        create_popup &
    fi
}

# Main execution
toggle_popup
