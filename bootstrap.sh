#!/bin/bash

# Bootstrap script for dotfiles installation
# Usage: curl -fsSL https://raw.githubusercontent.com/danielpmo1371/dotfiles/main/bootstrap.sh | bash

set -e

DOTFILES_REPO="https://github.com/danielpmo1371/dotfiles.git"
DOTFILES_DIR="$HOME/repos/dotfiles"

echo "=== Dotfiles Bootstrap ==="
echo ""

# Install git if not present
install_git() {
    echo "Git not found. Attempting to install..."

    if command -v apt &> /dev/null; then
        sudo apt update && sudo apt install -y git
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y git
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm git
    elif command -v brew &> /dev/null; then
        brew install git
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "Installing Xcode Command Line Tools (includes git)..."
        xcode-select --install
        echo "Please re-run this script after installation completes."
        exit 0
    else
        echo "Error: Could not install git automatically."
        echo "Please install git manually and re-run this script."
        exit 1
    fi
}

# Check for git, install if needed
if ! command -v git &> /dev/null; then
    install_git
fi

# Verify git is now available
if ! command -v git &> /dev/null; then
    echo "Error: git installation failed."
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
