#!/bin/bash

# Shared shell configuration installer
# Installs: chafa, ~/.accessTokens template
# Note: tmux is now installed via installers/tmux.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"
source "$DOTFILES_ROOT/lib/install-packages.sh"

install_shell_config() {
    log_header "Shared Shell Configuration"

    # Install shared tools
    install_package "chafa" "chafa" "chafa"

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
    else
        log_info "~/.accessTokens already exists"
    fi

    echo ""
    log_success "Shared shell config complete"
    echo ""
    echo "Shared configs in config/shell/:"
    echo "  env.sh, path.sh, aliases.sh, git.sh, tmux.sh"
    echo ""
    echo "Next steps:"
    echo "  ./installers/tmux.sh  - Install tmux and plugins"
    echo "  ./installers/zsh.sh   - Install zsh configuration"
    echo "  ./installers/bash.sh  - Install bash configuration"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_shell_config
fi
