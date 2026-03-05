#!/bin/bash

# Secrets management installer
# Installs nuvemlabs/secrets library and sets up native OS secret store
# (macOS Keychain / Linux libsecret)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"
source "$DOTFILES_ROOT/lib/install-packages.sh"

SECRETS_INSTALL_DIR="${HOME}/.local/lib/secrets"

# TODO: Update to GitHub URL when nuvemlabs/secrets is published
# SECRETS_REPO="https://github.com/nuvemlabs/secrets.git"
SECRETS_LOCAL_REPO="${HOME}/repos/secrets"

install_secrets() {
    log_header "Secrets Management"

    # ── Platform detection ──────────────────────────────────────────────────
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
            echo "Without secret-tool, secrets will fall back to file-based storage"
        else
            log_success "secret-tool found - using libsecret"
        fi
    fi

    # ── Install nuvemlabs/secrets library ───────────────────────────────────
    if [[ -f "$SECRETS_INSTALL_DIR/secrets.sh" ]]; then
        log_success "nuvemlabs/secrets already installed at $SECRETS_INSTALL_DIR"
    else
        log_info "Installing nuvemlabs/secrets library..."

        if [[ -f "$SECRETS_LOCAL_REPO/install.sh" ]]; then
            # Install from local clone
            SECRETS_INSTALL_DIR="$SECRETS_INSTALL_DIR" bash "$SECRETS_LOCAL_REPO/install.sh"
            log_success "Installed nuvemlabs/secrets from local repo"
        # TODO: Uncomment when nuvemlabs/secrets is published to GitHub
        # elif command -v git &>/dev/null; then
        #     local tmpdir
        #     tmpdir=$(mktemp -d)
        #     git clone --depth 1 "$SECRETS_REPO" "$tmpdir" && \
        #         SECRETS_INSTALL_DIR="$SECRETS_INSTALL_DIR" bash "$tmpdir/install.sh"
        #     rm -rf "$tmpdir"
        #     log_success "Installed nuvemlabs/secrets from GitHub"
        else
            log_error "Cannot install nuvemlabs/secrets: local repo not found at $SECRETS_LOCAL_REPO"
            log_info "Clone it first: git clone https://github.com/nuvemlabs/secrets.git $SECRETS_LOCAL_REPO"
            return 1
        fi
    fi

    # ── Migration check ─────────────────────────────────────────────────────
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
