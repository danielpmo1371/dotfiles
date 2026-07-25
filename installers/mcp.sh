#!/bin/bash

# MCP (Model Context Protocol) Configuration Installer
# Syncs MCP servers from canonical source to Claude tools:
# - Claude Code CLI (~/.claude.json) - always synced
# - Claude Desktop - opt-in with --desktop flag (experimental)
#
# Usage:
#   ./installers/mcp.sh           # Sync to Claude Code CLI only
#   ./installers/mcp.sh --desktop # Also sync to Claude Desktop


# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/install-common.sh"
source "$SCRIPT_DIR/../lib/secrets.sh"

# Configuration paths
DOTFILES_ROOT="$(get_dotfiles_root)"
SERVERS_SOURCE="$DOTFILES_ROOT/config/mcp/servers.json"
CLAUDE_CODE_CONFIG="$HOME/.claude.json"
CLAUDE_DESKTOP_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"

# Flags
SYNC_DESKTOP=false

# Rewrite secret:KEY_NAME references in env blocks to ${KEY_NAME}
# Claude Code expands ${VAR} from its environment when it spawns the server, so the
# credential never lands on disk. The shell exports these from the OS keychain
# (config/shell/secrets.sh), which stays the single source of truth.
#
# Caveat: this relies on the consuming app inheriting the shell environment. True for
# the Claude Code CLI; NOT true for GUI-launched Claude Desktop (--desktop), which
# would see an empty value. Desktop sync is opt-in and off by default for that reason.
resolve_secrets() {
    local config_file="$1"
    local has_secrets
    has_secrets=$(jq -r '
        [.mcpServers // {} | to_entries[] | .value.env // {} | to_entries[] |
         select(.value | startswith("secret:"))] | length
    ' "$config_file")

    if [[ "$has_secrets" -gt 0 ]]; then
        log_info "Rewriting $has_secrets secret reference(s) to \${VAR} expansion..."

        local tmpfile
        tmpfile=$(mktemp)

        # Extract secret references and point them at the environment
        jq -r '
            .mcpServers // {} | to_entries[] |
            .key as $server |
            .value.env // {} | to_entries[] |
            select(.value | startswith("secret:")) |
            "\($server)\t\(.key)\t\(.value | ltrimstr("secret:"))"
        ' "$config_file" | while IFS=$'\t' read -r server env_key secret_key; do
            jq --arg server "$server" --arg key "$env_key" --arg val "\${${secret_key}}" '
                .mcpServers[$server].env[$key] = $val
            ' "$config_file" > "$tmpfile" && mv "$tmpfile" "$config_file"

            # The value arrives at runtime from the environment, so check the keychain can
            # supply it now - otherwise the server fails later with an opaque auth error.
            if [[ -n "$(secret "$secret_key" 2>/dev/null)" ]]; then
                log_success "Linked $server.$env_key -> \${$secret_key}"
            else
                log_warn "Secret '$secret_key' not in keychain; $server.$env_key will be empty at runtime"
            fi
        done
    fi

    # NOT gated on has_secrets above — a server can have an args/url secret
    # with no env secret at all (browser-network is exactly that case), and
    # an early return here would silently skip resolving those.
    resolve_arg_secrets "$config_file"
    resolve_url_secrets "$config_file"
}

# Same rewrite as resolve_secrets, but for positional args (e.g. the
# azure-devops server's org name, which the package takes as argv not env).
#
# UNTESTED: env blocks are documented to get ${VAR} expansion when Claude Code
# spawns the server; it is NOT verified whether the same expansion applies to
# args. If it doesn't, the server receives the literal string "${VAR}" and
# fails loudly/obviously at connect time — deliberately: substituting the raw
# secret value into args instead would put it in plaintext in ~/.claude.json,
# defeating the entire point of this indirection. Fails loud, not silently
# insecure. If this turns out not to work, args-based secrets need Claude
# Code's own template/expansion feature, not something this installer can
# work around alone.
resolve_arg_secrets() {
    local config_file="$1"
    local has_arg_secrets
    has_arg_secrets=$(jq -r '
        [.mcpServers // {} | to_entries[] | .value.args // [] | .[] |
         select(type == "string" and startswith("secret:"))] | length
    ' "$config_file")

    if [[ "$has_arg_secrets" -eq 0 ]]; then
        return 0
    fi

    log_info "Rewriting $has_arg_secrets secret reference(s) in args to \${VAR} expansion (untested for args — see comment above)..."

    local tmpfile
    tmpfile=$(mktemp)

    jq -r '
        .mcpServers // {} | to_entries[] |
        .key as $server |
        (.value.args // []) | to_entries[] |
        select(.value | type == "string" and startswith("secret:")) |
        "\($server)\t\(.key)\t\(.value | ltrimstr("secret:"))"
    ' "$config_file" | while IFS=$'\t' read -r server arg_index secret_key; do
        jq --arg server "$server" --argjson idx "$arg_index" --arg val "\${${secret_key}}" '
            .mcpServers[$server].args[$idx] = $val
        ' "$config_file" > "$tmpfile" && mv "$tmpfile" "$config_file"

        if [[ -n "$(secret "$secret_key" 2>/dev/null)" ]]; then
            log_success "Linked $server.args[$arg_index] -> \${$secret_key}"
        else
            log_warn "Secret '$secret_key' not in keychain; $server.args[$arg_index] will be literal \${$secret_key} at runtime"
        fi
    done
}

# Same rewrite as resolve_secrets, but for a top-level "url" field (e.g. an
# SSE/HTTP server whose endpoint embeds a private-network host, like
# browser-network). The whole url is stored as one secret — this does
# whole-value substitution only, not partial ${VAR}-in-a-string templating
# (that's the templating layer docs/plans/open-source-architecture-plan.md
# Phase 2 already scopes; this is the minimal fix that doesn't require it).
resolve_url_secrets() {
    local config_file="$1"
    local has_url_secrets
    has_url_secrets=$(jq -r '
        [.mcpServers // {} | to_entries[] | .value.url // empty |
         select(type == "string" and startswith("secret:"))] | length
    ' "$config_file")

    if [[ "$has_url_secrets" -eq 0 ]]; then
        return 0
    fi

    log_info "Rewriting $has_url_secrets secret reference(s) in url to \${VAR} expansion..."

    local tmpfile
    tmpfile=$(mktemp)

    jq -r '
        .mcpServers // {} | to_entries[] |
        select(.value.url? | type == "string" and startswith("secret:")) |
        "\(.key)\t\(.value.url | ltrimstr("secret:"))"
    ' "$config_file" | while IFS=$'\t' read -r server secret_key; do
        jq --arg server "$server" --arg val "\${${secret_key}}" '
            .mcpServers[$server].url = $val
        ' "$config_file" > "$tmpfile" && mv "$tmpfile" "$config_file"

        if [[ -n "$(secret "$secret_key" 2>/dev/null)" ]]; then
            log_success "Linked $server.url -> \${$secret_key}"
        else
            log_warn "Secret '$secret_key' not in keychain; $server.url will be literal \${$secret_key} at runtime"
        fi
    done
}

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
    resolve_secrets "$CLAUDE_CODE_CONFIG"
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
    resolve_secrets "$CLAUDE_DESKTOP_CONFIG"

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
