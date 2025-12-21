#!/bin/bash

# Claude Code settings installer
# Installs: Claude Code CLI, ACP, CLAUDE.md, settings.json, skills/, workflow docs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

# Source common functions
source "$DOTFILES_ROOT/lib/install-common.sh"

DOTFILES_CLAUDE_DIR="$DOTFILES_ROOT/.claude"
TARGET_CLAUDE_DIR="$HOME/.claude"

# Files and folders to symlink
CLAUDE_ITEMS=(
    "CLAUDE.md"
    "settings.json"
    "skills"
    "AGENT_HANDOVER_PROMPT.md"
    "ITERATIVE_WORKFLOW.md"
)

# NPM packages to install globally
NPM_PACKAGES=(
    "@anthropics/claude-code"
    "@zed-industries/claude-code-acp"
)

install_npm_packages() {
    log_header "Claude Code NPM Packages"

    # Check if npm is available
    if ! command -v npm &> /dev/null; then
        log_error "npm is not installed. Please install Node.js first."
        return 1
    fi

    for package in "${NPM_PACKAGES[@]}"; do
        if npm list -g "$package" &> /dev/null; then
            log_info "$package is already installed"
        else
            log_info "Installing $package..."
            npm install -g "$package"
            log_info "$package installed successfully"
        fi
    done
}

install_claude_config() {
    log_header "Claude Code Settings"

    # Check if dotfiles .claude directory exists
    if [ ! -d "$DOTFILES_CLAUDE_DIR" ]; then
        log_error "Dotfiles Claude directory not found: $DOTFILES_CLAUDE_DIR"
        return 1
    fi

    # Create ~/.claude if it doesn't exist
    ensure_dir "$TARGET_CLAUDE_DIR"

    local backup_dir=""

    for item in "${CLAUDE_ITEMS[@]}"; do
        local source="$DOTFILES_CLAUDE_DIR/$item"
        local target="$TARGET_CLAUDE_DIR/$item"

        # Create backup dir only when needed
        if [ -e "$target" ] && [ ! -L "$target" ] && [ -z "$backup_dir" ]; then
            backup_dir="$(create_backup_dir "claude")"
        fi

        create_symlink "$source" "$target" "$backup_dir"
    done

    echo ""
    log_info "Claude settings installation complete"
    echo ""
    echo "Synced items:"
    for item in "${CLAUDE_ITEMS[@]}"; do
        if [ -L "$TARGET_CLAUDE_DIR/$item" ]; then
            echo "  - $item"
        fi
    done
    echo ""
    echo "Local items (not synced):"
    echo "  - settings.local.json (per-machine permissions)"
    echo "  - .credentials.json (auth tokens)"
    echo "  - debug/, file-history/, etc. (session data)"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_npm_packages
    install_claude_config
fi
