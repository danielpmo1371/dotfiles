#!/bin/bash

# Claude Code installer
# Installs: Claude Code CLI, CLAUDE.md, settings.json, commands/
#
# Dependencies: node, npm (for Claude Code CLI)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"

# Files and folders to symlink from config/claude/ to ~/.claude/
CLAUDE_FILES=(
    "CLAUDE.md"
    "settings.json"
    "commands"
    "skills"
    "scripts"
    "agents"
)

# NPM packages to install globally
NPM_PACKAGES=(
    "@anthropic-ai/claude-code"
    "@zed-industries/claude-code-acp"
)

install_npm_packages() {
    log_header "Claude Code"

    if ! command -v npm &> /dev/null; then
        log_error "npm is not installed. Please install Node.js first."
        return 1
    fi

    # Configure npm to use user-writable directory for global packages
    local npm_global_dir="$HOME/.npm-global"
    mkdir -p "$npm_global_dir"
    npm config set prefix "$npm_global_dir"

    # Ensure ~/.npm-global/bin is in PATH
    if [[ ":$PATH:" != *":$npm_global_dir/bin:"* ]]; then
        log_info "Note: Add '$npm_global_dir/bin' to your PATH"
        log_info "  Add this line to ~/.bashrc or ~/.zshrc:"
        log_info "  export PATH=\"$npm_global_dir/bin:\$PATH\""
    fi

    for package in "${NPM_PACKAGES[@]}"; do
        if npm list -g "$package" &> /dev/null; then
            log_success "$package is already installed"
        else
            log_info "Installing $package..."
            npm install -g "$package" || {
                log_warn "Failed to install $package, continuing..."
                continue
            }
            log_success "$package installed"
        fi
    done
}

ensure_settings_local() {
    local settings_local="$HOME/.claude/settings.local.json"

    # Ensure ~/.claude/ directory exists
    if [[ ! -d "$HOME/.claude" ]]; then
        mkdir -p "$HOME/.claude"
        log_info "Created ~/.claude/ directory"
    fi

    # Check for jq dependency
    if ! command -v jq &> /dev/null; then
        log_warn "jq is not installed - cannot create/update settings.local.json"
        log_warn "Install jq and re-run: ./install.sh --claude"
        return 1
    fi

    if [[ ! -f "$settings_local" ]]; then
        # File doesn't exist - create it fresh
        log_info "Creating settings.local.json..."
        jq -n '{
            "enableAllProjectMcpServers": true,
            "enabledMcpjsonServers": ["memory"]
        }' > "$settings_local"
        log_success "Created settings.local.json"
    elif [[ ! -s "$settings_local" ]]; then
        # File exists but is empty - recreate it
        log_info "settings.local.json is empty, recreating..."
        jq -n '{
            "enableAllProjectMcpServers": true,
            "enabledMcpjsonServers": ["memory"]
        }' > "$settings_local"
        log_success "Recreated settings.local.json"
    else
        # File exists with content - merge required keys preserving existing content
        log_info "Updating existing settings.local.json..."
        local updated
        updated=$(jq '
            .enableAllProjectMcpServers = true |
            .enabledMcpjsonServers = (
                (.enabledMcpjsonServers // [])
                | if any(. == "memory") then . else . + ["memory"] end
            )
        ' "$settings_local")
        echo "$updated" > "$settings_local"
        log_success "Updated settings.local.json (preserved existing content)"
    fi
}

install_claude_config() {
    log_header "Claude Code Settings"

    link_target_files "claude" "$HOME/.claude" "${CLAUDE_FILES[@]}"

    # Generate/update settings.local.json for MCP memory service
    ensure_settings_local

    echo ""
    log_info "Claude settings installation complete"
    echo ""
    echo "Synced items:"
    for item in "${CLAUDE_FILES[@]}"; do
        echo "  - $item"
    done
    echo ""
    echo "Local items (not synced):"
    echo "  - settings.local.json (per-machine permissions)"
    echo "  - .credentials.json (auth tokens)"
    echo "  - history.jsonl, debug/, todos/ (session data)"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_npm_packages
    install_claude_config
fi
