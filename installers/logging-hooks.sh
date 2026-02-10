#!/usr/bin/env bash
#
# Logging Hooks Installer
# Sets up custom Claude Code session logging hooks
#
# Usage: ./logging-hooks.sh [--dry-run]
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

# Source common functions
source "$DOTFILES_ROOT/lib/install-common.sh"

# Configuration
HOOKS_SOURCE_DIR="$DOTFILES_ROOT/config/claude/hooks/logging"
HOOKS_TARGET_DIR="$HOME/.claude/hooks/logging"
LOG_OUTPUT_DIR="$DOTFILES_ROOT/tmp/claude"
SETTINGS_FILE="$DOTFILES_ROOT/config/claude/settings.json"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  log_info "Running in dry-run mode"
fi

create_directories() {
  log_info "Creating directories..."

  local dirs=(
    "$HOOKS_SOURCE_DIR"
    "$LOG_OUTPUT_DIR"
    "$LOG_OUTPUT_DIR/active-sessions"
  )

  for dir in "${dirs[@]}"; do
    if $DRY_RUN; then
      log_info "[DRY-RUN] Would create: $dir"
    else
      mkdir -p "$dir"
    fi
  done

  log_success "Directories created"
}

link_hooks() {
  log_info "Linking logging hooks to ~/.claude/hooks/..."

  if $DRY_RUN; then
    log_info "[DRY-RUN] Would create symlink: $HOOKS_SOURCE_DIR -> $HOOKS_TARGET_DIR"
    return 0
  fi

  mkdir -p "$(dirname "$HOOKS_TARGET_DIR")"

  if [[ -L "$HOOKS_TARGET_DIR" ]]; then
    rm "$HOOKS_TARGET_DIR"
  elif [[ -d "$HOOKS_TARGET_DIR" ]]; then
    log_warn "Backing up existing logging hooks directory"
    mv "$HOOKS_TARGET_DIR" "$HOOKS_TARGET_DIR.bak.$(date +%Y%m%d%H%M%S)"
  fi

  ln -s "$HOOKS_SOURCE_DIR" "$HOOKS_TARGET_DIR"
  log_success "Linked logging hooks directory"
}

update_settings() {
  log_info "Updating settings.json with logging hooks..."

  if ! command -v jq &> /dev/null; then
    log_error "jq is required but not installed. Run ./install.sh --tools or install jq manually"
    return 1
  fi

  if $DRY_RUN; then
    log_info "[DRY-RUN] Would update settings.json with logging hooks"
    return 0
  fi

  # Backup settings
  cp "$SETTINGS_FILE" "$SETTINGS_FILE.bak"

  # Use portable $HOME path instead of expanded home directory
  local hooks_path="\$HOME/.claude/hooks/logging"

  # Add logging hooks if not already present
  local updated
  updated=$(jq '
    # Add UserPromptSubmit hooks if not present
    if .hooks.UserPromptSubmit == null then
      .hooks.UserPromptSubmit = [
        {
          "hooks": [
            {
              "type": "command",
              "command": "'"$hooks_path"'/user-request-logger.sh",
              "timeout": 5
            },
            {
              "type": "command",
              "command": "'"$hooks_path"'/session-goal-tracker.sh",
              "timeout": 5
            }
          ]
        }
      ]
    else . end |

    # Add Stop hooks if not present
    if .hooks.Stop == null then
      .hooks.Stop = [
        {
          "hooks": [
            {
              "type": "command",
              "command": "'"$hooks_path"'/response-summarizer.sh",
              "timeout": 10
            }
          ]
        }
      ]
    else . end |

    # Add session-goal-tracker to SessionStart if SessionStart exists
    if .hooks.SessionStart != null then
      .hooks.SessionStart[0].hooks += [
        {
          "type": "command",
          "command": "'"$hooks_path"'/session-goal-tracker.sh",
          "timeout": 5
        }
      ] | .hooks.SessionStart[0].hooks |= unique_by(.command)
    else
      .hooks.SessionStart = [
        {
          "hooks": [
            {
              "type": "command",
              "command": "'"$hooks_path"'/session-goal-tracker.sh",
              "timeout": 5
            }
          ]
        }
      ]
    end |

    # Add session-goal-tracker to SessionEnd if SessionEnd exists
    if .hooks.SessionEnd != null then
      .hooks.SessionEnd[0].hooks += [
        {
          "type": "command",
          "command": "'"$hooks_path"'/session-goal-tracker.sh",
          "timeout": 5
        }
      ] | .hooks.SessionEnd[0].hooks |= unique_by(.command)
    else
      .hooks.SessionEnd = [
        {
          "hooks": [
            {
              "type": "command",
              "command": "'"$hooks_path"'/session-goal-tracker.sh",
              "timeout": 5
            }
          ]
        }
      ]
    end
  ' "$SETTINGS_FILE")

  echo "$updated" > "$SETTINGS_FILE"
  log_success "Updated settings.json with logging hooks"
}

verify_installation() {
  log_info "Verifying installation..."

  local errors=0

  # Check hooks directory
  if [[ -d "$HOOKS_TARGET_DIR" ]] || $DRY_RUN; then
    log_success "Logging hooks directory exists"
  else
    log_error "Logging hooks directory not found"
    ((errors++))
  fi

  # Check hook files
  local hooks=("user-request-logger.sh" "response-summarizer.sh" "session-goal-tracker.sh")
  for hook in "${hooks[@]}"; do
    if [[ -f "$HOOKS_TARGET_DIR/$hook" ]] || $DRY_RUN; then
      log_success "Found $hook"
    else
      log_error "Missing $hook"
      ((errors++))
    fi
  done

  # Check log output directory
  if [[ -d "$LOG_OUTPUT_DIR" ]] || $DRY_RUN; then
    log_success "Log output directory exists: $LOG_OUTPUT_DIR"
  else
    log_error "Log output directory not found"
    ((errors++))
  fi

  # Check settings.json
  if jq -e '.hooks.UserPromptSubmit' "$SETTINGS_FILE" &>/dev/null || $DRY_RUN; then
    log_success "UserPromptSubmit hook configured"
  else
    log_warn "UserPromptSubmit hook not found in settings.json"
  fi

  if jq -e '.hooks.Stop' "$SETTINGS_FILE" &>/dev/null || $DRY_RUN; then
    log_success "Stop hook configured"
  else
    log_warn "Stop hook not found in settings.json"
  fi

  if [[ $errors -eq 0 ]]; then
    log_success "Installation verified successfully!"
    log_info ""
    log_info "Log files will be created in: $LOG_OUTPUT_DIR"
    log_info "  - user-requests.log    : All user prompts with metadata"
    log_info "  - response-summaries.log : Summaries of Claude responses"
    log_info "  - session-goals.log    : Session goal tracking"
    log_info ""
    log_info "Restart Claude Code to activate the hooks."
  else
    log_error "Installation had $errors error(s)"
    return 1
  fi
}

main() {
  log_info "=== Logging Hooks Installer ==="
  log_info ""

  create_directories
  link_hooks
  update_settings
  verify_installation

  log_info ""
  log_success "Logging hooks installation complete!"
}

main "$@"
