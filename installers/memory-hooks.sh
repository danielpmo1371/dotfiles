#!/usr/bin/env bash
#
# Memory Hooks Installer
# Downloads and configures mcp-memory-service hooks for Claude Code
#
# Usage: ./memory-hooks.sh [--dry-run]
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

# Source common functions
source "$DOTFILES_ROOT/lib/install-common.sh"

# Configuration
MEMORY_SERVICE_REPO="https://raw.githubusercontent.com/doobidoo/mcp-memory-service/main"
HOOKS_DIR="$DOTFILES_ROOT/config/claude/hooks/memory"
SETTINGS_FILE="$DOTFILES_ROOT/config/claude/settings.json"
TARGET_HOOKS_DIR="$HOME/.claude/hooks/memory"

# Hook files to download
HOOK_FILES=(
  "session-start.js"
  "session-end.js"
  "permission-request.js"
  "mid-conversation.js"
  "auto-capture-hook.js"
)

# Utility files required by hooks
UTILITY_FILES=(
  "adaptive-pattern-detector.js"
  "auto-capture-patterns.js"
  "context-formatter.js"
  "context-shift-detector.js"
  "conversation-analyzer.js"
  "dynamic-context-updater.js"
  "git-analyzer.js"
  "mcp-client.js"
  "memory-client.js"
  "memory-scorer.js"
  "performance-manager.js"
  "project-detector.js"
  "session-tracker.js"
  "tiered-conversation-monitor.js"
  "user-override-detector.js"
  "version-checker.js"
)

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  log_info "Running in dry-run mode"
fi

download_hooks() {
  log_info "Downloading memory hooks from mcp-memory-service..."

  mkdir -p "$HOOKS_DIR"
  mkdir -p "$HOOKS_DIR/../utilities"

  # Download core hook files
  for hook in "${HOOK_FILES[@]}"; do
    local url="$MEMORY_SERVICE_REPO/claude-hooks/core/$hook"
    local dest="$HOOKS_DIR/$hook"

    if $DRY_RUN; then
      log_info "[DRY-RUN] Would download: $url -> $dest"
    else
      log_info "Downloading $hook..."
      if curl -fsSL "$url" -o "$dest" 2>/dev/null; then
        log_success "Downloaded $hook"
      else
        log_warn "Failed to download $hook (may not exist upstream)"
      fi
    fi
  done

  # Download utility files
  log_info "Downloading utility modules..."
  for util in "${UTILITY_FILES[@]}"; do
    local url="$MEMORY_SERVICE_REPO/claude-hooks/utilities/$util"
    local dest="$HOOKS_DIR/../utilities/$util"

    if $DRY_RUN; then
      log_info "[DRY-RUN] Would download: $url -> $dest"
    else
      if curl -fsSL "$url" -o "$dest" 2>/dev/null; then
        log_success "Downloaded $util"
      else
        log_warn "Failed to download $util"
      fi
    fi
  done
}

create_config() {
  log_info "Creating hooks config.json..."

  # Config goes in hooks/ directory (parent of memory/), as hooks expect ../config.json
  local config_file="$DOTFILES_ROOT/config/claude/hooks/config.json"
  local config_content='{
  "memoryService": {
    "protocol": "http",
    "preferredProtocol": "http",
    "fallbackEnabled": true,
    "http": {
      "endpoint": "http://memory-mcp:8000",
      "healthCheckTimeout": 3000,
      "useDetailedHealthCheck": false
    },
    "mcp": {
      "serverCommand": ["uv", "run", "memory", "server"],
      "serverWorkingDir": null,
      "connectionTimeout": 5000,
      "toolCallTimeout": 10000
    },
    "defaultTags": ["claude-code", "auto-generated"],
    "maxMemoriesPerSession": 8,
    "enableSessionConsolidation": true,
    "injectAfterCompacting": false
  },
  "autoCapture": {
    "enabled": true,
    "patterns": ["Decision", "Error", "Learning", "Implementation"],
    "userOverrides": {
      "skip": "#skip",
      "remember": "#remember"
    }
  },
  "sessionAnalysis": {
    "extractTopics": true,
    "extractDecisions": true,
    "extractInsights": true,
    "extractCodeChanges": true,
    "extractNextSteps": true,
    "minSessionLength": 100,
    "minConfidence": 0.1
  },
  "permissionRequest": {
    "enabled": true,
    "autoApprove": true,
    "logDecisions": false
  },
  "output": {
    "verbose": false,
    "showMemoryDetails": false,
    "cleanMode": true
  }
}'

  if $DRY_RUN; then
    log_info "[DRY-RUN] Would create config at: $config_file"
    echo "$config_content"
  else
    echo "$config_content" > "$config_file"
    log_success "Created config.json"
  fi
}

