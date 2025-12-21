#!/bin/bash

# Zsh configuration installer

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"

# Files to symlink: "source:target" (source in config/zsh/, target in $HOME)
ZSH_FILES=(
    "zshrc:.zshrc"
)

install_zsh_config() {
    log_header "Zsh Configuration"

    link_home_files "zsh" "${ZSH_FILES[@]}"

    # Install Zap plugin manager if not present
    local zap_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zap"
    if [ ! -d "$zap_dir" ]; then
        log_info "Installing Zap plugin manager..."
        zsh <(curl -s https://raw.githubusercontent.com/zap-zsh/zap/master/install.zsh) --branch release-v1 --keep
    else
        log_success "Zap already installed"
    fi

    echo ""
    log_info "Zsh config installation complete"
    echo ""
    echo "Plugins (via Zap): powerlevel10k, zsh-autosuggestions, zsh-syntax-highlighting"
    echo ""
    echo "Next steps:"
    echo "  1. Run 'source ~/.zshrc' to reload"
    echo "  2. Run 'p10k configure' to setup prompt"
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && install_zsh_config
