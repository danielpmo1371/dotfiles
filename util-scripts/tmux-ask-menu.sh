#!/bin/bash
# tmux-ask-menu.sh
# Combined menu for Help and Ask Claude
#
# Usage: Bound to prefix + ? in tmux.conf
#   [h] Help       - keybindings cheat sheet
#   [a] Ask Claude - input prompt, feeds question to claude-popup session

SCRIPTS_DIR="$HOME/repos/dotfiles/util-scripts"

tmux display-menu -T " Claude & Help " \
    "Help  (keybindings)"    h "run-shell '$SCRIPTS_DIR/tmux-help-popup.sh'" \
    "Ask Claude"             a "command-prompt -p 'Ask Claude:' \"run-shell '$SCRIPTS_DIR/tmux-claude-ask.sh \\\"%%\\\"'\""
