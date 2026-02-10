#!/bin/bash

# Homebrew installer with cross-platform support
# Supports: macOS, Ubuntu/Debian, Fedora, Arch Linux
# Note: No 'set -e' here - this file is sourced by install.sh via run_installer.
# A global set -e would propagate to the parent shell and break error handling.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"

# Detect operating system
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [ -f /etc/fedora-release ]; then
        echo "fedora"
    elif [ -f /etc/arch-release ]; then
        echo "arch"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

# Install OS-specific dependencies for Homebrew
install_brew_deps() {
    local os="$1"
    log_info "Installing Homebrew dependencies for $os..."

    case "$os" in
        debian)
            sudo apt-get update
            sudo apt-get install -y build-essential procps curl file git
            ;;
        fedora)
            sudo dnf group install -y 'Development Tools'
            sudo dnf install -y procps-ng curl file
            ;;
        arch)
            sudo pacman -Sy --needed --noconfirm base-devel procps-ng curl file git
            ;;
        macos)
            # Xcode CLI tools - installer handles this automatically
            log_info "Xcode CLI tools will be installed if needed..."
            ;;
        *)
            log_error "Unsupported OS: $os"
            return 1
            ;;
    esac
}

# Set up brew environment for current session
setup_brew_env() {
    if [[ -d /home/linuxbrew/.linuxbrew ]]; then
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    elif [[ -d /opt/homebrew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -d /usr/local/Homebrew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
}

# Main installation function
install_brew() {
    log_header "Homebrew Installation"

    # Check if already installed
    if command -v brew &>/dev/null; then
        log_success "Homebrew already installed: $(brew --version | head -1)"
        return 0
    fi

    local os
    os=$(detect_os)

    if [[ "$os" == "unknown" ]]; then
        log_error "Unsupported operating system for Homebrew installation"
        log_info "Supported: macOS, Ubuntu/Debian, Fedora, Arch Linux"
        return 1
    fi

    log_info "Detected OS: $os"

    # Install dependencies
    install_brew_deps "$os"

    # Install Homebrew
    log_info "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Set up environment
    setup_brew_env

    # Verify installation
    if command -v brew &>/dev/null; then
        log_success "Homebrew installed successfully: $(brew --version | head -1)"

        # Show path info
        local brew_prefix
        brew_prefix=$(brew --prefix)
        log_info "Homebrew prefix: $brew_prefix"

        echo ""
        log_info "Add to your shell profile if not already present:"
        echo "  eval \"\$(${brew_prefix}/bin/brew shellenv)\""
    else
        log_error "Homebrew installation failed"
        return 1
    fi
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_brew
fi
