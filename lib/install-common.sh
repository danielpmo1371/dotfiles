#!/bin/bash

# Common functions for dotfiles installation scripts
# Source this file from other installation scripts

# Colors for output (if terminal supports it)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_header() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
    echo ""
}

# Get the dotfiles root directory (parent of lib/)
get_dotfiles_root() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$(dirname "$script_dir")"
}

# Create a timestamped backup directory
# Usage: create_backup_dir "component-name"
# Returns: path to backup directory via echo
create_backup_dir() {
    local component="${1:-general}"
    local dotfiles_root="$(get_dotfiles_root)"
    local backup_dir="$dotfiles_root/backup/${component}-$(date +%Y%m%d-%H%M%S)"

    mkdir -p "$backup_dir"
    echo "$backup_dir"
}

# Backup a file or directory if it exists and is not a symlink
# Usage: backup_item "/path/to/item" "/path/to/backup/dir"
backup_item() {
    local item="$1"
    local backup_dir="$2"

    if [ -e "$item" ] && [ ! -L "$item" ]; then
        local item_name="$(basename "$item")"
        mv "$item" "$backup_dir/"
        log_info "Backed up: $item_name"
        return 0
    fi
    return 1
}

# Create a symlink, backing up existing file if necessary
# Usage: create_symlink "source" "target" "backup_dir"
# - source: the file in dotfiles repo
# - target: where the symlink should be created (e.g., ~/.bashrc)
# - backup_dir: where to backup existing files (optional, created if needed)
create_symlink() {
    local source="$1"
    local target="$2"
    local backup_dir="$3"
    local item_name="$(basename "$target")"

    # Check if source exists
    if [ ! -e "$source" ]; then
        log_warn "Source not found, skipping: $source"
        return 1
    fi

    # If target is already a symlink
    if [ -L "$target" ]; then
        local current_link="$(readlink "$target")"
        if [ "$current_link" = "$source" ]; then
            log_success "Already linked: $item_name"
            return 0
        else
            log_info "Updating symlink: $item_name (was -> $current_link)"
            rm "$target"
        fi
    elif [ -e "$target" ]; then
        # Target exists and is not a symlink - back it up
        if [ -z "$backup_dir" ]; then
            backup_dir="$(create_backup_dir "auto")"
        fi
        backup_item "$target" "$backup_dir"
    fi

    # Create the symlink
    ln -s "$source" "$target"
    log_success "Linked: $item_name -> $source"
    return 0
}

# Ensure a directory exists
ensure_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        log_info "Created directory: $dir"
    fi
}
