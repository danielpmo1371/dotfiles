#!/bin/bash

# Zsh configuration installer
#
# Dependencies: zsh, curl (for Zap installation)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"

# Files to symlink: "source:target" (source in config/zsh/, target in $HOME)
ZSH_FILES=(
    "zshrc:.zshrc"
    "p10k.zsh:.p10k.zsh"
)

# Run the custom completions installer. The completion files are part of the
# zsh config, so they are a dependency of --zsh rather than an optional extra.
# A failure is warned about and never fatal, matching claude.sh's
# run_hook_dependency: a broken completion must not abort the whole --zsh run.
run_zsh_completions_dependency() {
    local installer="$DOTFILES_ROOT/installers/zsh-completions.sh"

    if [[ ! -x "$installer" ]]; then
        log_warn "zsh-completions.sh not found or not executable: $installer"
        return 0
    fi

    log_info "Installing custom zsh completions (dependency)..."
    if ! "$installer"; then
        log_warn "Zsh completions installer reported failures"
    fi
}

install_zsh_config() {
    log_header "Zsh Configuration"

    # Check dependencies
    local zsh_available=true
    local curl_available=true

    if ! command -v zsh &> /dev/null; then
        log_warn "zsh not found - install zsh first"
        log_info "Run './install.sh --tools' or install zsh manually"
        zsh_available=false
    fi
    if ! command -v curl &> /dev/null; then
        log_warn "curl not found - required to install Zap plugin manager"
        curl_available=false
    fi

    link_home_files "zsh" "${ZSH_FILES[@]}"

    # Custom completions live in a shared fpath dir, so they get their own
    # per-file installer (see installers/zsh-completions.sh)
    run_zsh_completions_dependency

    # Install Zap plugin manager if not present (only if zsh and curl are available)
    if [[ "$zsh_available" == "true" ]] && [[ "$curl_available" == "true" ]]; then
        local zap_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zap"
        if [ ! -d "$zap_dir" ]; then
            log_info "Installing Zap plugin manager..."
            zsh <(curl -s https://raw.githubusercontent.com/zap-zsh/zap/master/install.zsh) --branch release-v1 --keep
        else
            log_success "Zap already installed"
        fi
    elif [[ "$zsh_available" == "false" ]]; then
        log_warn "Skipping Zap installation - zsh not available"
        log_info "Run this installer again after installing zsh to complete setup"
    elif [[ "$curl_available" == "false" ]]; then
        log_warn "Skipping Zap installation - curl not available"
        log_info "Run this installer again after installing curl to complete setup"
    fi

    echo ""
    log_info "Zsh config installation complete"
    echo ""
    echo "Files installed:"
    echo "  - .zshrc (main config)"
    echo "  - .p10k.zsh (Powerlevel10k theme customizations)"
    echo "  - ~/.local/share/zsh/completions/_* (custom completions, per-file symlinks)"
    echo ""
    echo "Plugins (via Zap): powerlevel10k, zsh-autosuggestions, zsh-syntax-highlighting"
    echo ""
    echo "Next steps:"
    echo "  1. Run 'source ~/.zshrc' to reload"
    echo "  2. Your custom p10k theme is already configured!"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_zsh_config
fi
