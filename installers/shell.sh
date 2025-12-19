#!/bin/bash

# Shell configuration installer (bash, tmux)
# Installs: .bashrc, .bash_path, .tmux.conf

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

# Source common functions
source "$DOTFILES_ROOT/lib/install-common.sh"

# Files to symlink to home directory
SHELL_FILES=(
    ".bashrc"
    ".bash_path"
    ".tmux.conf"
)

install_shell_config() {
    log_header "Shell Configuration"

    local backup_dir=""

    for file in "${SHELL_FILES[@]}"; do
        local source="$DOTFILES_ROOT/$file"
        local target="$HOME/$file"

        # Create backup dir only when needed (lazy initialization)
        if [ -e "$target" ] && [ ! -L "$target" ] && [ -z "$backup_dir" ]; then
            backup_dir="$(create_backup_dir "shell")"
        fi

        create_symlink "$source" "$target" "$backup_dir"
    done

    echo ""
    log_info "Shell config installation complete"
    log_info "Run 'source ~/.bashrc' to apply changes"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_shell_config
fi
