#!/bin/bash

# Configuration directories installer
# Symlinks config folders from dotfiles/config/ to ~/.config/

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"

# Directories to symlink to ~/.config/
CONFIG_DIRS=(
    "nvim"
    "ghostty"
)

install_config_dirs() {
    log_header "Config Directories"

    link_config_dirs "${CONFIG_DIRS[@]}"

    echo ""
    log_info "Config directories installation complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_config_dirs
fi
