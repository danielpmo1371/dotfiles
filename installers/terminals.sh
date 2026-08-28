#!/bin/bash

# Terminal emulators configuration installer
# Handles: Ghostty, Kitty, and other terminal emulators

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"

install_ghostty() {
    log_info "Configuring Ghostty..."

    # Symlink config directory to ~/.config/ghostty
    link_config_dirs "ghostty"

    # macOS: Ghostty also reads from Application Support
    # Symlink the config file there too
    if [[ "$OSTYPE" == "darwin"* ]]; then
        local ghostty_app_support="$HOME/Library/Application Support/com.mitchellh.ghostty"

        if [ -d "$ghostty_app_support" ]; then
            create_symlink_with_backup "$DOTFILES_ROOT/config/ghostty/config" "$ghostty_app_support/config"
        fi
    fi
}

install_kitty() {
    log_info "Configuring Kitty..."

    # Symlink config directory to ~/.config/kitty
    link_config_dirs "kitty"
}

# macOS built-in Terminal.app: set the default profile's font to a Nerd Font so
# Powerlevel10k glyphs and emoji render. Terminal.app cannot be symlinked — it
# holds prefs in memory and rewrites com.apple.Terminal.plist wholesale on quit,
# so `defaults write` from an installer (which itself runs inside Terminal) is
# clobbered. Driving the running app over AppleScript applies live and persists.
# Only the font family is touched; size, colors, and other profiles are left as-is.
TERMINAL_APP_FONT="MesloLGS-NF-Regular"  # PostScript name (fc-scan), not family "MesloLGS NF"

install_terminal_app() {
    [[ "$OSTYPE" == "darwin"* ]] || return 0

    log_info "Configuring Terminal.app font..."

    if ! command -v osascript &>/dev/null; then
        log_warn "osascript not found, skipping Terminal.app font"
        return 0
    fi

    # Resolve the default profile name rather than hardcoding it.
    local profile
    profile="$(defaults read com.apple.Terminal "Default Window Settings" 2>/dev/null)"
    if [[ -z "$profile" ]]; then
        log_warn "Could not read Terminal.app default profile, skipping font"
        return 0
    fi

    local err
    if err="$(osascript -e "tell application \"Terminal\" to set font name of settings set \"$profile\" to \"$TERMINAL_APP_FONT\"" 2>&1)"; then
        log_success "Terminal.app profile '$profile' font -> $TERMINAL_APP_FONT"
    else
        # Most likely: font not installed (run --fonts) or Automation permission denied.
        log_warn "Could not set Terminal.app font (run --fonts, or grant Automation access): $err"
    fi
}

install_terminals() {
    log_header "Terminal Emulators"

    install_ghostty
    install_kitty
    install_terminal_app

    # Add other terminals here as needed:
    # install_alacritty
    # install_wezterm

    echo ""
    log_success "Terminal configuration complete"
    echo ""
    echo "Configured terminals:"
    echo "  - Ghostty (~/.config/ghostty)"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "    + macOS Application Support symlinked"
    fi
    echo "  - Kitty (~/.config/kitty)"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "  - Terminal.app (default profile font)"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_terminals
fi
