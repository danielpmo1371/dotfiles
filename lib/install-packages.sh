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

# Helper function for privilege elevation (imported from bootstrap.sh)
run_privileged() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    elif command -v sudo &> /dev/null; then
        sudo "$@"
    elif command -v doas &> /dev/null; then
        doas "$@"
    else
        log_error "No privilege elevation tool available (sudo/doas)"
        return 1
    fi
}

# Track if package manager has been updated this session
PKG_MANAGER_UPDATED=""

# Update package manager cache (once per session)
update_package_manager() {
    local manager="$1"

    # Skip if already updated this session
    if [[ "$PKG_MANAGER_UPDATED" == "$manager" ]]; then
        return 0
    fi

    case "$manager" in
        apt)
            log_info "Updating apt cache..."
            run_privileged apt update
            ;;
        dnf|yum)
            # dnf/yum auto-update metadata, but we can force it
            log_info "Updating $manager cache..."
            run_privileged "$manager" check-update || true
            ;;
        pacman)
            log_info "Updating pacman cache..."
            run_privileged pacman -Sy
            ;;
        brew)
            # Brew update can be slow, skip unless needed
            # Users can manually run 'brew update' if they want
            :
            ;;
        *)
            # For other managers, no update needed
            :
            ;;
    esac

    # Mark as updated for this session
    PKG_MANAGER_UPDATED="$manager"
}

# Check if running in non-interactive mode
is_non_interactive() {
    # Check if stdin is not a TTY
    if [[ ! -t 0 ]]; then
        return 0
    fi

    # Check for explicit flag
    if [[ "${DOTFILES_NON_INTERACTIVE:-false}" == "true" ]]; then
        return 0
    fi

    # Check for CI environment variables
    if [[ -n "$CI" ]] || [[ -n "$CONTINUOUS_INTEGRATION" ]] || [[ -n "$GITHUB_ACTIONS" ]]; then
        return 0
    fi

    return 1
}

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
    eval "$("$brew_bin" shellenv)" 2>/dev/null
    return 0
}

# Install Homebrew (called only when user explicitly selects it)
install_homebrew() {
    # Check if already installed
    if find_brew &> /dev/null; then
        log_info "Homebrew is already installed"
        ensure_brew_in_path
        return 0
    fi

    log_info "Installing Homebrew..."

    # Check for required permissions on Linux
    if [[ "$OSTYPE" == linux* ]]; then
        if [[ ! -w "/home/linuxbrew" ]] && [[ ! -w "$HOME" ]]; then
            log_error "Insufficient permissions to install Homebrew. Consider using native package manager instead."
            return 1
        fi
    fi

    # Homebrew's official install script with error handling
    if is_non_interactive; then
        # Non-interactive installation
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    local install_result=$?
    if [[ $install_result -ne 0 ]]; then
        log_error "Homebrew installation failed with exit code $install_result"
        return 1
    fi

    # Verify installation succeeded
    if ! find_brew &> /dev/null; then
        log_error "Homebrew installation completed but brew command not found"
        return 1
    fi

    # Set up PATH for current session
    ensure_brew_in_path

    log_success "Homebrew installed successfully"
    return 0
}

