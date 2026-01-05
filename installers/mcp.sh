#!/bin/bash

# MCP (Model Context Protocol) Configuration Installer
# This script sets up MCP configuration for Claude Code

set -e  # Exit on error

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/install-common.sh"

main() {
    log_header "Setting up MCP configuration"

    # Create ~/.mcp.json symlink to config/mcp/mcp.json
    log_info "Creating MCP configuration symlink..."
    local mcp_config="$(get_dotfiles_root)/config/mcp/mcp.json"
    local target_file="$HOME/.mcp.json"

    if [ -f "$mcp_config" ]; then
        create_symlink "$mcp_config" "$target_file"
        log_success "MCP configuration linked to ~/.mcp.json"
    else
        log_error "MCP configuration not found at $mcp_config"
        exit 1
    fi

    # Handle environment variables
    local dotfiles_root="$(get_dotfiles_root)"
    local env_template="$dotfiles_root/config/mcp/mcp-env.template"
    local env_local="$dotfiles_root/config/mcp/mcp-env.local"

    if [ ! -f "$env_local" ] && [ -f "$env_template" ]; then
        log_info "Creating mcp-env.local from template..."
        cp "$env_template" "$env_local"
        log_warn "Please edit $env_local and add your API keys"
    fi

    # Add gitignore for local files
    local gitignore="$dotfiles_root/config/mcp/.gitignore"
    if [ ! -f "$gitignore" ]; then
        echo "mcp-env.local" > "$gitignore"
        echo "*.local" >> "$gitignore"
        log_info "Created .gitignore for MCP local files"
    fi

    # Check if Node.js is installed (required for npx)
    if ! command -v node &> /dev/null; then
        log_warn "Node.js is not installed. MCP servers require Node.js and npm."
        log_warn "Install Node.js to use MCP servers."
    else
        log_success "Node.js detected: $(node --version)"
    fi

    # Check if npx is available
    if ! command -v npx &> /dev/null; then
        log_warn "npx is not available. Installing npm if needed..."
        if command -v npm &> /dev/null; then
            npm install -g npx
        else
            log_error "npm is not installed. Please install Node.js and npm."
        fi
    else
        log_success "npx is available"
    fi

    # Provide instructions for API keys
    log_header "MCP Configuration Complete"
    echo ""
    echo "Next steps:"
    echo "1. Edit $env_local with your API keys"
    echo "2. Source the environment variables before starting Claude Code:"
    echo "   export \$(grep -v '^#' $env_local | xargs)"
    echo "3. Restart Claude Code to load MCP servers"
    echo ""
    echo "Available MCP servers:"
    echo "  - memory: Long-term memory server (at http://192.168.1.107:8000)"
    echo "  - task-master-ai: Task management and planning"
    echo ""
    echo "To upgrade task-master tools tier, edit ~/.mcp.json"
    echo "and change TASK_MASTER_TOOLS from 'core' to 'standard' or 'all'"

    log_success "MCP installation complete!"
}

main "$@"