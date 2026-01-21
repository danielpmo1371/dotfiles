#!/bin/bash

# Secrets management installer
# Sets up native OS secret store (macOS Keychain / Linux libsecret)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"
source "$DOTFILES_ROOT/lib/install-packages.sh"

install_secrets() {
    log_header "Secrets Management"

    # Detect platform and check for required tools
    if [[ "$OSTYPE" == darwin* ]]; then
        log_success "macOS detected - using Keychain (built-in)"
    else
        # Linux - check for secret-tool (libsecret)
        if ! command -v secret-tool &>/dev/null; then
            log_warn "secret-tool not found - required for secure secret storage on Linux"
            echo ""
            echo "Install libsecret-tools for your distro:"
            echo "  Ubuntu/Debian: sudo apt install libsecret-tools"
            echo "  Fedora:        sudo dnf install libsecret"
            echo "  Arch:          sudo pacman -S libsecret"
            echo ""
            echo "Without secret-tool, secrets will fall back to ~/.accessTokens file"
        else
            log_success "secret-tool found - using libsecret"
        fi
    fi

    # Source the secrets library
    source "$DOTFILES_ROOT/lib/secrets.sh"

    # Check if migration is needed
    if [[ -f "$HOME/.accessTokens" ]]; then
        log_info "Found ~/.accessTokens - will auto-migrate on next shell startup"
        echo ""
        echo "To migrate immediately, run: secrets_migrate"
    fi

    echo ""
    echo "Secrets management commands:"
    echo "  secret KEY              - Get a secret"
    echo "  secret_set KEY VALUE    - Store a secret"
    echo "  secret_list             - List all stored keys"
    echo "  secret_delete KEY       - Remove a secret"
    echo "  secrets_migrate         - Manually trigger migration from ~/.accessTokens"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_secrets
fi
