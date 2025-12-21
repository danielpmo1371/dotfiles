#!/bin/bash

# Nushell configuration installer

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"
source "$DOTFILES_ROOT/lib/install-packages.sh"

install_nushell_config() {
    log_header "Nushell Configuration"

    # Install nushell if not present
    install_package "nu" "nushell" "nushell"

    # Install zoxide if not present
    install_package "zoxide" "zoxide" "zoxide"

    # Install starship prompt
    install_package "starship" "starship" "starship"

    # Generate integration files BEFORE symlinking config
    # (nushell sources these at parse time, not runtime)
    log_info "Generating tool integrations..."
    mkdir -p "$HOME/.cache/starship"

    if command -v zoxide &> /dev/null; then
        zoxide init nushell > "$HOME/.zoxide.nu"
        log_success "Zoxide: ~/.zoxide.nu"
    else
        # Create empty file so nushell doesn't fail on source
        echo "# zoxide not installed" > "$HOME/.zoxide.nu"
        log_warn "Zoxide not found - created placeholder"
    fi

    if command -v starship &> /dev/null; then
        starship init nu > "$HOME/.cache/starship/init.nu"
        log_success "Starship: ~/.cache/starship/init.nu"
    else
        # Create empty module so nushell doesn't fail on use
        echo "# starship not installed" > "$HOME/.cache/starship/init.nu"
        log_warn "Starship not found - created placeholder"
    fi

    # Symlink config directory
    link_config_dirs "nushell"

    echo ""
    log_info "Nushell config installation complete"
    echo ""
    echo "Files installed:"
    echo "  ~/.config/nushell/config.nu  - main config"
    echo "  ~/.config/nushell/env.nu     - environment variables"
    echo "  ~/.config/nushell/aliases.nu - aliases and functions"
    echo ""
    echo "Next steps:"
    echo "  1. Run 'nu' to start nushell"
    echo "  2. Run 'starship preset pure-preset -o ~/.config/starship.toml' for a clean prompt"
    echo "  3. Add secrets to ~/.accessTokens"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_nushell_config
fi
