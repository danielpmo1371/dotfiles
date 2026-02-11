#!/bin/bash

# Common development tools installer
# Installs Homebrew (if needed) and CLI tools
#
# Dependencies: curl (for Homebrew installation)

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
    install_package "tmux" "tmux" "tmux" || log_warn "Failed to install tmux, continuing..."
    install_package "nvim" "neovim" "neovim" || log_warn "Failed to install neovim, continuing..."
    install_package "git" "git" "git" || log_warn "Failed to install git, continuing..."
    install_package "zsh" "zsh" "zsh" || log_warn "Failed to install zsh, continuing..."
    install_package "curl" "curl" "curl" || log_warn "Failed to install curl, continuing..."
    install_package "tldr" "tlrc" "tldr" || log_warn "Failed to install tldr, continuing..."

    # Node.js and npm (required for Claude Code)
    # Note: On most systems, 'node' command may not exist after install, check 'nodejs' too
    install_package "node" "node" "nodejs" || log_warn "Failed to install node, continuing..."
    # npm is sometimes separate package on apt-based systems
    if ! command -v npm &> /dev/null; then
        install_package "npm" "npm" "npm" || log_warn "Failed to install npm, continuing..."
    fi

    # Modern CLI replacements
    log_info "Installing modern CLI tools..."
    install_package "rg" "ripgrep" "ripgrep" "" "ripgrep" || log_warn "Failed to install ripgrep, continuing..."
    install_package "fd" "fd" "fd-find" "" "fd-find" || log_warn "Failed to install fd, continuing..."
    install_package "bat" "bat" "bat" "" "bat" || log_warn "Failed to install bat, continuing..."
    install_package "delta" "git-delta" "git-delta" "" "git-delta" || log_warn "Failed to install git-delta, continuing..."
    install_package "lsd" "lsd" "lsd" "" "lsd" || log_warn "Failed to install lsd, continuing..."
    install_package "zoxide" "zoxide" "zoxide" "" "zoxide" || log_warn "Failed to install zoxide, continuing..."
    install_package "fzf" "fzf" "fzf" || log_warn "Failed to install fzf, continuing..."

    # Utilities
    log_info "Installing utilities..."
    install_package "jq" "jq" "jq" || log_warn "Failed to install jq, continuing..."
    install_package "chafa" "chafa" "chafa" || log_warn "Failed to install chafa, continuing..."
    install_package "htop" "htop" "htop" || log_warn "Failed to install htop, continuing..."
    install_package "btop" "btop" "btop" || log_warn "Failed to install btop, continuing..."
    install_package "tree" "tree" "tree" || log_warn "Failed to install tree, continuing..."
    install_package "gdu" "gdu" "gdu" || log_warn "Failed to install gdu, continuing..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        install_package "terminal-notifier" "terminal-notifier" || log_warn "Failed to install terminal-notifier, continuing..."
    else
        install_package "notify-send" "libnotify" "libnotify-bin" "libnotify" || log_warn "Failed to install libnotify, continuing..."
    fi
    install_package "fastfetch" "fastfetch" "fastfetch" || log_warn "Failed to install fastfetch, continuing..."
    install_package "toilet" "toilet" "toilet" || log_warn "Failed to install toilet, continuing..."
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
