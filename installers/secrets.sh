#!/bin/bash

# Secrets management installer
# Installs the nuvemlabs/secrets library and secrets-bridge, and sets up the native OS secret store
# (macOS Keychain / Linux libsecret)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"
source "$DOTFILES_ROOT/lib/install-packages.sh"

SECRETS_INSTALL_DIR="${HOME}/.local/lib/secrets"

SECRETS_REPO_URL="https://github.com/nuvemlabs/secrets.git"
SECRETS_LOCAL_REPO="${HOME}/repos/secrets"
SECRETS_BRIDGE_REPO_URL="https://github.com/nuvemlabs/secrets-bridge.git"
SECRETS_BRIDGE_LOCAL_REPO="${HOME}/repos/secrets-bridge"
# Package prefixes checked for an AUR / Homebrew install
SECRETS_PACKAGE_PREFIXES=(/usr "${HOMEBREW_PREFIX:-/opt/homebrew}" /usr/local)

# Clone <url> into <dir> unless a checkout with an install.sh is already there.
# The clone stays in ~/repos as the working copy later installs update from.
_secrets_ensure_clone() {
    local url="$1" dir="$2"
    [[ -f "$dir/install.sh" ]] && return 0
    if ! command -v git &>/dev/null; then
        log_error "git not found: cannot clone $url"
        return 1
    fi
    if [[ -e "$dir" ]]; then
        log_error "$dir exists but has no install.sh; not touching it"
        return 1
    fi
    log_info "Cloning $url into $dir"
    mkdir -p "$(dirname "$dir")"
    git clone --quiet "$url" "$dir"
}

# secrets-bridge: fetches cloud and wallet secrets into .env, Postman and
# Bruno files on top of the secrets library. Optional: a failure warns.
install_secrets_bridge() {
    local prefix
    if [[ -x "$HOME/.local/bin/secrets-bridge" ]]; then
        log_success "secrets-bridge already installed at $HOME/.local/lib/secrets-bridge"
        return 0
    fi
    for prefix in "${SECRETS_PACKAGE_PREFIXES[@]}"; do
        if [[ -x "$prefix/bin/secrets-bridge" ]]; then
            log_success "secrets-bridge installed by a package at $prefix"
            return 0
        fi
    done
    command -v python3 &>/dev/null || log_warn "secrets-bridge needs python3 at runtime"
    if _secrets_ensure_clone "$SECRETS_BRIDGE_REPO_URL" "$SECRETS_BRIDGE_LOCAL_REPO" &&
       bash "$SECRETS_BRIDGE_LOCAL_REPO/install.sh"; then
        log_success "Installed secrets-bridge from $SECRETS_BRIDGE_LOCAL_REPO"
    else
        log_warn "secrets-bridge not installed (optional); see $SECRETS_BRIDGE_REPO_URL"
    fi
}

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

    # ── Install nuvemlabs/secrets library + CLI tools ───────────────────────
    # Library AND doctor must both be present, or (re)run the installer —
    # machines that installed before the CLI tools existed pick them up here.
    # A package (AUR, Homebrew) installs both into one prefix and owns
    # upgrades, so it counts as installed; config/shell/secrets.sh finds it.
    local pkg_prefix packaged_prefix=""
    for pkg_prefix in "${SECRETS_PACKAGE_PREFIXES[@]}"; do
        if [[ -f "$pkg_prefix/lib/secrets/secrets.sh" && -x "$pkg_prefix/bin/secrets-doctor" ]]; then
            packaged_prefix="$pkg_prefix"
            break
        fi
    done

    if [[ -f "$SECRETS_INSTALL_DIR/secrets.sh" && -x "$HOME/.local/bin/secrets-doctor" ]]; then
        log_success "nuvemlabs/secrets already installed at $SECRETS_INSTALL_DIR"
    elif [[ -n "$packaged_prefix" ]]; then
        log_success "nuvemlabs/secrets installed by a package at $packaged_prefix/lib/secrets"
    else
        log_info "Installing nuvemlabs/secrets library..."

        if _secrets_ensure_clone "$SECRETS_REPO_URL" "$SECRETS_LOCAL_REPO" &&
           SECRETS_INSTALL_DIR="$SECRETS_INSTALL_DIR" bash "$SECRETS_LOCAL_REPO/install.sh"; then
            log_success "Installed nuvemlabs/secrets from $SECRETS_LOCAL_REPO"
        else
            log_error "Cannot install nuvemlabs/secrets (clone $SECRETS_REPO_URL into $SECRETS_LOCAL_REPO, or: brew install nuvemlabs/tap/secrets)"
            return 1
        fi
    fi

    install_secrets_bridge

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
