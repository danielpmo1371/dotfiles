#!/bin/bash

# Homebrew casks installer (macOS GUI applications)
# Installs apps declared in config/brew/Brewfile via `brew bundle`.
# Note: No 'set -e' here - this file is sourced by install.sh via run_installer.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"
source "$DOTFILES_ROOT/lib/install-packages.sh"

BREWFILE="$DOTFILES_ROOT/config/brew/Brewfile"

install_casks() {
    log_header "Homebrew Casks (macOS Applications)"

    # Casks are macOS-only - skip gracefully elsewhere
    if [[ "$OSTYPE" != "darwin"* ]]; then
        log_info "Skipping casks: only supported on macOS (detected: $OSTYPE)"
        return 0
    fi

    if [[ ! -f "$BREWFILE" ]]; then
        log_error "Brewfile not found: $BREWFILE"
        return 1
    fi

    if ! ensure_brew_in_path; then
        log_error "Homebrew not found. Install it first: ./install.sh --brew"
        return 1
    fi

    log_info "Installing casks from $BREWFILE..."
    if brew bundle --file="$BREWFILE"; then
        log_success "All casks installed"
    else
        log_warn "Some casks failed to install (see output above)"
        log_info "Re-run with: ./install.sh --casks"
        return 1
    fi
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_casks
fi
