#!/usr/bin/env bash
#
# tmux-claude-corner.sh - Toggle Claude processes display in corner pane
# Wrapper script that uses tmux-corner-pane.sh with show-claude-processes.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "$SCRIPT_DIR/tmux-corner-pane.sh" \
    "$SCRIPT_DIR/show-claude-processes.sh" \
    60 \
    25% \
    30%
