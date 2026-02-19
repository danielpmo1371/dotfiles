#!/bin/bash
# tmux-shader-picker.sh
# Pick a Ghostty custom shader via fzf inside a tmux popup
#
# Usage:
#   Direct (inside popup):  bash tmux-shader-picker.sh --pick
#   Via tmux keybind:       bash tmux-shader-picker.sh

GHOSTTY_CONFIG="$HOME/.config/ghostty/config"
SHADERS_DIR="$HOME/.config/ghostty/shaders"

pick_shader() {
    local current_shader=""
    # Extract current active shader (relative path after shaders/)
    if grep -q '^custom-shader = ' "$GHOSTTY_CONFIG" 2>/dev/null; then
        current_shader=$(grep '^custom-shader = ' "$GHOSTTY_CONFIG" | head -1 | sed 's|.*shaders/||')
    fi

    # Collect all .glsl files relative to shaders dir
    local shaders
    shaders=$(cd "$SHADERS_DIR" && find . -name '*.glsl' -type f | sed 's|^\./||' | sort)

    if [ -z "$shaders" ]; then
        echo "No shaders found in $SHADERS_DIR"
        read -r -n 1
        return 1
    fi

    # Build display list with active marker
    local choices
    choices=$(
        # "none" option
        if [ -z "$current_shader" ]; then
            printf "\033[33m* none (disable shader)\033[0m\n"
        else
            printf "  none (disable shader)\n"
        fi
        # shader files
        echo "$shaders" | while IFS= read -r name; do
            if [ "$name" = "$current_shader" ]; then
                printf "\033[33m* %s\033[0m\n" "$name"
            else
                printf "  %s\n" "$name"
            fi
        done
    )

    local selected
    selected=$(echo "$choices" | fzf \
        --ansi \
        --header="  Select Ghostty shader (* = active)" \
        --prompt="shader> " \
        --height=100% \
        --reverse \
        --no-info \
        | sed 's/^[* ] //' | sed $'s/\033\\[[0-9;]*m//g')

    [ -z "$selected" ] && return 0

    if [[ "$selected" == "none (disable shader)" ]]; then
        # Comment out all active custom-shader lines
        sed -i '' 's|^custom-shader = |# custom-shader = |' "$GHOSTTY_CONFIG"
        printf "\n  Shader disabled. Reload Ghostty to apply.\n"
    else
        local shader_path="$SHADERS_DIR/$selected"
        if [ ! -f "$shader_path" ]; then
            echo "Shader file not found: $shader_path"
            read -r -n 1
            return 1
        fi

        # Comment out any active custom-shader lines
        sed -i '' 's|^custom-shader = |# custom-shader = |' "$GHOSTTY_CONFIG"

        # Insert new active line after the last commented custom-shader line
        local last_shader_line
        last_shader_line=$(grep -n '# custom-shader = ' "$GHOSTTY_CONFIG" | tail -1 | cut -d: -f1)

        if [ -n "$last_shader_line" ]; then
            sed -i '' "${last_shader_line}a\\
custom-shader = ~/.config/ghostty/shaders/${selected}
" "$GHOSTTY_CONFIG"
        else
            # No shader lines exist, add before custom-shader-animation
            local anim_line
            anim_line=$(grep -n 'custom-shader-animation' "$GHOSTTY_CONFIG" | head -1 | cut -d: -f1)
            if [ -n "$anim_line" ]; then
                sed -i '' "${anim_line}i\\
custom-shader = ~/.config/ghostty/shaders/${selected}
" "$GHOSTTY_CONFIG"
            else
                echo "custom-shader = ~/.config/ghostty/shaders/${selected}" >> "$GHOSTTY_CONFIG"
            fi
        fi

        printf "\n  Shader set to: %s\n  Reload Ghostty to apply.\n" "$selected"
    fi

    sleep 1
}

if [ "$1" = "--pick" ]; then
    pick_shader
else
    tmux display-popup -E -w 60% -h 70% -T " Ghostty Shader Picker " \
        "bash '$0' --pick"
fi
