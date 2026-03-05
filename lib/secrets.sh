#!/bin/bash
# secrets.sh - Dotfiles-specific migration logic
#
# This file provides migration from ~/.accessTokens to the OS-native secret
# store. The core secrets library is provided by nuvemlabs/secrets, installed
# at ~/.local/lib/secrets/secrets.sh.
#
# This file is sourced AFTER the core library, so all public API functions
# (secret, secret_set, secret_list, etc.) and backend helpers are available.
#
# Migration commands:
#   __secrets_auto_migrate  - Auto-migrate on shell startup (idempotent)
#   secrets_migrate         - Force re-migration (removes migration flag)

SECRETS_MIGRATED_FLAG="$HOME/.cache/dotfiles-secrets-migrated"

# ─────────────────────────────────────────────────────────────────────────────
#   File Backend Helpers (for migration only)
# ─────────────────────────────────────────────────────────────────────────────

__secrets_migration_file() {
    if [[ -f "$HOME/.accessTokens" ]]; then
        echo "$HOME/.accessTokens"
    elif [[ -n "$DOTFILES_DIR" && -f "$DOTFILES_DIR/.accessTokens" ]]; then
        echo "$DOTFILES_DIR/.accessTokens"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
#   Migration
# ─────────────────────────────────────────────────────────────────────────────

__secrets_auto_migrate() {
    local file="$HOME/.accessTokens"
    local backend
    backend=$(__secrets_backend)

    # Skip if no file to migrate
    [[ ! -f "$file" ]] && return 0

    # Skip if file backend (no point migrating to itself)
    [[ "$backend" == "file" ]] && return 0

    # Skip if already migrated this file (check marker)
    [[ -f "$SECRETS_MIGRATED_FLAG" ]] && return 0

    local migrated=0
    local skipped=0
    local key value existing

    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            ''|\#*) continue ;;
            *=*)
                key="${line%%=*}"
                value="${line#*=}"

                # Validate key name
                if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
                    continue
                fi

                # Check if already exists in secret store
                existing=$(secret "$key" 2>/dev/null) || existing=""

                if [[ -z "$existing" ]]; then
                    # Add to secret store
                    secret_set "$key" "$value" && ((migrated++))
                elif [[ "$existing" != "$value" ]]; then
                    echo "[secrets] Warning: $key exists with different value, skipping" >&2
                    ((skipped++))
                fi
                ;;
        esac
    done < "$file"

    # Rename the file after migration
    if [[ $migrated -gt 0 || $skipped -eq 0 ]]; then
        local backup="$HOME/.accessTokens.importedtosecretsstore-$(date +%Y%m%d).bkup"
        mv "$file" "$backup"
        echo "[secrets] Migrated $migrated secrets to $backend, backed up to $backup"
    fi

    # Mark as migrated
    mkdir -p "$(dirname "$SECRETS_MIGRATED_FLAG")"
    touch "$SECRETS_MIGRATED_FLAG"
}

secrets_migrate() {
    # Manual migration command - remove flag and re-run
    rm -f "$SECRETS_MIGRATED_FLAG"
    __secrets_auto_migrate
}
