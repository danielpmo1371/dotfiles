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

    # All base tools install in ONE batch transaction per manager (installing
    # them one-by-one makes pacman/apt re-run post-transaction hooks per package,
    # which dominated install time). install_packages_fast batches, then recovers
    # any straggler individually (correct per-manager name + on-demand brew
    # fallback for tools the native repo lacks).
    #
    # Spec format: "cmd|brew_pkg|apt_pkg|pacman_pkg" (empty fields take defaults;
    # pacman defaults to the apt name, so only override where Arch differs).
    log_info "Installing base tools..."
    local specs=(
        "tmux|tmux|tmux|"
        "nvim|neovim|neovim|"
        "git|git|git|"
        "zsh|zsh|zsh|"
        "curl|curl|curl|"
        "tldr|tlrc|tldr|"
        "node|node|nodejs|"
        "rg|ripgrep|ripgrep|"
        "fd|fd|fd-find|fd"
        "bat|bat|bat|"
        "delta|git-delta|git-delta|"
        "lsd|lsd|lsd|"
        "zoxide|zoxide|zoxide|"
        "fzf|fzf|fzf|"
        "jq|jq|jq|"
        "htop|htop|htop|"
        "btop|btop|btop|"
        "lazydocker|lazydocker|lazydocker|"
        "tree|tree|tree|"
        "gdu|gdu|gdu|"
        "fastfetch|fastfetch|fastfetch|"
    )
    # Platform-specific desktop notifier
    if [[ "$OSTYPE" == "darwin"* ]]; then
        specs+=("terminal-notifier|terminal-notifier|terminal-notifier|")
    else
        specs+=("notify-send|libnotify|libnotify-bin|libnotify")
    fi
    # toilet removed: the Arch package drags in libcaca -> mesa -> llvm-libs
    # (~300 MB) for a cosmetic ASCII-art banner. Not worth it.

    install_packages_fast "${specs[@]}"

    # npm is sometimes a separate package on apt-based systems (node above pulls
    # it on most, but Debian/Ubuntu split it out).
    if ! command -v npm &> /dev/null; then
        install_package "npm" "npm" "npm" || log_warn "Failed to install npm, continuing..."
    fi

    echo ""
    log_info "Tools installation complete"
    echo ""
    echo "Installed tools:"
    echo "  tmux, nvim, git, zsh, curl     - essentials"
    echo "  node, npm                      - JavaScript runtime (for Claude Code)"
    echo "  rg, fd, bat, delta, lsd, zoxide - modern replacements"
    echo "  fzf, jq, htop, tree            - utilities"
    echo "  lazydocker                     - docker TUI"
    echo ""
    echo "To reset package manager preference: rm ~/.dotfiles_pkg_manager"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_tools
fi
