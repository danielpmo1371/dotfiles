#!/bin/bash

# Git configuration installer
# Sets up global gitignore and optional git config
#
# Configures:
#   - Global gitignore (~/.config/git/ignore)
#   - Core git settings (optional)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"

install_git_config() {
    log_header "Git Configuration"

    # Ensure git config directory exists
    ensure_dir "$HOME/.config/git"

    # Symlink global gitignore
    local ignore_source="$DOTFILES_ROOT/config/git/ignore"
    local ignore_target="$HOME/.config/git/ignore"

    if [[ -f "$ignore_source" ]]; then
        create_symlink_with_backup "$ignore_source" "$ignore_target" "git"
        log_success "Global gitignore configured"
    else
        log_warn "Git ignore file not found: $ignore_source"
    fi

    # Set core.excludesfile if not already set
    local current_excludes
    current_excludes=$(git config --global core.excludesfile 2>/dev/null || echo "")

    if [[ -z "$current_excludes" ]]; then
        git config --global core.excludesfile "$ignore_target"
        log_success "Set git core.excludesfile"
    elif [[ "$current_excludes" != "$ignore_target" ]]; then
        log_info "core.excludesfile already set to: $current_excludes"
        log_info "To use dotfiles gitignore, run:"
        log_info "  git config --global core.excludesfile $ignore_target"
    fi

    # Display current git user config (informational)
    echo ""
    log_info "Current git user configuration:"
    local git_name git_email
    git_name=$(git config --global user.name 2>/dev/null || echo "(not set)")
    git_email=$(git config --global user.email 2>/dev/null || echo "(not set)")
    echo "  user.name:  $git_name"
    echo "  user.email: $git_email"

    if [[ "$git_name" == "(not set)" || "$git_email" == "(not set)" ]]; then
        echo ""
        log_info "To set git user, run:"
        echo "  git config --global user.name \"Your Name\""
        echo "  git config --global user.email \"your@email.com\""
    fi

    echo ""
    log_success "Git configuration complete"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_git_config
fi
