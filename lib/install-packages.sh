#!/bin/bash

# Package installation library
# Provides cross-platform package installation with user choice

# Common Homebrew installation paths
BREW_PATHS=(
    "/opt/homebrew/bin/brew"        # macOS Apple Silicon
    "/usr/local/bin/brew"           # macOS Intel
    "/home/linuxbrew/.linuxbrew/bin/brew"  # Linux system-wide
    "$HOME/.linuxbrew/bin/brew"     # Linux user install
)

# Find brew binary even if not in PATH
find_brew() {
    # First check if it's in PATH
    if command -v brew &> /dev/null; then
        command -v brew
        return 0
    fi

    # Check common installation paths
    for brew_path in "${BREW_PATHS[@]}"; do
        if [[ -x "$brew_path" ]]; then
            echo "$brew_path"
            return 0
        fi
    done

    return 1
}

# Ensure brew is in PATH for current session
ensure_brew_in_path() {
    if command -v brew &> /dev/null; then
        return 0
    fi

    local brew_bin
    brew_bin=$(find_brew) || return 1

    # Add brew to PATH and set up environment
    eval "$("$brew_bin" shellenv)"
    return 0
}

# Install Homebrew (called only when user selects it)
install_homebrew() {
    if find_brew &> /dev/null; then
        ensure_brew_in_path
        return 0
    fi

    log_info "Installing Homebrew..."

    # Homebrew's official install script
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Set up PATH for current session
    ensure_brew_in_path

    log_success "Homebrew installed"
}

# Detect available package managers (including brew even if not installed)
detect_package_managers() {
    local managers=()

    # Always offer brew as an option (can be installed)
    managers+=("brew")

    # Detect system package managers
    command -v apt &> /dev/null && managers+=("apt")
    command -v dnf &> /dev/null && managers+=("dnf")
    command -v pacman &> /dev/null && managers+=("pacman")
    command -v choco &> /dev/null && managers+=("choco")

    echo "${managers[@]}"
}

# Check if a package manager is available (installed)
is_manager_installed() {
    local manager="$1"
    case "$manager" in
        brew) find_brew &> /dev/null ;;
        *) command -v "$manager" &> /dev/null ;;
    esac
}

# Get preferred package manager (cached choice)
get_preferred_manager() {
    local cache_file="$HOME/.dotfiles_pkg_manager"

    # Check cached choice
    if [[ -f "$cache_file" ]]; then
        local cached
        cached=$(cat "$cache_file")
        # Validate cached choice is still available/installable
        if [[ "$cached" == "brew" ]] || command -v "$cached" &> /dev/null; then
            # If brew was chosen, ensure it's installed
            if [[ "$cached" == "brew" ]]; then
                if ! find_brew &> /dev/null; then
                    install_homebrew
                fi
                ensure_brew_in_path
            fi
            echo "$cached"
            return 0
        fi
        # Cached choice no longer valid, remove it
        rm -f "$cache_file"
    fi

    local managers=($(detect_package_managers))

    if [[ ${#managers[@]} -eq 0 ]]; then
        log_error "No package managers available"
        return 1
    fi

    # Show available package managers
    echo "" >&2
    echo "Available package managers:" >&2
    local i=1
    for mgr in "${managers[@]}"; do
        if is_manager_installed "$mgr"; then
            echo "  $i) $mgr" >&2
        else
            echo "  $i) $mgr (will be installed)" >&2
        fi
        ((i++))
    done
    echo "" >&2

    read -p "Choose package manager [1-${#managers[@]}] (default: 1): " choice >&2

    # Default to first option if empty
    if [[ -z "$choice" ]]; then
        choice=1
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#managers[@]} ]]; then
        local selected="${managers[$((choice-1))]}"

        # Install if needed
        if ! is_manager_installed "$selected"; then
            if [[ "$selected" == "brew" ]]; then
                install_homebrew || return 1
            else
                log_error "Cannot install $selected automatically"
                return 1
            fi
        fi

        # Ensure brew is in PATH if selected
        if [[ "$selected" == "brew" ]]; then
            ensure_brew_in_path
        fi

        echo "$selected" > "$cache_file"
        echo "$selected"
    else
        log_error "Invalid choice"
        return 1
    fi
}

# Install a package using the preferred manager
# Usage: install_package <package_name> [brew_name] [apt_name] [npm_name] ...
# Example: install_package "ripgrep" "ripgrep" "ripgrep" "" "ripgrep"
install_package() {
    local package="$1"
    local brew_pkg="${2:-$package}"
    local apt_pkg="${3:-$package}"
    local npm_pkg="${4:-}"
    local cargo_pkg="${5:-}"

    # Check if already installed
    if command -v "$package" &> /dev/null; then
        log_info "$package already installed"
        return 0
    fi

    local manager=$(get_preferred_manager)

    if [[ -z "$manager" ]]; then
        log_error "No package manager available"
        return 1
    fi

    log_info "Installing $package via $manager..."

    case "$manager" in
        brew)
            ensure_brew_in_path
            brew install "$brew_pkg"
            ;;
        apt)
            sudo apt update && sudo apt install -y "$apt_pkg"
            ;;
        dnf)
            sudo dnf install -y "$apt_pkg"  # Usually same as apt
            ;;
        pacman)
            sudo pacman -S --noconfirm "$apt_pkg"
            ;;
        choco)
            choco install -y "$brew_pkg"  # Usually same as brew
            ;;
        npm)
            if [[ -n "$npm_pkg" ]]; then
                npm install -g "$npm_pkg"
            else
                log_error "$package not available via npm"
                return 1
            fi
            ;;
        cargo)
            if [[ -n "$cargo_pkg" ]]; then
                cargo install "$cargo_pkg"
            else
                log_error "$package not available via cargo"
                return 1
            fi
            ;;
        *)
            log_error "Unknown package manager: $manager"
            return 1
            ;;
    esac
}

# Install multiple packages
# Usage: install_packages "pkg1" "pkg2" "pkg3"
install_packages() {
    for pkg in "$@"; do
        install_package "$pkg"
    done
}

# Common tool installations with correct package names per manager
install_common_tools() {
    log_header "Installing Common Tools"

    # Format: install_package "command" "brew" "apt" "npm" "cargo"
    install_package "tmux" "tmux" "tmux"
    install_package "chafa" "chafa" "chafa"
    install_package "fzf" "fzf" "fzf"
    install_package "rg" "ripgrep" "ripgrep" "" "ripgrep"
    install_package "fd" "fd" "fd-find" "" "fd-find"
    install_package "bat" "bat" "bat" "" "bat"
    install_package "eza" "eza" "eza" "" "eza"  # modern ls
    install_package "zoxide" "zoxide" "zoxide" "" "zoxide"
    install_package "jq" "jq" "jq"
    install_package "lsd" "lsd" "lsd" "" "lsd"
}

# Reset package manager choice
reset_package_manager_choice() {
    rm -f "$HOME/.dotfiles_pkg_manager"
    log_info "Package manager preference reset"
}
