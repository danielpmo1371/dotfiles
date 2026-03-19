#!/bin/bash
# High-resolution image display using iTerm2 inline images protocol
# Ghostty supports this protocol for true image rendering

LOGO_FILE="$HOME/.config/fastfetch/logos/apple.png"

# Try different image protocols in order of preference
if [[ -n "$TMUX" ]]; then
    # In tmux: use sixel if available, otherwise kitty protocol
    if command -v img2sixel &>/dev/null; then
        img2sixel -w 150 -h 150 "$LOGO_FILE"
    else
        # Use chafa with kitty protocol through tmux passthrough
        chafa --format=kitty --size=20x20 "$LOGO_FILE"
    fi
else
    # Outside tmux: use iTerm2 protocol (Ghostty native support)
    if command -v imgcat &>/dev/null; then
        imgcat --width 20 --height 20 "$LOGO_FILE"
    else
        # Fallback: direct iTerm2 inline image protocol
        printf '\033]1337;File=inline=1;width=150px;height=150px:'
        base64 < "$LOGO_FILE"
        printf '\a\n'
    fi
fi

echo ""
fastfetch --logo none
