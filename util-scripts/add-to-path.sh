#!/bin/bash
# Usage: add-to-path.sh <path>
# Description: Add a path to PATH permanently via dotfiles/.bash_path file

DOTFILES_DIR="${DOTFILES_DIR:-/mnt/c/repos/dotfiles}"
BASH_PATH_FILE="$DOTFILES_DIR/.bash_path"

if [ -z "$1" ]; then
    echo "Error: Path argument is required"
    echo "Usage: $0 <path>"
    echo "Example: $0 /opt/my-tool/bin"
    exit 1
fi

NEW_PATH="$1"

# Validate that the path exists
if [ ! -d "$NEW_PATH" ]; then
    echo "Error: Path does not exist: $NEW_PATH"
    exit 1
fi

# Create .bash_path file if it doesn't exist
if [ ! -f "$BASH_PATH_FILE" ]; then
    echo "# Managed PATH additions - created by add-to-path.sh" > "$BASH_PATH_FILE"
    echo "# This file is sourced by .bashrc" >> "$BASH_PATH_FILE"
    echo "" >> "$BASH_PATH_FILE"
    echo "Created $BASH_PATH_FILE"
fi

# Check if path already exists in .bash_path
if grep -Fq "$NEW_PATH" "$BASH_PATH_FILE"; then
    echo "Path already exists in $BASH_PATH_FILE: $NEW_PATH"
    exit 0
fi

# Add the path to .bash_path
echo "export PATH=\"$NEW_PATH:\$PATH\"" >> "$BASH_PATH_FILE"
echo "Successfully added to $BASH_PATH_FILE: $NEW_PATH"
echo ""
echo "To apply changes, run: source ~/.bashrc"
echo "Or restart your terminal"
