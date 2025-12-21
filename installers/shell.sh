#!/bin/bash

# Shared shell configuration installer
# Installs: tmux, chafa, .tmux.conf, ~/.accessTokens template

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"
source "$DOTFILES_ROOT/lib/install-packages.sh"

# Files to symlink from dotfiles root to $HOME
DOTFILES=(
    ".tmux.conf"
)

# Packages to install
PACKAGES=(
    "tmux"
    "chafa"
)

install_shell_config() {
    log_header "Shared Shell Configuration"

    # Install required tools
    for pkg in "${PACKAGES[@]}"; do
        install_package "$pkg" "$pkg" "$pkg"
    done

    # Symlink dotfiles
    for file in "${DOTFILES[@]}"; do
        link_dotfile "$file"
    done

    # Install TPM (Tmux Plugin Manager) if not already installed
    if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
        log_info "Installing Tmux Plugin Manager (TPM)..."
        git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
        log_success "TPM installed"

        # Install tmux plugins
        log_info "Installing tmux plugins (this may take a moment)..."
        ~/.tmux/plugins/tpm/bin/install_plugins
        log_success "Tmux plugins installed"
    else
        log_info "TPM already installed, updating plugins..."
        ~/.tmux/plugins/tpm/bin/update_plugins all
    fi

    # Create ~/.accessTokens template if it doesn't exist
    if [ ! -f "$HOME/.accessTokens" ]; then
        cat > "$HOME/.accessTokens" << 'EOF'
# Access tokens and API keys - DO NOT COMMIT TO GIT
# Format: KEY=value (no spaces around =, no quotes needed)
#
# OPENAI_API_KEY=sk-...
# GH_AUTH_TOKEN=github_pat_...
# AZURE_DEVOPS_EXT_PAT=...
EOF
        chmod 600 "$HOME/.accessTokens"
        log_info "Created ~/.accessTokens template"
    fi

    echo ""
    log_info "Shared shell config complete"
    echo ""
    echo "Shared configs in config/shell/:"
    echo "  env.sh, path.sh, aliases.sh, git.sh, tmux.sh"
    echo ""
    echo "Tmux plugins installed:"
    echo "  - TPM (Plugin Manager)"
    echo "  - tmux-gruvbox (Gruvbox dark theme)"
    echo "  - tmux-resurrect (Session saving)"
    echo "  - tmux-continuum (Auto-save/restore)"
    echo "  - tmux-floax (Floating windows)"
    echo "  - tmux-colortag (Window color tags)"
    echo ""
    echo "To reload tmux config: tmux source ~/.tmux.conf"
    echo "To install/update plugins manually: Press prefix + I in tmux"
    echo ""
    echo "Next: run ./installers/zsh.sh or ./installers/bash.sh"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_shell_config
fi
