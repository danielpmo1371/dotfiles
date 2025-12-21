#!/bin/bash

# Secrets template installer
# Creates ~/.accessTokens template for API keys and tokens

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"

install_secrets() {
    log_header "Secrets Template"

    # Create ~/.accessTokens template if it doesn't exist
    if [ ! -f "$HOME/.accessTokens" ]; then
        cat > "$HOME/.accessTokens" << 'EOF'
# Access tokens and API keys - DO NOT COMMIT TO GIT
# This file is sourced by shell configs (env.sh)
#
# Format: export KEY=value
#
# export OPENAI_API_KEY=sk-...
# export ANTHROPIC_API_KEY=sk-ant-...
# export GH_AUTH_TOKEN=github_pat_...
# export AZURE_DEVOPS_EXT_PAT=...
EOF
        chmod 600 "$HOME/.accessTokens"
        log_success "Created ~/.accessTokens template"
    else
        log_info "~/.accessTokens already exists"
    fi

    echo ""
    echo "Add your API keys and tokens to ~/.accessTokens"
    echo "This file is sourced by your shell config automatically."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_secrets
fi
