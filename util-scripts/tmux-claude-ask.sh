#!/bin/bash
# tmux-claude-ask.sh
# Sends a question to the persistent claude-popup session and opens the popup
#
# Usage: tmux-claude-ask.sh "<question>"

QUESTION="$1"
SESSION_NAME="claude-popup"
POPUP_WIDTH="85%"
POPUP_HEIGHT="85%"
DOTFILES_DIR="$HOME/repos/dotfiles"
LOCK_FILE="/tmp/tmux-claude-popup.lock"

if [ -z "$QUESTION" ]; then
    exit 0
fi

if [ -z "$TMUX" ]; then
    echo "Error: Must be run from within tmux"
    exit 1
fi

if ! command -v claude &> /dev/null; then
    tmux display-message "claude not found. Install with: npm install -g @anthropic-ai/claude-code"
    exit 1
fi

# Ensure the claude-popup session exists
if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    # Create session detached, start claude in the dotfiles dir
    tmux new-session -d -s "$SESSION_NAME" -c "$DOTFILES_DIR" "claude"
    # Give claude a moment to start up
    sleep 2
fi

# Send the question as keystrokes to the claude session
tmux send-keys -t "$SESSION_NAME" "$QUESTION" Enter

# Open the popup showing the claude session
touch "$LOCK_FILE"
tmux display-popup -E -w "$POPUP_WIDTH" -h "$POPUP_HEIGHT" \
    "tmux attach-session -t $SESSION_NAME; rm -f $LOCK_FILE"
rm -f "$LOCK_FILE"
