#!/bin/bash

# MCP (Model Context Protocol) Configuration Installer
# Syncs MCP servers from canonical source to Claude tools:
# - Claude Code CLI (~/.claude.json) - always synced
# - Claude Desktop - opt-in with --desktop flag (experimental)
#
# Usage:
#   ./installers/mcp.sh           # Sync to Claude Code CLI only
#   ./installers/mcp.sh --desktop # Also sync to Claude Desktop

set -e  # Exit on error

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/install-common.sh"

# Configuration paths
DOTFILES_ROOT="$(get_dotfiles_root)"
SERVERS_SOURCE="$DOTFILES_ROOT/config/mcp/servers.json"
CLAUDE_CODE_CONFIG="$HOME/.claude.json"
CLAUDE_DESKTOP_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"

# Flags
SYNC_DESKTOP=false

sync_to_claude_code() {
    log_info "Syncing MCP servers to Claude Code CLI..."

    if [ ! -f "$CLAUDE_CODE_CONFIG" ]; then
        log_info "Creating new ~/.claude.json..."
        echo '{"mcpServers": {}}' > "$CLAUDE_CODE_CONFIG"
    else
        backup_copy "$CLAUDE_CODE_CONFIG" "mcp"
    fi

    # Merge servers into existing config (preserves other settings)
    local merged
    merged=$(jq -s '
        .[0] as $existing |
        .[1] as $servers |
        $existing * {mcpServers: ($existing.mcpServers // {}) * $servers}
    ' "$CLAUDE_CODE_CONFIG" "$SERVERS_SOURCE")

    echo "$merged" > "$CLAUDE_CODE_CONFIG"
    log_success "Updated ~/.claude.json with MCP servers"
}

sync_to_claude_desktop() {
    log_info "Syncing MCP servers to Claude Desktop..."

    local config_dir
    config_dir="$(dirname "$CLAUDE_DESKTOP_CONFIG")"

    # Create directory if it doesn't exist
    if [ ! -d "$config_dir" ]; then
        log_info "Creating Claude Desktop config directory..."
        mkdir -p "$config_dir"
    fi

    if [ ! -f "$CLAUDE_DESKTOP_CONFIG" ]; then
        log_info "Creating new claude_desktop_config.json..."
        echo '{"mcpServers": {}}' > "$CLAUDE_DESKTOP_CONFIG"
    else
        backup_copy "$CLAUDE_DESKTOP_CONFIG" "mcp"
    fi

    # Filter to only stdio servers (Claude Desktop doesn't support HTTP servers)
    # Replace mcpServers entirely (preserves other settings like preferences)
    local merged
    merged=$(jq -s '
        .[0] as $existing |
        .[1] as $servers |
        ($servers | to_entries | map(select((.value.type == "http") | not)) | from_entries) as $stdio_only |
        $existing | .mcpServers = $stdio_only
    ' "$CLAUDE_DESKTOP_CONFIG" "$SERVERS_SOURCE")

    echo "$merged" > "$CLAUDE_DESKTOP_CONFIG"

    # Show which servers were skipped
    local skipped
    skipped=$(jq -r 'to_entries | map(select(.value.type == "http")) | .[].key' "$SERVERS_SOURCE")
    if [ -n "$skipped" ]; then
        log_warn "Skipped HTTP servers (not supported by Claude Desktop): $skipped"
    fi

    log_success "Updated Claude Desktop config with MCP servers"
}

check_dependencies() {
    # Check jq
    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed. Please install jq first."
        exit 1
    fi

    # Check Node.js (required for npx-based servers)
    if ! command -v node &> /dev/null; then
        log_warn "Node.js is not installed. MCP servers using npx will not work."
    else
        log_success "Node.js detected: $(node --version)"
    fi

    # Check npx
    if ! command -v npx &> /dev/null; then
        log_warn "npx is not available. MCP servers using npx will not work."
    fi
}

show_servers() {
    log_info "Configured MCP servers:"
    jq -r 'keys[]' "$SERVERS_SOURCE" | while read -r server; do
        local type
        type=$(jq -r --arg s "$server" '.[$s].type // "stdio"' "$SERVERS_SOURCE")
        echo "  - $server ($type)"
    done
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --desktop)
                SYNC_DESKTOP=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    log_header "Syncing MCP Configuration"

    # Verify source exists
    if [ ! -f "$SERVERS_SOURCE" ]; then
        log_error "Canonical servers config not found at $SERVERS_SOURCE"
        exit 1
    fi

    check_dependencies

    # Initialize backup session
    backup_init "mcp"

    # Sync to Claude Code CLI (always)
    sync_to_claude_code

    # Sync to Claude Desktop (opt-in, macOS only)
    if [[ "$SYNC_DESKTOP" == "true" ]]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            log_warn "Claude Desktop sync is experimental - MCP servers may not work correctly"
            sync_to_claude_desktop
        else
            log_info "Skipping Claude Desktop sync (not macOS)"
        fi
    else
        log_info "Skipping Claude Desktop sync (use --desktop to enable)"
    fi

    # Finalize backup session
    backup_finish

    log_header "MCP Sync Complete"
    show_servers

    echo ""
    echo "Targets updated:"
    echo "  - Claude Code CLI: ~/.claude.json"
    if [[ "$SYNC_DESKTOP" == "true" && "$OSTYPE" == "darwin"* ]]; then
        echo "  - Claude Desktop: ~/Library/Application Support/Claude/claude_desktop_config.json"
    fi
    echo ""
    echo "Restart Claude Code to load the new servers."
    echo ""
    echo "To add/modify servers, edit:"
    echo "  $SERVERS_SOURCE"
    echo "Then run: ./install.sh --mcp"
    echo ""
    echo "For Claude Desktop (experimental): ./installers/mcp.sh --desktop"

    log_success "MCP sync complete!"
}

main "$@"
