#!/bin/bash
# Toggle tmux zen mode with padding effect
# Hides status bar and pane borders for distraction-free view

ZEN_STATE_FILE="/tmp/tmux-zen-mode-$$"
ZEN_MARKER="@zen_mode"

# Check current zen state
zen_active=$(tmux show-option -gqv "$ZEN_MARKER")

if [ "$zen_active" != "on" ]; then
    # Save current state
    tmux set-option -g "$ZEN_MARKER" "on"

    # Hide status bar
    tmux set-option -g status off

    # Hide pane borders (tmux 3.2+)
    tmux set-option -g pane-border-lines hidden 2>/dev/null
    tmux set-option -g pane-border-style "fg=default,bg=default"
    tmux set-option -g pane-active-border-style "fg=default,bg=default"

    # Add padding effect using window margins (requires tmux 3.4+)
    # Falls back gracefully on older versions
    tmux set-option -g pane-border-indicators off 2>/dev/null

    # Set window padding via popup-style workaround isn't practical
    # Instead, use a subtle visual cue - slightly different background
    tmux set-option -g window-style "bg=default"
    tmux set-option -g window-active-style "bg=default"

    tmux display-message "Zen mode: ON (prefix+Z to exit)"
else
    # Restore normal mode
    tmux set-option -g "$ZEN_MARKER" "off"

    # Show status bar
    tmux set-option -g status on

    # Restore pane borders
    tmux set-option -g pane-border-lines single 2>/dev/null
    tmux set-option -g pane-border-style "fg=#3c3836"
    tmux set-option -g pane-active-border-style "fg=#504945"
    tmux set-option -g pane-border-indicators colour 2>/dev/null

    # Reset window styles
    tmux set-option -g window-style "default"
    tmux set-option -g window-active-style "default"

    tmux display-message "Zen mode: OFF"
fi
