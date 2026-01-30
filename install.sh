#!/bin/bash

# Dotfiles Installation Script
# Main entry point with both CLI and interactive dialog modes
#
# Usage:
#   ./install.sh              # Interactive dialog mode (default)
#   ./install.sh --tools      # CLI mode - install specific component
#   ./install.sh --all        # CLI mode - install everything
#   ./install.sh --dialog     # Force dialog mode
#
# Installation Order & Dependencies:
#   1. brew.sh       - Homebrew package manager - no dependencies
#   2. tools.sh      - Base dev tools (git, nvim, etc.) - no dependencies
#   3. secrets.sh    - Create ~/.accessTokens template - no dependencies
#   4. terminals.sh  - Terminal emulators (Ghostty, etc.) - no dependencies
#   5. tmux.sh       - Tmux + TPM + plugins - requires: git
#   6. bash.sh       - Bash configuration - no dependencies
#   7. zsh.sh        - Zsh configuration + Zap - requires: git, zsh, curl
#   8. config-dirs.sh - Symlink config directories (nvim) - no dependencies
#   9. claude.sh     - Claude Code CLI + settings - requires: node, npm
#  10. mcp.sh        - MCP configuration - requires: jq

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
source "$SCRIPT_DIR/lib/install-common.sh"
source "$SCRIPT_DIR/lib/install-packages.sh"

# =============================================================================
# Package Profile Definitions
# =============================================================================

# Profile package lists
PROFILE_MINIMAL="git curl wget"
PROFILE_DEVELOPER="git curl wget nvim tmux zsh node npm ripgrep fzf fd bat jq"
PROFILE_FULL="git curl wget nvim tmux zsh node npm ripgrep fzf fd bat jq git-delta lsd zoxide eza chafa htop btop tree gdu terminal-notifier neofetch tlrc"

# All available packages with descriptions
# Format: "package:description"
ALL_PACKAGES=(
    "git:Version control"
    "curl:URL transfer tool"
    "wget:File downloader"
    "nvim:Neovim editor"
    "tmux:Terminal multiplexer"
    "zsh:Z shell"
    "node:Node.js runtime"
    "npm:Node package manager"
    "ripgrep:Fast grep (rg)"
    "fzf:Fuzzy finder"
    "fd:Fast find"
    "bat:Cat with syntax highlighting"
    "jq:JSON processor"
    "git-delta:Better git diffs"
    "lsd:Modern ls"
    "zoxide:Smart cd"
    "eza:Modern ls alternative"
    "chafa:Terminal image viewer"
    "htop:Process viewer"
    "btop:Resource monitor"
    "tree:Directory tree"
    "gdu:Disk usage analyzer"
    "terminal-notifier:macOS notifications"
    "neofetch:System info"
    "tlrc:Tldr client (Rust)"
)

# Get component dependencies (returns space-separated package list)
get_component_deps() {
    case "$1" in
        zsh)       echo "git zsh curl" ;;
        bash)      echo "" ;;
        tmux)      echo "git tmux" ;;
        terminals) echo "" ;;
        claude)    echo "node npm" ;;
        mcp)       echo "jq" ;;
        *)         echo "" ;;
    esac
}

# Get command name for a package (for checking if installed)
get_package_command() {
    case "$1" in
        ripgrep)   echo "rg" ;;
        git-delta) echo "delta" ;;
        tlrc)      echo "tldr" ;;
        *)         echo "$1" ;;
    esac
}

# =============================================================================
# Dialog Mode State
# =============================================================================

SELECTED_COMPONENTS=()
SELECTED_PACKAGES=()

# =============================================================================
# Mode Detection
# =============================================================================

should_use_dialog() {
    # Explicit --dialog flag forces dialog mode
    for arg in "$@"; do
        [[ "$arg" == "--dialog" ]] && return 0
    done

    # Any other flags = CLI mode
    [[ $# -gt 0 ]] && return 1

    # No args = dialog mode (if available and interactive terminal)
    [[ -t 0 ]] && command -v dialog &>/dev/null && return 0

    return 1
}

# =============================================================================
# Dialog Mode Functions
# =============================================================================

run_dialog_mode() {
    source "$SCRIPT_DIR/lib/dialog-ui.sh"

    if ! dialog_available; then
        log_error "dialog not installed. Install it or use CLI flags."
        log_info "Install with: brew install dialog (or apt install dialog)"
        exit 1
    fi

    while true; do
        local choice
        choice=$(dialog_welcome) || choice=""

        case "$choice" in
            install)
                run_install_flow
                ;;
            configure)
                dialog_msgbox "Configure" "Settings configuration not yet implemented.\n\nUse CLI flags or edit ~/.dotfiles_pkg_manager directly."
                ;;
            help)
                show_help_dialog
                ;;
            exit|"")
                clear
                exit 0
                ;;
        esac
    done
}

