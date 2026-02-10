#!/bin/bash

# Terminal emulators configuration installer
# Handles: Ghostty, and other terminal emulators

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

install_terminals() {
    log_header "Terminal Emulators"

    install_ghostty

    # Add other terminals here as needed:
    # install_kitty
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
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_terminals
fi
