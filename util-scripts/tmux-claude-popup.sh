#!/bin/bash
# tmux-claude-popup.sh
# True toggle for Claude Code CLI in a floating tmux popup with persistent session
#
# Usage (macOS with Ghostty):
#   - Toggle: Cmd+e Cmd+n    (opens/closes popup)
#   - Close:  Cmd+e q        (explicit close, works anywhere)
#   - Close:  Esc            (closes popup, session persists)
#   - Kill:   exit           (terminate Claude and session entirely)
#
# Note: Ctrl+d is disabled globally in tmux.conf to prevent accidental closes

SESSION_NAME="claude-popup"
POPUP_WIDTH="85%"
POPUP_HEIGHT="85%"
LOCK_FILE="/tmp/tmux-claude-popup.lock"

# Check if we're running inside tmux
if [ -z "$TMUX" ]; then
    echo "Error: This script must be run from within tmux"
    exit 1
fi

# Check if claude is available
if ! command -v claude &> /dev/null; then
    echo "Error: claude command not found. Install with: npm install -g @anthropic-ai/claude-code"
    exit 1
fi

# Check if popup is currently open by checking if we're in the popup session
current_session=$(tmux display-message -p '#S' 2>/dev/null)
if [ "$current_session" = "$SESSION_NAME" ]; then
    # We're inside the popup, detach to close it
    tmux detach-client
    exit 0
fi

# Check if lock file exists (popup is open)
if [ -f "$LOCK_FILE" ]; then
    # Popup is open, kill it by finding and killing the popup pane
    # Remove lock file
    rm -f "$LOCK_FILE"

    # Kill any tmux popup windows
    tmux list-clients -F '#{client_name} #{client_flags}' | \
        grep popup | \
        awk '{print $1}' | \
        xargs -I {} tmux detach-client -t {} 2>/dev/null || true
else
    # Popup is not open, create lock file and open it
    touch "$LOCK_FILE"

    # Check if the session already exists
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        # Session exists, attach to it in a popup
        tmux display-popup -E -w "$POPUP_WIDTH" -h "$POPUP_HEIGHT" \
            "tmux attach-session -t $SESSION_NAME; rm -f $LOCK_FILE"
    else
        # Create new session and start claude
        tmux display-popup -E -w "$POPUP_WIDTH" -h "$POPUP_HEIGHT" \
            "tmux new-session -s $SESSION_NAME claude; rm -f $LOCK_FILE"
    fi

    # Clean up lock file after popup closes
    rm -f "$LOCK_FILE"
fi