update_settings_json() {
  log_info "Updating settings.json with hook configuration..."

  if ! command -v jq &> /dev/null; then
    log_error "jq is required but not installed. Run ./install.sh --tools or install jq manually"
    return 1
  fi

  # Hooks to add to settings.json
  # Using absolute path with $HOME expanded at runtime via the hook script
  local hooks_path="\$HOME/.claude/hooks/memory"

  local new_hooks='{
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node '"$hooks_path"'/session-start.js",
            "timeout": 30
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node '"$hooks_path"'/session-end.js",
            "timeout": 15
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "mcp__memory__.*",
        "hooks": [
          {
            "type": "command",
            "command": "node '"$hooks_path"'/permission-request.js",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "node '"$hooks_path"'/auto-capture-hook.js",
            "timeout": 5
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node '"$hooks_path"'/mid-conversation.js",
            "timeout": 8
          }
        ]
      }
    ]
  }'

  if $DRY_RUN; then
    log_info "[DRY-RUN] Would add hooks to settings.json:"
    echo "$new_hooks" | jq .
    return 0
  fi

  # Backup current settings
  cp "$SETTINGS_FILE" "$SETTINGS_FILE.bak"
  log_info "Backed up settings.json to settings.json.bak"

  # Merge hooks into existing settings
  # This preserves existing hooks and adds new ones
  local merged
  merged=$(jq --argjson new_hooks "$new_hooks" '
    .hooks = (.hooks // {}) * $new_hooks
  ' "$SETTINGS_FILE")

  echo "$merged" > "$SETTINGS_FILE"
  log_success "Updated settings.json with memory hooks"
}

link_hooks_to_home() {
  log_info "Linking hooks to ~/.claude/hooks/..."

  local source_hooks_dir="$DOTFILES_ROOT/config/claude/hooks"
  local target_hooks_dir="$HOME/.claude/hooks"

  if $DRY_RUN; then
    log_info "[DRY-RUN] Would create symlink: $source_hooks_dir/memory -> $target_hooks_dir/memory"
    log_info "[DRY-RUN] Would create symlink: $source_hooks_dir/utilities -> $target_hooks_dir/utilities"
    return 0
  fi

  mkdir -p "$target_hooks_dir"

  # Link memory hooks
  if [[ -L "$target_hooks_dir/memory" ]]; then
    rm "$target_hooks_dir/memory"
  elif [[ -d "$target_hooks_dir/memory" ]]; then
    log_warn "Backing up existing memory hooks directory"
    mv "$target_hooks_dir/memory" "$target_hooks_dir/memory.bak.$(date +%Y%m%d%H%M%S)"
  fi
  ln -s "$source_hooks_dir/memory" "$target_hooks_dir/memory"
  log_success "Linked memory hooks directory"

  # Link utilities
  if [[ -L "$target_hooks_dir/utilities" ]]; then
    rm "$target_hooks_dir/utilities"
  elif [[ -d "$target_hooks_dir/utilities" ]]; then
    log_warn "Backing up existing utilities directory"
    mv "$target_hooks_dir/utilities" "$target_hooks_dir/utilities.bak.$(date +%Y%m%d%H%M%S)"
  fi
  ln -s "$source_hooks_dir/utilities" "$target_hooks_dir/utilities"
  log_success "Linked utilities directory"

  # Link config.json (hooks read this from ~/.claude/hooks/config.json)
  if [[ -L "$target_hooks_dir/config.json" ]]; then
    rm "$target_hooks_dir/config.json"
  elif [[ -f "$target_hooks_dir/config.json" ]]; then
    log_warn "Backing up existing config.json"
    mv "$target_hooks_dir/config.json" "$target_hooks_dir/config.json.bak.$(date +%Y%m%d%H%M%S)"
  fi
  ln -s "$source_hooks_dir/config.json" "$target_hooks_dir/config.json"
  log_success "Linked config.json"
}

verify_installation() {
  log_info "Verifying installation..."

  local errors=0
  local target_hooks_dir="$HOME/.claude/hooks"

  # Check hooks directory exists
  if [[ -d "$target_hooks_dir/memory" ]] || $DRY_RUN; then
    log_success "Memory hooks directory exists"
  else
    log_error "Memory hooks directory not found"
    ((errors++))
  fi

  # Check utilities directory exists
  if [[ -d "$target_hooks_dir/utilities" ]] || $DRY_RUN; then
    log_success "Utilities directory exists"
  else
    log_error "Utilities directory not found"
    ((errors++))
  fi

  # Check config.json symlink
  if [[ -f "$target_hooks_dir/config.json" ]] || $DRY_RUN; then
    log_success "config.json accessible at $target_hooks_dir/config.json"
  else
    log_error "config.json not found at $target_hooks_dir/config.json"
    ((errors++))
  fi

  # Check all required hook files
  for hook in "session-start.js" "session-end.js" "permission-request.js" "auto-capture-hook.js" "mid-conversation.js"; do
    if [[ -f "$target_hooks_dir/memory/$hook" ]] || $DRY_RUN; then
      log_success "Found $hook"
    else
      log_warn "Missing $hook"
    fi
  done

  # Check required utility files
  local required_utils=("memory-client.js" "project-detector.js" "context-formatter.js")
  for util in "${required_utils[@]}"; do
    if [[ -f "$target_hooks_dir/utilities/$util" ]] || $DRY_RUN; then
      log_success "Found utility: $util"
    else
      log_warn "Missing utility: $util"
    fi
  done

  # Check config.json (in hooks/ parent directory, not memory/)
  local config_path="$DOTFILES_ROOT/config/claude/hooks/config.json"
  if [[ -f "$config_path" ]] || $DRY_RUN; then
    log_success "Found config.json at $config_path"
  else
    log_error "config.json not found at $config_path"
    ((errors++))
  fi

  # Check settings.json has all memory hooks registered
  for event in "SessionStart" "SessionEnd" "PreToolUse" "PostToolUse" "UserPromptSubmit"; do
    if jq -e ".hooks.$event" "$SETTINGS_FILE" &>/dev/null || $DRY_RUN; then
      log_success "$event hook configured in settings.json"
    else
      log_error "$event hook not found in settings.json"
      ((errors++))
    fi
  done

  # Test hook execution (non-blocking)
  log_info "Testing session-start.js execution..."
  if $DRY_RUN; then
    log_info "[DRY-RUN] Would test hook execution"
  else
    if timeout 5 node "$target_hooks_dir/memory/session-start.js" < /dev/null 2>&1 | head -5; then
      log_success "Hook executed (check output above)"
    else
      log_warn "Hook execution returned non-zero or timed out (may be expected without stdin)"
    fi
  fi

  if [[ $errors -eq 0 ]]; then
    log_success "Installation verified successfully!"
    log_info ""
    log_info "To test the hooks, restart Claude Code or run:"
    log_info "  claude --debug hooks"
    log_info ""
    log_info "User override triggers:"
    log_info "  #skip    - Skip memory operations for this message"
    log_info "  #remember - Force memory operations"
  else
    log_error "Installation had $errors error(s)"
    return 1
  fi
}

main() {
  log_info "=== Memory Hooks Installer ==="
  log_info ""

  download_hooks
  create_config
  link_hooks_to_home
  update_settings_json
  verify_installation

  log_info ""
  log_success "Memory hooks installation complete!"
}

main "$@"
