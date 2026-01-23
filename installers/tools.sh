#!/bin/bash

# Common development tools installer
# Installs Homebrew (if needed) and CLI tools
#
# Dependencies: curl (for Homebrew installation)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

# Source common functions
source "$DOTFILES_ROOT/lib/install-common.sh"
source "$DOTFILES_ROOT/lib/install-packages.sh"

install_tools() {
    log_header "Common Development Tools"

    # Let user choose package manager (will install brew if selected and not present)
    local manager=$(get_preferred_manager)
    if [[ -z "$manager" ]]; then
        log_error "No package manager selected"
        return 1
    fi
    log_info "Using package manager: $manager"
    echo ""

    # Essential tools
    log_info "Installing essential tools..."
    install_package "tmux" "tmux" "tmux"
    install_package "nvim" "neovim" "neovim"
    install_package "git" "git" "git"
    install_package "zsh" "zsh" "zsh"
    install_package "curl" "curl" "curl"
    install_package "tldc" "tldc" "tdlc"

    # Node.js and npm (required for Claude Code)
    # Note: On most systems, 'node' command may not exist after install, check 'nodejs' too
    install_package "node" "node" "nodejs"
    # npm is sometimes separate package on apt-based systems
    if ! command -v npm &> /dev/null; then
        install_package "npm" "npm" "npm"
    fi

    # Modern CLI replacements
    log_info "Installing modern CLI tools..."
    install_package "rg" "ripgrep" "ripgrep" "" "ripgrep"
    install_package "fd" "fd" "fd-find" "" "fd-find"
    install_package "bat" "bat" "bat" "" "bat"
    install_package "delta" "git-delta" "git-delta" "" "git-delta"
    install_package "lsd" "lsd" "lsd" "" "lsd"
    install_package "zoxide" "zoxide" "zoxide" "" "zoxide"
    install_package "fzf" "fzf" "fzf"

    # Utilities
    log_info "Installing utilities..."
    install_package "jq" "jq" "jq"
    install_package "chafa" "chafa" "chafa"
    install_package "htop" "htop" "htop"
    install_package "btop" "btop" "btop"
    install_package "tree" "tree" "tree"
    install_package "gdu" "gdu" "gdu"
    install_package "terminal-notifier" "terminal-notifier" "terminal-notifier"
    # install calcure with pipx install calcure # calendar

    echo ""
    log_info "Tools installation complete"
    echo ""
    echo "Installed tools:"
    echo "  tmux, nvim, git, zsh, curl     - essentials"
    echo "  node, npm                      - JavaScript runtime (for Claude Code)"
    echo "  rg, fd, bat, delta, lsd, zoxide - modern replacements"
    echo "  fzf, jq, chafa, htop, tree     - utilities"
    echo ""
    echo "To reset package manager preference: rm ~/.dotfiles_pkg_manager"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_tools
fi
