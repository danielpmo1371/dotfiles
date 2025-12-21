#!/bin/bash

# Tmux configuration installer
# Installs: tmux, TPM (plugin manager), plugins, and config

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"
source "$DOTFILES_ROOT/lib/install-packages.sh"

install_tmux() {
    log_header "Tmux Configuration"

    # Install tmux
    install_package "tmux" "tmux" "tmux"

    # Symlink tmux.conf from config/tmux to ~/.tmux.conf
    create_symlink "$DOTFILES_ROOT/config/tmux/tmux.conf" "$HOME/.tmux.conf"

    # Verify tmux.conf is in place before proceeding with TPM
    if [ ! -e "$HOME/.tmux.conf" ]; then
        log_error "~/.tmux.conf not found - cannot install TPM plugins"
        return 1
    fi

    # Install TPM (Tmux Plugin Manager) if not already installed
    if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
        log_info "Installing Tmux Plugin Manager (TPM)..."
        git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
        log_success "TPM installed"
    else
        log_info "TPM already installed"
    fi

    # Install/update tmux plugins (TPM reads from ~/.tmux.conf)
    if [ -x "$HOME/.tmux/plugins/tpm/bin/install_plugins" ]; then
        log_info "Installing tmux plugins (this may take a moment)..."

        # TPM needs TMUX_PLUGIN_MANAGER_PATH set via tmux environment
        # Source the config to ensure the variable is set
        if tmux source-file ~/.tmux.conf 2>/dev/null; then
            log_info "Sourced tmux config"
        else
            log_info "Starting tmux server to source config..."
            tmux start-server \; source-file ~/.tmux.conf 2>/dev/null || true
        fi

        if ~/.tmux/plugins/tpm/bin/install_plugins; then
            log_success "Tmux plugins installed"
        else
            log_warn "Plugin installation had issues - try 'prefix + I' in tmux to install manually"
        fi
    else
        log_error "TPM install_plugins script not found or not executable"
        return 1
    fi

    echo ""
    log_success "Tmux configuration complete"
    echo ""
    echo "Plugins installed:"
    echo "  - TPM (Plugin Manager)"
    echo "  - tmux-sensible (Sensible defaults)"
    echo "  - tmux-gruvbox (Gruvbox dark theme)"
    echo "  - tmux-resurrect (Session saving)"
    echo "  - tmux-continuum (Auto-save/restore)"
    echo "  - tmux-floax (Floating windows)"
    echo "  - tmux-colortag (Window color tags)"
    echo ""
    echo "To reload config: tmux source ~/.tmux.conf"
    echo "To install/update plugins manually: prefix + I"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_tmux
fi
