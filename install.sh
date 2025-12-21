#!/bin/bash

# Dotfiles Installation Script
# Main entry point for installing all dotfiles configurations
#
# Installation Order & Dependencies:
#   1. tools.sh      - Base dev tools (git, nvim, chafa, etc.) - no dependencies
#   2. secrets.sh    - Create ~/.accessTokens template - no dependencies
#   3. terminals.sh  - Terminal emulators (Ghostty, etc.) - no dependencies
#   4. tmux.sh       - Tmux + TPM + plugins - requires: git, terminal config
#   5. bash.sh       - Bash configuration - no dependencies
#   6. zsh.sh        - Zsh configuration + Zap - requires: git, zsh, curl
#   7. config-dirs.sh - Symlink config directories (nvim) - no dependencies
#   8. claude.sh     - Claude Code CLI + settings - requires: node, npm

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
    echo "  --tools        Install common dev tools (git, nvim, chafa, ripgrep, etc.)"
    echo "  --secrets      Create ~/.accessTokens template"
    echo "  --tmux         Install tmux and plugins (requires: git)"
    echo "  --bash         Install bash configuration"
    echo "  --zsh          Install zsh configuration (requires: git, zsh, curl)"
    echo "  --nushell      Install nushell configuration (includes starship)"
    echo "  --terminals    Install terminal emulators config (Ghostty, etc.)"
    echo "  --config-dirs  Symlink config directories (nvim)"
    echo "  --claude       Install Claude Code settings (requires: node, npm)"
    echo "  --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./install.sh              # Install everything (recommended)"
    echo "  ./install.sh --zsh        # Install only zsh config"
    echo "  ./install.sh --tools      # Install only dev tools"
    echo ""
    echo "Note: Running --all ensures correct installation order."
    echo "      Individual installers may warn about missing dependencies."
    echo ""
}

# Check if a command exists
check_dependency() {
    local cmd="$1"
    local installer="$2"
    if ! command -v "$cmd" &> /dev/null; then
        log_warn "Missing dependency: $cmd (needed for $installer)"
        log_info "Run './install.sh --tools' first, or './install.sh --all'"
        return 1
    fi
    return 0
}

run_installer() {
    local installer="$1"
    local func="$2"
    local install_root="$SCRIPT_DIR"

    if [ -f "$install_root/installers/$installer" ]; then
        source "$install_root/installers/$installer"
        $func
        # Restore SCRIPT_DIR in case installer changed it
        SCRIPT_DIR="$install_root"
    else
        log_error "Installer not found: $installer"
        return 1
    fi
}

install_all() {
    log_header "Full Dotfiles Installation"

    # Install tools first
    run_installer "tools.sh" "install_tools"

    # Create secrets template
    run_installer "secrets.sh" "install_secrets"

    # Install terminal emulators config (before tmux - tmux needs terminal keybindings)
    run_installer "terminals.sh" "install_terminals"

    # Install tmux
    run_installer "tmux.sh" "install_tmux"

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
        --secrets)
            run_installer "secrets.sh" "install_secrets"
            ;;
        --tmux)
            run_installer "tmux.sh" "install_tmux"
            ;;
        --bash)
            run_installer "bash.sh" "install_bash_config"
            ;;
        --zsh)
            run_installer "zsh.sh" "install_zsh_config"
            ;;
        --nushell)
            run_installer "nushell.sh" "install_nushell_config"
            ;;
        --terminals)
            run_installer "terminals.sh" "install_terminals"
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
