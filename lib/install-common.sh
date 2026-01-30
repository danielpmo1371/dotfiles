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

# Source the unified backup library
_INSTALL_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_INSTALL_COMMON_DIR/backup.sh"

# Create a timestamped backup directory (wrapper for backward compatibility)
# Usage: create_backup_dir "component-name"
# Returns: path to backup directory via echo
create_backup_dir() {
    local component="${1:-general}"
    backup_init "$component"
}

# Create a symlink, backing up existing file if necessary
# Usage: create_symlink "source" "target" ["category"]
# - source: the file in dotfiles repo
# - target: where the symlink should be created (e.g., ~/.bashrc)
# - category: optional category for backup organization (default: from target path)
create_symlink() {
    local source="$1"
    local target="$2"
    local category="${3:-}"
    local item_name="$(basename "$target")"

    # Auto-detect category from target path if not provided
    if [[ -z "$category" ]]; then
        if [[ "$target" == "$HOME/.config/"* ]]; then
            category="config"
        elif [[ "$target" == "$HOME/."* ]]; then
            category="dotfiles"
        else
            category="other"
        fi
    fi

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
        # Target exists and is not a symlink - back it up using unified backup
        backup_item "$target" "$category"
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

# Link directories from config/ to ~/.config/
# Usage: link_config_dirs "nvim" "ghostty" "kitty"
link_config_dirs() {
    local dotfiles_root="${DOTFILES_ROOT:-$(get_dotfiles_root)}"
    ensure_dir "$HOME/.config"

    for dir in "$@"; do
        local source="$dotfiles_root/config/$dir"
        local target="$HOME/.config/$dir"
        create_symlink "$source" "$target"
    done
}

# Link files from config/<subdir>/ to $HOME
# Usage: link_home_files "bash" "bashrc:.bashrc" "bash_aliases:.bash_aliases"
# Format: "source_name:target_name" where target is in $HOME
link_home_files() {
    local config_subdir="$1"
    shift
    local dotfiles_root="${DOTFILES_ROOT:-$(get_dotfiles_root)}"

    for pair in "$@"; do
        local source_name="${pair%%:*}"
        local target_name="${pair##*:}"
        local source="$dotfiles_root/config/$config_subdir/$source_name"
        local target="$HOME/$target_name"
        create_symlink "$source" "$target"
    done
}

# Link a single file from dotfiles root to $HOME
# Usage: link_dotfile ".tmux.conf"
link_dotfile() {
    local filename="$1"
    local dotfiles_root="${DOTFILES_ROOT:-$(get_dotfiles_root)}"
    create_symlink "$dotfiles_root/$filename" "$HOME/$filename"
}

# Link files from config/<subdir>/ to a target directory
# Usage: link_target_files "claude" "$HOME/.claude" "CLAUDE.md" "settings.json" "commands"
# Each file/dir in config/<subdir>/ is symlinked to target_dir/<name>
link_target_files() {
    local config_subdir="$1"
    local target_dir="$2"
    shift 2
    local dotfiles_root="${DOTFILES_ROOT:-$(get_dotfiles_root)}"

    ensure_dir "$target_dir"

    for item in "$@"; do
        local source="$dotfiles_root/config/$config_subdir/$item"
        local target="$target_dir/$item"
        create_symlink "$source" "$target"
    done
}
