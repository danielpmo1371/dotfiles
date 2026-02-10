#!/bin/bash

# Bash configuration installer

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"

# Files to symlink: "source:target" (source in config/bash/, target in $HOME)
BASH_FILES=(
    "bashrc:.bashrc"
    "bash_aliases:.bash_aliases"
    "bash_path:.bash_path"
)

install_bash_config() {
    log_header "Bash Configuration"

    link_home_files "bash" "${BASH_FILES[@]}"

    echo ""
    log_info "Bash config installation complete"
    log_info "Run 'source ~/.bashrc' to apply changes"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_bash_config
fi