show_help_dialog() {
    local help_text="INTERACTIVE MODE
  Run ./install.sh without arguments to launch this dialog.

CLI MODE
  ./install.sh --all        Install everything
  ./install.sh --brew       Install Homebrew
  ./install.sh --tools      Install CLI tools
  ./install.sh --zsh        Configure Zsh
  ./install.sh --bash       Configure Bash
  ./install.sh --tmux       Install Tmux + plugins
  ./install.sh --terminals  Configure terminal emulators
  ./install.sh --claude     Install Claude Code CLI
  ./install.sh --mcp        Configure MCP servers

OPTIONS
  --dialog    Force dialog mode
  --help      Show help

PROFILES
  Minimal:   git, curl, wget
  Developer: + nvim, tmux, zsh, node, npm, ripgrep, fzf, fd, bat, jq
  Full:      + git-delta, lsd, zoxide, eza, chafa, htop, btop, etc."

    dialog_textbox "Help" "$help_text"
}

run_install_flow() {
    # Reset selections
    SELECTED_COMPONENTS=()
    SELECTED_PACKAGES=()

    # Step 1: Select components
    select_components
    [[ ${#SELECTED_COMPONENTS[@]} -eq 0 ]] && return

    # Step 2: If tools selected, run package selection
    if [[ " ${SELECTED_COMPONENTS[*]} " =~ " tools " ]]; then
        select_packages
    fi

    # Step 3: Resolve dependencies
    resolve_dependencies

    # Step 4: Show confirmation
    if ! show_confirmation; then
        return
    fi

    # Step 5: Run installation
    run_dialog_installation
}

select_components() {
    local result
    result=$(dialog_checklist "Select Components" \
        "brew:Homebrew package manager:on" \
        "tools:CLI tools and utilities:on" \
        "zsh:Zsh shell + plugins:off" \
        "bash:Bash configuration:off" \
        "tmux:Tmux + TPM plugins:off" \
        "terminals:Terminal emulators (Ghostty):off" \
        "claude:Claude Code CLI + config:off" \
        "mcp:MCP server configuration:off") || result=""

    # Parse space-separated result into array
    read -ra SELECTED_COMPONENTS <<< "$result"
}

select_packages() {
    # First: choose profile
    local profile
    profile=$(dialog_menu "Package Profile" \
        "minimal:Essential tools only (git, curl, wget)" \
        "developer:Productive dev setup (Recommended)" \
        "full:Everything included" \
        "custom:Choose individual packages") || profile=""

    [[ -z "$profile" ]] && return

    local preset=""
    case "$profile" in
        minimal)   preset="$PROFILE_MINIMAL" ;;
        developer) preset="$PROFILE_DEVELOPER" ;;
        full)      preset="$PROFILE_FULL" ;;
        custom)    preset="" ;;
    esac

    # Build checklist items with profile pre-selection
    local items=()
    for pkg_entry in "${ALL_PACKAGES[@]}"; do
        IFS=':' read -r pkg desc <<< "$pkg_entry"
        if [[ " $preset " =~ " $pkg " ]]; then
            items+=("$pkg:$desc:on")
        else
            items+=("$pkg:$desc:off")
        fi
    done

    local result
    result=$(dialog_checklist "Select Packages ($profile)" "${items[@]}") || result=""

    # Parse space-separated result into array
    read -ra SELECTED_PACKAGES <<< "$result"
}

resolve_dependencies() {
    local missing_deps=()

    for component in "${SELECTED_COMPONENTS[@]}"; do
        local deps
        deps=$(get_component_deps "$component")
        [[ -z "$deps" ]] && continue

        for dep in $deps; do
            local cmd
            cmd=$(get_package_command "$dep")

            # Skip if already installed on system
            command -v "$cmd" &>/dev/null && continue

            # Skip if already in selected packages
            [[ " ${SELECTED_PACKAGES[*]} " =~ " $dep " ]] && continue

            # Prompt user
            if dialog_yesno "'$component' requires '$dep' which is not selected.\n\nAdd '$dep' to installation?"; then
                SELECTED_PACKAGES+=("$dep")
            else
                missing_deps+=("$dep (for $component)")
            fi
        done
    done

    # Warn about unresolved dependencies
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        local warning="The following dependencies were not added:\n\n"
        for dep in "${missing_deps[@]}"; do
            warning+="  - $dep\n"
        done
        warning+="\nSome components may not work correctly."
        dialog_msgbox "Warning" "$warning"
    fi
}

