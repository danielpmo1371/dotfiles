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
    echo "Next: run ./installers/zsh.sh or ./installers/bash.sh"
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && install_shell_config
