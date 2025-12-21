#!/bin/bash

# Common development tools installer
# Installs CLI tools using preferred package manager

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

# Source common functions
source "$DOTFILES_ROOT/lib/install-common.sh"
source "$DOTFILES_ROOT/lib/install-packages.sh"

install_tools() {
    log_header "Common Development Tools"

    # Let user choose package manager if multiple available
    local manager=$(get_preferred_manager)
    log_info "Using package manager: $manager"
    echo ""

    # Essential tools
    log_info "Installing essential tools..."
    install_package "tmux" "tmux" "tmux"
    install_package "nvim" "neovim" "neovim"
    install_package "git" "git" "git"

    # Modern CLI replacements
    log_info "Installing modern CLI tools..."
    install_package "rg" "ripgrep" "ripgrep" "" "ripgrep"
    install_package "fd" "fd" "fd-find" "" "fd-find"
    install_package "bat" "bat" "bat" "" "bat"
    install_package "lsd" "lsd" "lsd" "" "lsd"
    install_package "zoxide" "zoxide" "zoxide" "" "zoxide"
    install_package "fzf" "fzf" "fzf"

    # Utilities
    log_info "Installing utilities..."
    install_package "jq" "jq" "jq"
    install_package "chafa" "chafa" "chafa"
    install_package "htop" "htop" "htop"
    install_package "tree" "tree" "tree"

    echo ""
    log_info "Tools installation complete"
    echo ""
    echo "Installed tools:"
    echo "  tmux, nvim, git          - essentials"
    echo "  rg, fd, bat, lsd, zoxide - modern replacements"
    echo "  fzf, jq, chafa, htop     - utilities"
    echo ""
    echo "To reset package manager preference: rm ~/.dotfiles_pkg_manager"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_tools
fi
