#!/bin/bash

# Zsh configuration installer
# Installs: .zshrc, Zap plugin manager, powerlevel10k

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

# Source common functions
source "$DOTFILES_ROOT/lib/install-common.sh"

install_zsh_config() {
    log_header "Zsh Configuration"

    local backup_dir=""

    # Symlink zshrc
    local zshrc_source="$DOTFILES_ROOT/config/zsh/zshrc"
    local zshrc_target="$HOME/.zshrc"

    if [ -e "$zshrc_target" ] && [ ! -L "$zshrc_target" ]; then
        backup_dir="$(create_backup_dir "zsh")"
    fi
    create_symlink "$zshrc_source" "$zshrc_target" "$backup_dir"

    # Install Zap plugin manager if not present
    local zap_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zap"
    if [ ! -d "$zap_dir" ]; then
        log_info "Installing Zap plugin manager..."
        zsh <(curl -s https://raw.githubusercontent.com/zap-zsh/zap/master/install.zsh) --branch release-v1 --keep
    else
        log_info "Zap already installed"
    fi

    echo ""
    log_info "Zsh config installation complete"
    echo ""
    echo "Structure:"
    echo "  ~/.zshrc -> dotfiles/config/zsh/zshrc"
    echo ""
    echo "Plugins (via Zap):"
    echo "  - powerlevel10k (prompt)"
    echo "  - zsh-autosuggestions"
    echo "  - zsh-syntax-highlighting"
    echo ""
    echo "Next steps:"
    echo "  1. Run 'source ~/.zshrc' to reload"
    echo "  2. Run 'p10k configure' to setup prompt"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_zsh_config
fi
