#!/bin/bash

# Unified backup library for dotfiles installation
# Provides consistent backup/restore functionality across all installers
#
# Usage:
#   source lib/backup.sh
#   backup_init "component-name"
#   backup_file "/path/to/file"
#   backup_dir "/path/to/dir"
#   backup_finish
#
# Restore:
#   list_backups
#   restore_backup "~/.dotfiles-backup-20260130-120000"

# Backup configuration
BACKUP_BASE_DIR="$HOME"
BACKUP_PREFIX=".dotfiles-backup"
BACKUP_MANIFEST_FILE="manifest.json"

# Session state
_BACKUP_SESSION_DIR=""
_BACKUP_SESSION_COMPONENT=""
_BACKUP_SESSION_ITEMS=()

# Get list of all backup directories
list_backups() {
    local backups=()

    for dir in "$BACKUP_BASE_DIR"/${BACKUP_PREFIX}-*/; do
        [[ -d "$dir" ]] || continue
        backups+=("$dir")
    done

    if [[ ${#backups[@]} -eq 0 ]]; then
        echo "No backups found."
        return 1
    fi

    echo "Available backups:"
    echo ""

    for backup_dir in "${backups[@]}"; do
        local dir_name=$(basename "$backup_dir")
        local manifest="$backup_dir/$BACKUP_MANIFEST_FILE"

        if [[ -f "$manifest" ]]; then
            local component=$(jq -r '.component // "unknown"' "$manifest" 2>/dev/null)
            local timestamp=$(jq -r '.timestamp // "unknown"' "$manifest" 2>/dev/null)
            local item_count=$(jq -r '.items | length' "$manifest" 2>/dev/null)
            echo "  $dir_name"
            echo "    Component: $component"
            echo "    Date: $timestamp"
            echo "    Items: $item_count"
        else
            echo "  $dir_name (no manifest)"
        fi
        echo ""
    done
}

# Initialize a backup session
# Usage: backup_init "component-name"
backup_init() {
    local component="${1:-general}"
    local timestamp=$(date +%Y%m%d-%H%M%S)

    _BACKUP_SESSION_DIR="$BACKUP_BASE_DIR/${BACKUP_PREFIX}-${timestamp}"
    _BACKUP_SESSION_COMPONENT="$component"
    _BACKUP_SESSION_ITEMS=()

    mkdir -p "$_BACKUP_SESSION_DIR"

    echo "$_BACKUP_SESSION_DIR"
}

# Get current backup session directory (for external use)
backup_get_session_dir() {
    echo "$_BACKUP_SESSION_DIR"
}

# Check if backup session is active
backup_session_active() {
    [[ -n "$_BACKUP_SESSION_DIR" && -d "$_BACKUP_SESSION_DIR" ]]
}

# Backup a single file (move to backup directory)
# Usage: backup_file "/path/to/file" ["category"]
# Returns: 0 if backed up, 1 if skipped (doesn't exist or is symlink)
backup_file() {
    local file="$1"
    local category="${2:-files}"

    # Skip if doesn't exist
    if [[ ! -e "$file" ]]; then
        return 1
    fi

    # Skip if it's a symlink (nothing to preserve)
    if [[ -L "$file" ]]; then
        return 1
    fi

    # Ensure session is initialized
    if ! backup_session_active; then
        backup_init "auto"
    fi

    # Create category subdirectory
    local category_dir="$_BACKUP_SESSION_DIR/$category"
    mkdir -p "$category_dir"

    # Move file to backup
    local filename=$(basename "$file")
    local backup_path="$category_dir/$filename"

    # Handle duplicates by adding suffix
    local counter=1
    while [[ -e "$backup_path" ]]; do
        backup_path="$category_dir/${filename}.${counter}"
        ((counter++))
    done

    mv "$file" "$backup_path"

    # Track in session
    _BACKUP_SESSION_ITEMS+=("$(jq -n \
        --arg type "file" \
        --arg original "$file" \
        --arg backup "$backup_path" \
        --arg category "$category" \
        '{type: $type, original: $original, backup: $backup, category: $category}')")

    log_info "Backed up: $file"
    return 0
}

# Backup a directory (move to backup directory)
# Usage: backup_dir "/path/to/dir" ["category"]
backup_dir() {
    local dir="$1"
    local category="${2:-dirs}"

    # Skip if doesn't exist
    if [[ ! -e "$dir" ]]; then
        return 1
    fi

    # Skip if it's a symlink
    if [[ -L "$dir" ]]; then
        return 1
    fi

    # Ensure session is initialized
    if ! backup_session_active; then
        backup_init "auto"
    fi

    # Create category subdirectory
    local category_dir="$_BACKUP_SESSION_DIR/$category"
    mkdir -p "$category_dir"

    # Move directory to backup
    local dirname=$(basename "$dir")
    local backup_path="$category_dir/$dirname"

    # Handle duplicates
    local counter=1
    while [[ -e "$backup_path" ]]; do
        backup_path="$category_dir/${dirname}.${counter}"
        ((counter++))
    done

    mv "$dir" "$backup_path"

    # Track in session
    _BACKUP_SESSION_ITEMS+=("$(jq -n \
        --arg type "directory" \
        --arg original "$dir" \
        --arg backup "$backup_path" \
        --arg category "$category" \
        '{type: $type, original: $original, backup: $backup, category: $category}')")

    log_info "Backed up: $dir"
    return 0
}

# Backup a file or directory (auto-detects type)
# Usage: backup_item "/path/to/item" ["category"]
backup_item() {
    local item="$1"
    local category="$2"

    if [[ -d "$item" && ! -L "$item" ]]; then
        backup_dir "$item" "${category:-dirs}"
    else
        backup_file "$item" "${category:-files}"
    fi
}

# Copy a file to backup (for merge operations where original stays in place)
# Usage: backup_copy "/path/to/file" ["category"]
# Returns: 0 if backed up, 1 if skipped
backup_copy() {
    local file="$1"
    local category="${2:-copies}"

    # Skip if doesn't exist
    if [[ ! -f "$file" ]]; then
        return 1
    fi

    # Ensure session is initialized
    if ! backup_session_active; then
        backup_init "auto"
    fi

    # Create category subdirectory
    local category_dir="$_BACKUP_SESSION_DIR/$category"
    mkdir -p "$category_dir"

    # Copy file to backup
    local filename=$(basename "$file")
    local backup_path="$category_dir/$filename"

    # Handle duplicates by adding suffix
    local counter=1
    while [[ -e "$backup_path" ]]; do
        backup_path="$category_dir/${filename}.${counter}"
        ((counter++))
    done

    cp "$file" "$backup_path"

    # Track in session
    _BACKUP_SESSION_ITEMS+=("$(jq -n \
        --arg type "copy" \
        --arg original "$file" \
        --arg backup "$backup_path" \
        --arg category "$category" \
        '{type: $type, original: $original, backup: $backup, category: $category}')")

    log_info "Backed up (copy): $file"
    return 0
}

# Finalize backup session and write manifest
backup_finish() {
    if ! backup_session_active; then
        return 1
    fi

    # If no items were backed up, remove empty directory
    if [[ ${#_BACKUP_SESSION_ITEMS[@]} -eq 0 ]]; then
        rmdir "$_BACKUP_SESSION_DIR" 2>/dev/null || true
        _BACKUP_SESSION_DIR=""
        return 0
    fi

    # Build items array for manifest
    local items_json="["
    local first=true
    for item in "${_BACKUP_SESSION_ITEMS[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            items_json+=","
        fi
        items_json+="$item"
    done
    items_json+="]"

    # Write manifest
    local manifest="$_BACKUP_SESSION_DIR/$BACKUP_MANIFEST_FILE"
    jq -n \
        --arg component "$_BACKUP_SESSION_COMPONENT" \
        --arg timestamp "$(date -Iseconds)" \
        --arg hostname "$(hostname)" \
        --argjson items "$items_json" \
        '{
            component: $component,
            timestamp: $timestamp,
            hostname: $hostname,
            items: $items
        }' > "$manifest"

    local item_count=${#_BACKUP_SESSION_ITEMS[@]}
    log_success "Backup complete: $item_count item(s) saved to $_BACKUP_SESSION_DIR"

    # Clear session
    _BACKUP_SESSION_DIR=""
    _BACKUP_SESSION_COMPONENT=""
    _BACKUP_SESSION_ITEMS=()

    return 0
}

# Restore from a backup directory
# Usage: restore_backup "/path/to/backup" [--dry-run]
restore_backup() {
    local backup_dir="$1"
    local dry_run="${2:-}"

    # Handle relative paths
    if [[ ! "$backup_dir" = /* ]]; then
        backup_dir="$BACKUP_BASE_DIR/$backup_dir"
    fi

    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup directory not found: $backup_dir"
        return 1
    fi

    local manifest="$backup_dir/$BACKUP_MANIFEST_FILE"

    if [[ ! -f "$manifest" ]]; then
        log_error "No manifest found in backup: $backup_dir"
        return 1
    fi

    local item_count=$(jq -r '.items | length' "$manifest")
    local component=$(jq -r '.component' "$manifest")
    local timestamp=$(jq -r '.timestamp' "$manifest")

    echo "Restore backup:"
    echo "  Component: $component"
    echo "  Date: $timestamp"
    echo "  Items: $item_count"
    echo ""

    if [[ "$dry_run" == "--dry-run" ]]; then
        echo "Dry run - would restore:"
        jq -r '.items[] | "  \(.backup) -> \(.original)"' "$manifest"
        return 0
    fi

    # Restore each item
    local restored=0
    local failed=0

    while IFS= read -r item; do
        local backup_path=$(echo "$item" | jq -r '.backup')
        local original_path=$(echo "$item" | jq -r '.original')
        local item_type=$(echo "$item" | jq -r '.type')

        if [[ ! -e "$backup_path" ]]; then
            log_warn "Backup item missing: $backup_path"
            ((failed++))
            continue
        fi

        # Check if original location has something new
        if [[ -e "$original_path" ]]; then
            if [[ -L "$original_path" ]]; then
                # Remove symlink
                rm "$original_path"
            else
                log_warn "Target exists (not overwriting): $original_path"
                ((failed++))
                continue
            fi
        fi

        # Ensure parent directory exists
        mkdir -p "$(dirname "$original_path")"

        # Move back to original location
        mv "$backup_path" "$original_path"
        log_success "Restored: $original_path"
        ((restored++))

    done < <(jq -c '.items[]' "$manifest")

    echo ""
    log_info "Restored $restored item(s), $failed failed"

    # Clean up empty backup directory
    if [[ $restored -gt 0 && $failed -eq 0 ]]; then
        rm -f "$manifest"
        find "$backup_dir" -type d -empty -delete 2>/dev/null
        if [[ ! -d "$backup_dir" ]] || [[ -z "$(ls -A "$backup_dir" 2>/dev/null)" ]]; then
            rmdir "$backup_dir" 2>/dev/null || true
            log_info "Removed empty backup directory"
        fi
    fi

    return 0
}

# Interactive restore - list backups and let user choose
restore_interactive() {
    local backups=()

    for dir in "$BACKUP_BASE_DIR"/${BACKUP_PREFIX}-*/; do
        [[ -d "$dir" ]] || continue
        backups+=("$(basename "$dir")")
    done

    if [[ ${#backups[@]} -eq 0 ]]; then
        echo "No backups found."
        return 1
    fi

    echo "Available backups:"
    echo ""

    local i=1
    for backup in "${backups[@]}"; do
        local manifest="$BACKUP_BASE_DIR/$backup/$BACKUP_MANIFEST_FILE"
        if [[ -f "$manifest" ]]; then
            local component=$(jq -r '.component // "unknown"' "$manifest" 2>/dev/null)
            local timestamp=$(jq -r '.timestamp // "unknown"' "$manifest" 2>/dev/null)
            echo "  $i) $backup ($component - $timestamp)"
        else
            echo "  $i) $backup (no manifest)"
        fi
        ((i++))
    done

    echo ""
    read -p "Select backup to restore [1-${#backups[@]}] (or 'q' to quit): " choice

    if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
        return 0
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#backups[@]} ]]; then
        local selected="${backups[$((choice-1))]}"
        echo ""
        read -p "Restore '$selected'? This will overwrite current symlinks. [y/N]: " confirm

        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            restore_backup "$BACKUP_BASE_DIR/$selected"
        else
            echo "Cancelled."
        fi
    else
        log_error "Invalid selection"
        return 1
    fi
}

# Delete old backups (keep last N)
# Usage: backup_cleanup [keep_count]
backup_cleanup() {
    local keep_count="${1:-5}"
    local backups=()

    # Get backups sorted by date (oldest first)
    while IFS= read -r dir; do
        [[ -d "$dir" ]] && backups+=("$dir")
    done < <(ls -dt "$BACKUP_BASE_DIR"/${BACKUP_PREFIX}-*/ 2>/dev/null | tail -r)

    local total=${#backups[@]}

    if [[ $total -le $keep_count ]]; then
        echo "Only $total backup(s) found, keeping all."
        return 0
    fi

    local to_delete=$((total - keep_count))
    echo "Found $total backups, removing $to_delete oldest..."

    for ((i=0; i<to_delete; i++)); do
        local backup="${backups[$i]}"
        echo "  Removing: $(basename "$backup")"
        rm -rf "$backup"
    done

    log_success "Cleanup complete. Kept $keep_count most recent backups."
}
