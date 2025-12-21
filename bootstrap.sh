#!/bin/bash

# Bootstrap script for dotfiles installation
# Usage: curl -fsSL https://raw.githubusercontent.com/danielpmo1371/dotfiles/main/bootstrap.sh | bash

set -e

DOTFILES_REPO="https://github.com/danielpmo1371/dotfiles.git"
DOTFILES_DIR="$HOME/repos/dotfiles"

echo "=== Dotfiles Bootstrap ==="
echo ""

# Check for git
if ! command -v git &> /dev/null; then
    echo "Error: git is required but not installed."
    echo "Install git first, then run this script again."
    exit 1
fi

# Clone or update dotfiles
if [ -d "$DOTFILES_DIR" ]; then
    echo "Dotfiles already exist at $DOTFILES_DIR"
    echo "Pulling latest changes..."
    cd "$DOTFILES_DIR" && git pull
else
    echo "Cloning dotfiles to $DOTFILES_DIR..."
    mkdir -p "$(dirname "$DOTFILES_DIR")"
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
fi

echo ""
echo "Running installer..."
echo ""

cd "$DOTFILES_DIR" && ./install.sh

echo ""
echo "Bootstrap complete!"
