#!/bin/bash

# Dotfiles Installation Script
# Main entry point for installing all dotfiles configurations

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
source "$SCRIPT_DIR/lib/install-common.sh"

show_help() {
    echo "Dotfiles Installation Script"
    echo ""
    echo "Usage: ./install.sh [options]"
    echo ""
    echo "Options:"
    echo "  --all        Install all configurations (default)"
    echo "  --shell      Install shell config only (bash, tmux)"
    echo "  --claude     Install Claude Code settings only"
    echo "  --help       Show this help message"
    echo ""
}

install_all() {
    log_header "Dotfiles Installation"

    # Install shell configuration
    source "$SCRIPT_DIR/installers/shell.sh"
    install_shell_config

    # Install Claude settings
    source "$SCRIPT_DIR/installers/claude.sh"
    install_claude_config

    log_header "Installation Complete"
    echo "All dotfiles have been installed successfully."
    echo ""
    echo "Next steps:"
    echo "  1. Restart your shell or run: source ~/.bashrc"
    echo "  2. Restart Claude Code to pick up new settings"
    echo ""
}

main() {
    local mode="${1:---all}"

    case "$mode" in
        --help|-h)
            show_help
            ;;
        --shell)
            source "$SCRIPT_DIR/installers/shell.sh"
            install_shell_config
            ;;
        --claude)
            source "$SCRIPT_DIR/installers/claude.sh"
            install_claude_config
            ;;
        --all|*)
            install_all
            ;;
    esac
}

main "$@"