show_confirmation() {
    local summary="The following will be installed:\n\n"

    if [[ ${#SELECTED_COMPONENTS[@]} -gt 0 ]]; then
        summary+="COMPONENTS:\n"
        for comp in "${SELECTED_COMPONENTS[@]}"; do
            summary+="  - $comp\n"
        done
    fi

    if [[ ${#SELECTED_PACKAGES[@]} -gt 0 ]]; then
        summary+="\nPACKAGES:\n"
        for pkg in "${SELECTED_PACKAGES[@]}"; do
            summary+="  - $pkg\n"
        done
    fi

    summary+="\nProceed with installation?"

    dialog_yesno "$summary"
}

run_dialog_installation() {
    clear
    log_header "Starting Installation"

    # Always install brew first if selected
    if [[ " ${SELECTED_COMPONENTS[*]} " =~ " brew " ]]; then
        log_info "Installing Homebrew..."
        source "$SCRIPT_DIR/installers/brew.sh"
        install_brew || log_warn "Homebrew installation skipped or failed"
        echo ""
    fi

    # Install packages if tools selected
    if [[ " ${SELECTED_COMPONENTS[*]} " =~ " tools " ]] && [[ ${#SELECTED_PACKAGES[@]} -gt 0 ]]; then
        log_info "Installing packages..."
        for pkg in "${SELECTED_PACKAGES[@]}"; do
            install_single_package "$pkg"
        done
        echo ""
    fi

    # Run remaining component installers
    for comp in "${SELECTED_COMPONENTS[@]}"; do
        [[ "$comp" == "brew" || "$comp" == "tools" ]] && continue

        log_info "Running $comp installer..."
        case "$comp" in
            zsh)       run_installer "zsh.sh" "install_zsh_config" ;;
            bash)      run_installer "bash.sh" "install_bash_config" ;;
            tmux)      run_installer "tmux.sh" "install_tmux" ;;
            terminals) run_installer "terminals.sh" "install_terminals" ;;
            claude)
                run_installer "claude.sh" "install_npm_packages"
                run_installer "claude.sh" "install_claude_config"
                ;;
            mcp)       run_installer "mcp.sh" "main" ;;
            *)         continue ;;
        esac
        echo ""
    done

    log_success "Installation complete!"
    echo ""
    echo "Press any key to return to menu..."
    read -n 1 -s
}

# Install a single package using install-packages.sh
install_single_package() {
    local pkg="$1"

    # Map package names to install_package arguments
    # Format: install_package "command" "brew_pkg" "apt_pkg" "pacman_pkg"
    case "$pkg" in
        git)        install_package "git" ;;
        curl)       install_package "curl" ;;
        wget)       install_package "wget" ;;
        nvim)       install_package "nvim" "neovim" "neovim" ;;
        tmux)       install_package "tmux" ;;
        zsh)        install_package "zsh" ;;
        node)       install_package "node" "node" "nodejs" ;;
        npm)        install_package "npm" ;;
        ripgrep)    install_package "rg" "ripgrep" "ripgrep" "ripgrep" ;;
        fzf)        install_package "fzf" ;;
        fd)         install_package "fd" "fd" "fd-find" "fd" ;;
        bat)        install_package "bat" ;;
        jq)         install_package "jq" ;;
        git-delta)  install_package "delta" "git-delta" "git-delta" "git-delta" ;;
        lsd)        install_package "lsd" ;;
        zoxide)     install_package "zoxide" ;;
        eza)        install_package "eza" ;;
        chafa)      install_package "chafa" ;;
        htop)       install_package "htop" ;;
        btop)       install_package "btop" ;;
        tree)       install_package "tree" ;;
        gdu)        install_package "gdu" ;;
        terminal-notifier) install_package "terminal-notifier" ;;
        neofetch)   install_package "neofetch" ;;
        tlrc)       install_package "tldr" "tlrc" "tlrc" "tldr" ;;
        *)          log_warn "Unknown package: $pkg" ;;
    esac
}

# =============================================================================
# CLI Mode Functions
# =============================================================================

