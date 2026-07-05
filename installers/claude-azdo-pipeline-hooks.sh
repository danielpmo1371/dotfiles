#!/usr/bin/env bash
#
# Claude AZDO Pipeline Hooks Installer
# Installs the PreToolUse guard hooks that gate Azure DevOps pipeline runs:
#   - pipeline-guard.sh         (matches mcp__azure-devops__pipelines_run_pipeline)
#   - pipeline-trigger-guard.sh (matches Bash; blocks direct curl/az/gh triggers)
#
# Both hooks are referenced by:
#   - agents/pipeline-runner.md
#   - commands/pipe-deploy.md
#   - skills/pipeline-ops/SKILL.md
#
# This installer creates per-file symlinks inside ~/.claude/hooks/. The hooks/
# directory itself is not whole-symlinked because memory-hooks.sh and
# logging-hooks.sh also populate it with their own subdirectories.
#
# Settings registration (the PreToolUse entries) lives in config/claude/settings.json
# which is whole-symlinked by claude.sh, so this installer does NOT modify
# settings.json.
#
# Prerequisites: ~/.claude/scripts/pipeline-validator.sh and pipeline-registry.sh
# (delivered automatically by --claude via the whole-dir scripts symlink).
# Their absence produces a warning, not a failure, so this installer can run
# before --claude has been executed without aborting.
#
# Usage: ./claude-azdo-pipeline-hooks.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"

HOOKS_SOURCE_DIR="$DOTFILES_ROOT/config/claude/hooks"
HOOKS_TARGET_DIR="$HOME/.claude/hooks"
SCRIPTS_TARGET_DIR="$HOME/.claude/scripts"

PIPELINE_HOOK_FILES=(
    "pipeline-guard.sh"
    "pipeline-trigger-guard.sh"
)

PIPELINE_HOOK_PREREQS=(
    "pipeline-validator.sh"
    "pipeline-registry.sh"
)

DRY_RUN=false

parse_args() {
    if [[ "${1:-}" == "--dry-run" ]]; then
        DRY_RUN=true
        log_info "Running in dry-run mode"
    fi
}

link_pipeline_hooks() {
    log_info "Linking AZDO pipeline guard hooks to $HOOKS_TARGET_DIR"

    if $DRY_RUN; then
        for hook in "${PIPELINE_HOOK_FILES[@]}"; do
            log_info "[DRY-RUN] Would link $HOOKS_SOURCE_DIR/$hook -> $HOOKS_TARGET_DIR/$hook"
        done
        return 0
    fi

    ensure_dir "$HOOKS_TARGET_DIR"

    for hook in "${PIPELINE_HOOK_FILES[@]}"; do
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

check_prerequisites() {
    log_info "Checking prerequisite scripts in $SCRIPTS_TARGET_DIR"

    local missing=0
    for prereq in "${PIPELINE_HOOK_PREREQS[@]}"; do
        if [[ -e "$SCRIPTS_TARGET_DIR/$prereq" ]]; then
            log_success "Found prereq: $prereq"
        else
            log_warn "Missing prereq: $SCRIPTS_TARGET_DIR/$prereq"
            ((missing++)) || true
        fi
    done

    if (( missing > 0 )); then
        log_warn "$missing prerequisite script(s) missing — hooks will be linked but may fail at runtime."
        log_warn "Run './install.sh --claude' to install them via the scripts whole-dir symlink."
    fi
}

verify_installation() {
    log_info "Verifying installation"

    local errors=0

    for hook in "${PIPELINE_HOOK_FILES[@]}"; do
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

    log_success "AZDO pipeline hooks installation verified"
    return 0
}

main() {
    log_header "Claude AZDO Pipeline Hooks"
    parse_args "$@"

    link_pipeline_hooks
    check_prerequisites
    verify_installation

    if ! $DRY_RUN; then
        log_info "Restart Claude Code to (re)load hooks if it is running."
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
