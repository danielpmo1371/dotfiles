#!/bin/bash

# Claude Code installer
# Installs: Claude Code CLI (native installer), ACP plugin, config files
#
# Dependencies: curl (for native installer), node/npm (for ACP plugin only)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"

# Files and folders to symlink from config/claude/ to ~/.claude/
CLAUDE_FILES=(
    "CLAUDE.md"
    "settings.json"
    "keybindings.json"
    "commands"
    "skills"
    "scripts"
    "agents"
)

install_claude_code() {
    log_header "Claude Code CLI"

    # Check if already installed
    if command -v claude &> /dev/null; then
        local current_version
        current_version=$(claude --version 2>/dev/null || echo "unknown")
        log_success "Claude Code already installed: $current_version"
        log_info "Updating to latest version..."
    fi

    # Install/update via official native installer (no Node.js dependency)
    if ! command -v curl &> /dev/null; then
        log_error "curl is required for the Claude Code installer"
        return 1
    fi

    log_info "Installing Claude Code via official installer..."
    curl -fsSL https://claude.ai/install.sh | bash -s latest 2>&1 || {
        log_warn "Native installer failed, trying brew as fallback..."
        # Ensure brew is in PATH (may have been installed earlier in the session)
        source "$DOTFILES_ROOT/lib/install-packages.sh" 2>/dev/null || true
        ensure_brew_in_path 2>/dev/null || true
        if command -v brew &> /dev/null; then
            brew install claude-code || {
                log_error "Failed to install Claude Code via both native installer and brew"
                return 1
            }
        else
            log_error "Failed to install Claude Code (native installer failed, brew not available)"
            return 1
        fi
    }

    # Check common install locations and add to PATH if needed
    local claude_search_paths=(
        "$HOME/.local/bin"
        "$HOME/.claude/bin"
    )
    for search_path in "${claude_search_paths[@]}"; do
        if [[ -x "$search_path/claude" ]] && [[ ":$PATH:" != *":$search_path:"* ]]; then
            export PATH="$search_path:$PATH"
        fi
    done

    if command -v claude &> /dev/null; then
        log_success "Claude Code installed: $(claude --version 2>/dev/null || echo 'installed')"
    else
        log_warn "Claude Code binary not found in PATH after install"
    fi

    # Install ACP plugin via npm (still requires node/npm)
    if command -v npm &> /dev/null; then
        local npm_global_dir="$HOME/.npm-global"
        mkdir -p "$npm_global_dir"
        npm config set prefix "$npm_global_dir"

        local acp_pkg="@zed-industries/claude-code-acp"
        if npm list -g "$acp_pkg" &> /dev/null; then
            log_success "$acp_pkg already installed"
        else
            log_info "Installing $acp_pkg..."
            npm install -g "$acp_pkg" || log_warn "Failed to install $acp_pkg (optional)"
        fi
    else
        log_info "npm not available - skipping ACP plugin (optional)"
    fi
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

# Run an installer that delivers hooks referenced by settings.json.
# settings.json registers these hooks unconditionally, so they are dependencies
# of --claude rather than optional extras. A failure is warned about and never
# fatal: a broken hook dependency must not abort the whole --claude run.
run_hook_dependency() {
    local script_name="$1"
    local description="$2"
    local installer="$DOTFILES_ROOT/installers/$script_name"

    if [[ ! -x "$installer" ]]; then
        log_warn "$script_name not found or not executable: $installer"
        return 0
    fi

    log_info "Installing $description (dependency)..."
    if ! "$installer"; then
        log_warn "$description installer reported failures"
    fi
}

install_claude_config() {
    log_header "Claude Code Settings"

    link_target_files "claude" "$HOME/.claude" "${CLAUDE_FILES[@]}"

    # Symlink ~/.claude.json (user-level MCP config) to home directory
    link_home_files "claude" "claude.json:.claude.json"

    # Generate/update settings.local.json for MCP memory service
    ensure_settings_local

    # Install the hooks that settings.json references. The hooks/ directory is
    # not a whole symlink (each installer owns a different part of it), so each
    # one needs its own run:
    #   - claude-azdo-pipeline-hooks.sh: the loose pipeline-*.sh guards
    #   - claude-hooks.sh:               the loose general hooks (No-Delete guard, notification.sh)
    #   - logging-hooks.sh:              the hooks/logging/ directory symlink
    #   - memory-hooks.sh:               hooks/memory/ + hooks/utilities/ (needs network)
    run_hook_dependency "claude-azdo-pipeline-hooks.sh" "Claude AZDO pipeline guard hooks"
    run_hook_dependency "claude-hooks.sh" "Claude general hooks (No-Delete guard, notifications)"
    run_hook_dependency "logging-hooks.sh" "Claude session logging hooks"
    run_hook_dependency "memory-hooks.sh" "Claude MCP memory hooks"

    echo ""
    log_info "Claude settings installation complete"
    echo ""
    echo "Synced items:"
    for item in "${CLAUDE_FILES[@]}"; do
        echo "  - $item"
    done
    echo "  - ~/.claude.json (user-level MCP config)"
    echo "  - ~/.claude/hooks/pipeline-guard.sh (AZDO pipeline guard)"
    echo "  - ~/.claude/hooks/pipeline-trigger-guard.sh (AZDO pipeline guard)"
    echo "  - ~/.claude/hooks/pipeline-registry-write-guard.sh (AZDO pipeline guard)"
    echo "  - ~/.claude/hooks/destructive-ops-guard.sh (No-Delete Rule guard)"
    echo "  - ~/.claude/hooks/notification.sh (desktop notifications)"
    echo "  - ~/.claude/hooks/logging/ (session logging hooks)"
    echo "  - ~/.claude/hooks/memory/, ~/.claude/hooks/utilities/ (MCP memory hooks)"
    echo ""
    echo "Local items (not synced):"
    echo "  - settings.local.json (per-machine permissions)"
    echo "  - .credentials.json (auth tokens)"
    echo "  - history.jsonl, debug/, todos/ (session data)"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_claude_code
    install_claude_config
fi