show_help() {
    echo "Dotfiles Installation Script"
    echo ""
    echo "Usage: ./install.sh [options]"
    echo ""
    echo "Interactive mode (default when no arguments):"
    echo "  ./install.sh              Launch dialog-based installer"
    echo "  ./install.sh --dialog     Force dialog mode"
    echo ""
    echo "CLI mode:"
    echo "  --all          Install everything"
    echo "  --brew         Install Homebrew"
    echo "  --tools        Install common dev tools"
    echo "  --secrets      Create ~/.accessTokens template"
    echo "  --tmux         Install tmux and plugins"
    echo "  --bash         Install bash configuration"
    echo "  --zsh          Install zsh configuration"
    echo "  --nushell      Install nushell configuration"
    echo "  --terminals    Install terminal emulators config"
    echo "  --config-dirs  Symlink config directories"
    echo "  --claude       Install Claude Code settings"
    echo "  --mcp          Install MCP configuration"
    echo "  --memory-hooks Install MCP memory hooks"
    echo "  --logging-hooks Install session logging hooks"
    echo "  --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./install.sh              # Interactive dialog mode"
    echo "  ./install.sh --zsh        # Install only zsh config"
    echo "  ./install.sh --all        # Install everything (CLI mode)"
    echo ""
}

run_installer() {
    local installer="$1"
    local func="$2"
    local install_root="$SCRIPT_DIR"

    if [ -f "$install_root/installers/$installer" ]; then
        source "$install_root/installers/$installer"
        $func
        SCRIPT_DIR="$install_root"
    else
        log_error "Installer not found: $installer"
        return 1
    fi
}

install_all() {
    log_header "Full Dotfiles Installation"

    # Install brew first
    run_installer "brew.sh" "install_brew"

    # Install tools
    run_installer "tools.sh" "install_tools"

    # Create secrets template
    run_installer "secrets.sh" "install_secrets"

    # Install terminal emulators config
    run_installer "terminals.sh" "install_terminals"

    # Install tmux
    run_installer "tmux.sh" "install_tmux"

    # Install shell-specific configs
    run_installer "bash.sh" "install_bash_config"
    run_installer "zsh.sh" "install_zsh_config"

    # Symlink config directories
    run_installer "config-dirs.sh" "install_config_dirs"

    # Install Claude settings
    run_installer "claude.sh" "install_npm_packages"
    run_installer "claude.sh" "install_claude_config"

    # Install MCP configuration
    run_installer "mcp.sh" "main"

    log_header "Installation Complete"
    echo "All dotfiles have been installed successfully."
    echo ""
    echo "Next steps:"
    echo "  1. Restart your shell or run: source ~/.zshrc (or ~/.bashrc)"
    echo "  2. Run 'p10k configure' to setup powerlevel10k prompt"
    echo "  3. Restart Claude Code to pick up new settings"
    echo ""
}

# =============================================================================
# Main Entry Point
# =============================================================================

main() {
    if should_use_dialog "$@"; then
        run_dialog_mode
    else
        local mode="${1:---help}"

        case "$mode" in
            --help|-h)
                show_help
                ;;
            --brew)
                run_installer "brew.sh" "install_brew"
                ;;
            --tools)
                run_installer "tools.sh" "install_tools"
                ;;
            --secrets)
                run_installer "secrets.sh" "install_secrets"
                ;;
            --tmux)
                run_installer "tmux.sh" "install_tmux"
                ;;
            --bash)
                run_installer "bash.sh" "install_bash_config"
                ;;
            --zsh)
                run_installer "zsh.sh" "install_zsh_config"
                ;;
            --nushell)
                run_installer "nushell.sh" "install_nushell_config"
                ;;
            --terminals)
                run_installer "terminals.sh" "install_terminals"
                ;;
            --config-dirs)
                run_installer "config-dirs.sh" "install_config_dirs"
                ;;
            --claude)
                run_installer "claude.sh" "install_npm_packages"
                run_installer "claude.sh" "install_claude_config"
                ;;
            --mcp)
                run_installer "mcp.sh" "main"
                ;;
            --memory-hooks)
                run_installer "memory-hooks.sh" "main"
                ;;
            --logging-hooks)
                run_installer "logging-hooks.sh" "main"
                ;;
            --all)
                install_all
                ;;
            --dialog)
                run_dialog_mode
                ;;
            *)
                log_error "Unknown option: $mode"
                show_help
                exit 1
                ;;
        esac
    fi
}

main "$@"
