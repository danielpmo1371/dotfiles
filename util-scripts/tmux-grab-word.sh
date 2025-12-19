#!/bin/bash
# Script to grab a word from tmux history
# Enters copy mode, scrolls up 7 lines, selects last word, and pastes it

# Enter copy mode
tmux copy-mode

# Scroll up 7 lines
for i in {1..7}; do
    tmux send-keys -X cursor-up
done

# Move to end of line (to position at the last word)
tmux send-keys -X end-of-line

# Move backward by one WORD (capital W behavior - whitespace delimited)
tmux send-keys -X previous-space

# Start visual selection
tmux send-keys -X begin-selection

# Move to end of current word to select it entirely
tmux send-keys -X next-space-end

# Copy selection and exit copy mode
tmux send-keys -X copy-selection-and-cancel

# Paste the copied word at command prompt
tmux paste-buffer
