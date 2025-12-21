#!/bin/bash

# Configuration directories installer
# Symlinks config folders (e.g., nvim) from dotfiles to ~/.config/

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

# Source common functions
source "$DOTFILES_ROOT/lib/install-common.sh"

# Directories to symlink to ~/.config/
CONFIG_DIRS=(
  "nvim"
)

install_config_dirs() {
  log_header "Config Directories"

  local backup_dir=""

  for dir in "${CONFIG_DIRS[@]}"; do
    local source="$DOTFILES_ROOT/config/$dir"
    local target="$HOME/.config/$dir"

    # Create backup dir only when needed (lazy initialization)
    if [ -e "$target" ] && [ ! -L "$target" ] && [ -z "$backup_dir" ]; then
      backup_dir="$(create_backup_dir "config-dirs")"
    fi

    create_symlink "$source" "$target" "$backup_dir"
  done

  echo ""
  log_info "Config directories installation complete"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  install_config_dirs
fi
