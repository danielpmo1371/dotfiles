#!/usr/bin/env bash
#
# Claude Hooks Installer
# General-purpose installer for the loose (non-subdirectory) config/claude/hooks/*.sh
# files that settings.json references and that are NOT pipeline-specific:
#   - destructive-ops-guard.sh (PreToolUse/Bash; enforces the No-Delete Rule)
#   - notification.sh          (Notification; desktop notification side effect)
#   - tmux-pane-registry.sh    (SessionStart/SessionEnd; records pane -> session
#                               for util-scripts/tmux-claude-relaunch.sh)
#
# The Azure DevOps pipeline guard hooks are owned by claude-azdo-pipeline-hooks.sh.
#
# This installer creates per-file symlinks inside ~/.claude/hooks/. The hooks/
# directory itself is not whole-symlinked because memory-hooks.sh and
# logging-hooks.sh also populate it with their own subdirectories.
#
# Settings registration (the hook entries) lives in config/claude/settings.json
# which is whole-symlinked by claude.sh, so this installer does NOT modify
# settings.json.
#
# Usage: ./claude-hooks.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"

HOOKS_SOURCE_DIR="$DOTFILES_ROOT/config/claude/hooks"
HOOKS_TARGET_DIR="$HOME/.claude/hooks"

CLAUDE_HOOK_FILES=(
    "destructive-ops-guard.sh"
    "notification.sh"
    "tmux-pane-registry.sh"
)

DRY_RUN=false

parse_args() {
    if [[ "${1:-}" == "--dry-run" ]]; then
        DRY_RUN=true
        log_info "Running in dry-run mode"
    fi
}

link_claude_hooks() {
    log_info "Linking Claude general hooks to $HOOKS_TARGET_DIR"

    if $DRY_RUN; then
        for hook in "${CLAUDE_HOOK_FILES[@]}"; do
            log_info "[DRY-RUN] Would link $HOOKS_SOURCE_DIR/$hook -> $HOOKS_TARGET_DIR/$hook"
        done
        return 0
    fi

    ensure_dir "$HOOKS_TARGET_DIR"

    for hook in "${CLAUDE_HOOK_FILES[@]}"; do
        local source="$HOOKS_SOURCE_DIR/$hook"
        local target="$HOOKS_TARGET_DIR/$hook"

        if [[ ! -f "$source" ]]; then
            log_error "Source hook missing in dotfiles: $source"
            return 1
        fi

        if [[ ! -x "$source" ]]; then
            log_warn "Hook is not executable, fixing: $source"
            chmod +x "$source"
        fi

        create_symlink_with_backup "$source" "$target" "claude-hooks"
    done
}

verify_installation() {
    log_info "Verifying installation"

    local errors=0

    for hook in "${CLAUDE_HOOK_FILES[@]}"; do
        local target="$HOOKS_TARGET_DIR/$hook"
        if $DRY_RUN; then
            log_success "[DRY-RUN] Would verify $target"
            continue
        fi
        if [[ -L "$target" ]]; then
            log_success "Symlink present: $hook"
        else
            log_error "Symlink missing: $target"
            ((errors++)) || true
        fi
    done

    if (( errors > 0 )); then
        log_error "Verification failed with $errors error(s)"
        return 1
    fi

    log_success "Claude general hooks installation verified"
    return 0
}

main() {
    log_header "Claude General Hooks"
    parse_args "$@"

    link_claude_hooks
    verify_installation

    if ! $DRY_RUN; then
        log_info "Restart Claude Code to (re)load hooks if it is running."
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
