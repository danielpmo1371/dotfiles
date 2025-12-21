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
    echo "  --all          Install everything (default)"
    echo "  --tools        Install common dev tools (tmux, nvim, ripgrep, etc.)"
    echo "  --shell        Install shared shell config (tmux, chafa, .accessTokens)"
    echo "  --bash         Install bash configuration"
    echo "  --zsh          Install zsh configuration (includes Zap)"
    echo "  --config-dirs  Symlink config directories (nvim, ghostty)"
    echo "  --claude       Install Claude Code settings"
    echo "  --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./install.sh              # Install everything"
    echo "  ./install.sh --zsh        # Install only zsh config"
    echo "  ./install.sh --tools      # Install only dev tools"
    echo ""
}

run_installer() {
    local installer="$1"
    local func="$2"

    if [ -f "$SCRIPT_DIR/installers/$installer" ]; then
        source "$SCRIPT_DIR/installers/$installer"
        $func
    else
        log_error "Installer not found: $installer"
        return 1
    fi
}

install_all() {
    log_header "Full Dotfiles Installation"

    # Install tools first
    run_installer "tools.sh" "install_tools"

    # Install shared shell config
    run_installer "shell.sh" "install_shell_config"

    # Install shell-specific configs
    run_installer "bash.sh" "install_bash_config"
    run_installer "zsh.sh" "install_zsh_config"

    # Symlink config directories
    run_installer "config-dirs.sh" "install_config_dirs"

    # Install Claude settings
    run_installer "claude.sh" "install_npm_packages"
    run_installer "claude.sh" "install_claude_config"

    log_header "Installation Complete"
    echo "All dotfiles have been installed successfully."
    echo ""
    echo "Next steps:"
    echo "  1. Restart your shell or run: source ~/.zshrc (or ~/.bashrc)"
    echo "  2. Run 'p10k configure' to setup powerlevel10k prompt"
    echo "  3. Restart Claude Code to pick up new settings"
    echo ""
}

main() {
    local mode="${1:---all}"

    case "$mode" in
        --help|-h)
            show_help
            ;;
        --tools)
            run_installer "tools.sh" "install_tools"
            ;;
        --shell)
            run_installer "shell.sh" "install_shell_config"
            ;;
        --bash)
            run_installer "bash.sh" "install_bash_config"
            ;;
        --zsh)
            run_installer "zsh.sh" "install_zsh_config"
            ;;
        --config-dirs)
            run_installer "config-dirs.sh" "install_config_dirs"
            ;;
        --claude)
            run_installer "claude.sh" "install_npm_packages"
            run_installer "claude.sh" "install_claude_config"
            ;;
        --all|*)
            install_all
            ;;
    esac
}

main "$@"