# Detect available package managers (prioritize native over brew on Linux)
detect_package_managers() {
    local managers=()

    # On macOS, prefer brew
    if [[ "$OSTYPE" == darwin* ]]; then
        managers+=("brew")
        # macOS might have other managers installed
        command -v port &> /dev/null && managers+=("macports")
    else
        # On Linux, prefer native package managers
        command -v apt &> /dev/null && managers+=("apt")
        command -v dnf &> /dev/null && managers+=("dnf")
        command -v yum &> /dev/null && managers+=("yum")
        command -v pacman &> /dev/null && managers+=("pacman")
        command -v zypper &> /dev/null && managers+=("zypper")
        command -v apk &> /dev/null && managers+=("apk")

        # Only offer brew if it's already installed or explicitly requested
        if find_brew &> /dev/null || [[ "${DOTFILES_PREFER_BREW:-false}" == "true" ]]; then
            managers+=("brew")
        fi
    fi

    # Windows
    command -v choco &> /dev/null && managers+=("choco")
    command -v scoop &> /dev/null && managers+=("scoop")

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

# Get the best available native package manager for non-interactive mode
get_native_package_manager() {
    # Prefer native package managers in order
    local native_managers=("apt" "dnf" "yum" "pacman" "zypper" "apk")

    for mgr in "${native_managers[@]}"; do
        if command -v "$mgr" &> /dev/null; then
            echo "$mgr"
            return 0
        fi
    done

    # Fall back to brew on macOS
    if [[ "$OSTYPE" == darwin* ]] && find_brew &> /dev/null; then
        echo "brew"
        return 0
    fi

    return 1
}

# Get preferred package manager (cached choice or prompt)
get_preferred_manager() {
    local cache_file="$HOME/.dotfiles_pkg_manager"
    local cached=""
    local homebrew_already_installed=false

    # Check if Homebrew is already installed (don't auto-install during validation)
    if find_brew &> /dev/null; then
        homebrew_already_installed=true
    fi

    # Check cached choice
    if [[ -f "$cache_file" ]]; then
        cached=$(cat "$cache_file")

        # Validate cached choice is still available
        if is_manager_installed "$cached"; then
            # If brew was chosen and is installed, just ensure PATH
            if [[ "$cached" == "brew" ]] && [[ "$homebrew_already_installed" == "true" ]]; then
                ensure_brew_in_path
            fi
            echo "$cached"
            return 0
        fi

        # Cached choice no longer valid, remove it
        rm -f "$cache_file"
    fi

    # In non-interactive mode, use the best available native package manager
    if is_non_interactive; then
        local native_mgr
        native_mgr=$(get_native_package_manager)
        if [[ -n "$native_mgr" ]]; then
            echo "$native_mgr" > "$cache_file"
            echo "$native_mgr"
            log_info "Using package manager: $native_mgr (non-interactive mode)"
            return 0
        else
            log_error "No native package manager available in non-interactive mode"
            return 1
        fi
    fi

    local managers=($(detect_package_managers))

    if [[ ${#managers[@]} -eq 0 ]]; then
        log_error "No package managers available"
        return 1
    fi

    # If only one option, use it automatically
    if [[ ${#managers[@]} -eq 1 ]]; then
        local selected="${managers[0]}"
        echo "$selected" > "$cache_file"
        log_info "Using package manager: $selected (only option available)"

        # Ensure brew is in PATH if it's already installed
        if [[ "$selected" == "brew" ]] && [[ "$homebrew_already_installed" == "true" ]]; then
            ensure_brew_in_path
        fi

        echo "$selected"
        return 0
    fi

    # Show available package managers
    echo "" >&2
    echo "Available package managers:" >&2
    local i=1
    for mgr in "${managers[@]}"; do
        if is_manager_installed "$mgr"; then
            echo "  $i) $mgr" >&2
        else
            if [[ "$mgr" == "brew" ]]; then
                echo "  $i) $mgr (can be installed)" >&2
            else
                echo "  $i) $mgr" >&2
            fi
        fi
        ((i++))
    done
    echo "" >&2

    # Use timeout for read to prevent indefinite blocking
    local choice
    if read -t 30 -p "Choose package manager [1-${#managers[@]}] (default: 1): " choice >&2; then
        # User provided input
        if [[ -z "$choice" ]]; then
            choice=1
        fi
    else
        # Timeout or no input available - use first option
        choice=1
        echo "" >&2
        log_info "No input received, using default: ${managers[0]}"
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#managers[@]} ]]; then
        local selected="${managers[$((choice-1))]}"

        # Only install brew if user explicitly selected it and it's not installed
        if [[ "$selected" == "brew" ]] && [[ "$homebrew_already_installed" == "false" ]]; then
            if ! install_homebrew; then
                log_error "Failed to install Homebrew"
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
# Usage: install_package <command_name> [brew] [apt/dnf/yum] [pacman] [npm] [cargo] [choco/scoop] [zypper] [apk]
# Example: install_package "ripgrep" "ripgrep" "ripgrep" "ripgrep" "" "ripgrep"
# Note: Most Linux package managers use the same name, so apt_pkg applies to dnf/yum by default
install_package() {
    local package="$1"           # Command name to check for
    local brew_pkg="${2:-$package}"      # Homebrew (macOS, Linux)
    local apt_pkg="${3:-$package}"       # apt (Debian, Ubuntu) - also used for dnf/yum
    local pacman_pkg="${4:-$apt_pkg}"    # pacman (Arch) - defaults to apt name
    local npm_pkg="${5:-}"               # npm (optional)
    local cargo_pkg="${6:-}"             # cargo (optional)
    local choco_pkg="${7:-$brew_pkg}"    # chocolatey/scoop (Windows) - defaults to brew name
    local zypper_pkg="${8:-$apt_pkg}"    # zypper (openSUSE) - defaults to apt name
    local apk_pkg="${9:-$apt_pkg}"       # apk (Alpine) - defaults to apt name

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

    # Debug: Show what we're about to install
    if [[ "$package" != "$apt_pkg" ]] || [[ "$package" != "$brew_pkg" ]]; then
        log_info "  Package name: $apt_pkg (apt), $brew_pkg (brew)"
    fi

    # Update package manager cache if needed (once per session)
    update_package_manager "$manager"

    case "$manager" in
        brew)
            ensure_brew_in_path
            brew install "$brew_pkg"
            ;;
        apt)
            run_privileged apt install -y "$apt_pkg"
            ;;
        dnf)
            run_privileged dnf install -y "$apt_pkg"
            ;;
        yum)
            run_privileged yum install -y "$apt_pkg"
            ;;
        pacman)
            run_privileged pacman -S --noconfirm "$pacman_pkg"
            ;;
        zypper)
            run_privileged zypper install -y "$zypper_pkg"
            ;;
        apk)
            run_privileged apk add "$apk_pkg"
            ;;
        choco)
            choco install -y "$choco_pkg"
            ;;
        scoop)
            scoop install "$choco_pkg"
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

    # Format: install_package "command" "brew" "apt" "pacman" "npm" "cargo" "choco" "zypper" "apk"
    # Most packages have the same name across managers, so we only specify differences
    install_package "tmux"
    install_package "chafa"
    install_package "fzf"
    install_package "rg" "ripgrep" "ripgrep" "ripgrep" "" "ripgrep"
    install_package "fd" "fd" "fd-find" "fd" "" "fd-find"
    install_package "bat"
    install_package "eza"  # modern ls
    install_package "zoxide"
    install_package "jq"
    install_package "lsd"
}

# Reset package manager choice
reset_package_manager_choice() {
    rm -f "$HOME/.dotfiles_pkg_manager"
    log_info "Package manager preference reset"
}