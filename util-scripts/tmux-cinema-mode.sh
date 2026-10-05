#!/bin/bash
# Toggle cinema/transparency mode for overlaying terminal on movies
# - Ghostty: transparent background, disable shaders (auto-reloads on config change)
# - tmux: transparent backgrounds, hide status bar and pane borders

CINEMA_MARKER="@cinema_mode"
GHOSTTY_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/config"
GHOSTTY_BACKUP="${GHOSTTY_CONFIG}.pre-cinema"

cinema_active=$(tmux show-option -gqv "$CINEMA_MARKER" 2>/dev/null)

if [ "$cinema_active" != "on" ]; then
    # ── ENABLE CINEMA MODE ──────────────────────────────────────────────
    tmux set-option -g "$CINEMA_MARKER" "on"

    # --- Ghostty: save config, then make transparent ---
    if [ -f "$GHOSTTY_CONFIG" ]; then
        cp "$GHOSTTY_CONFIG" "$GHOSTTY_BACKUP"

        # Enable background opacity (uncomment or add)
        if grep -q '^# *background-opacity' "$GHOSTTY_CONFIG"; then
            sed -i '' 's/^# *background-opacity.*/background-opacity = 0.25/' "$GHOSTTY_CONFIG"
        elif ! grep -q '^background-opacity' "$GHOSTTY_CONFIG"; then
            printf '\n# Cinema mode opacity\nbackground-opacity = 0.25\n' >> "$GHOSTTY_CONFIG"
        fi

        # Disable active shaders (comment out any uncommented shader lines)
        sed -i '' '/^[^#]*custom-shader = /s/^/# cinema # /' "$GHOSTTY_CONFIG"
        sed -i '' '/^[^#]*custom-shader-animation/s/^/# cinema # /' "$GHOSTTY_CONFIG"
    fi

    # --- Tmux: make everything transparent ---
    tmux set-option -g status off
    tmux set-option -g pane-border-status off
    tmux set-option -g pane-border-lines hidden 2>/dev/null
    tmux set-option -g pane-border-style "fg=default,bg=default"
    tmux set-option -g pane-active-border-style "fg=default,bg=default"
    tmux set-option -g window-style "bg=default"
    tmux set-option -g window-active-style "bg=default"

    tmux display-message "Cinema mode: ON (prefix+V to toggle)"
else
    # ── DISABLE CINEMA MODE ─────────────────────────────────────────────
    tmux set-option -g "$CINEMA_MARKER" "off"

    # --- Ghostty: restore original config ---
    if [ -f "$GHOSTTY_BACKUP" ]; then
        cp "$GHOSTTY_BACKUP" "$GHOSTTY_CONFIG"
        rm -f "$GHOSTTY_BACKUP"
    fi

    # --- Tmux: restore appearance ---
    tmux set-option -g status on
    # Divider shape back to tmux defaults (tmux.conf leaves them unset)
    tmux set-option -gu pane-border-status
    tmux set-option -gu pane-border-lines
    tmux set-option -gu pane-border-format
    # Border colours come from the active theme (config/tmux/themes)
    "$(dirname "$0")/tmux-theme.sh" apply-saved
    tmux set-option -g window-style "default"
    tmux set-option -g window-active-style "default"

    tmux display-message "Cinema mode: OFF"
fi
