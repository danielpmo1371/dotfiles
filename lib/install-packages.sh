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

# Install Homebrew if not present
install_homebrew() {
    if find_brew &> /dev/null; then
        ensure_brew_in_path
        log_info "Homebrew already installed"
        return 0
    fi

    log_info "Installing Homebrew..."

    # Homebrew's official install script
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Set up PATH for current session
    ensure_brew_in_path

    log_success "Homebrew installed"
}

# Detect available package managers
detect_package_managers() {
    local managers=()
    find_brew &> /dev/null && managers+=("brew")
    command -v apt &> /dev/null && managers+=("apt")
    command -v dnf &> /dev/null && managers+=("dnf")
    command -v pacman &> /dev/null && managers+=("pacman")
    command -v choco &> /dev/null && managers+=("choco")
    echo "${managers[@]}"
}

# Get preferred package manager (cached choice)
get_preferred_manager() {
    local cache_file="$HOME/.dotfiles_pkg_manager"

    if [[ -f "$cache_file" ]]; then
        cat "$cache_file"
        return
    fi

    local managers=($(detect_package_managers))

    if [[ ${#managers[@]} -eq 0 ]]; then
        echo ""
        return 1
    elif [[ ${#managers[@]} -eq 1 ]]; then
        echo "${managers[0]}"
        return
    fi

    # Multiple managers available - ask user
    echo "Multiple package managers detected:" >&2
    local i=1
    for mgr in "${managers[@]}"; do
        echo "  $i) $mgr" >&2
        ((i++))
    done

    read -p "Choose default package manager [1-${#managers[@]}]: " choice >&2

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#managers[@]} ]]; then
        local selected="${managers[$((choice-1))]}"
        echo "$selected" > "$cache_file"
        echo "$selected"
    else
        # Default to first available
        echo "${managers[0]}" > "$cache_file"
        echo "${managers[0]}"
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
