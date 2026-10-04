#!/bin/bash

# Hyprland (Wayland compositor) configuration installer — Linux only
# Symlinks config/hypr/ to ~/.config/hypr

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"

# The control hub is part of the Hyprland desktop (autostarted and bound in
# hyprland.lua), so --hypr installs it too. A failure is warned about, never
# fatal, matching zsh.sh's completions dependency.
run_quickshell_dependency() {
    local installer="$DOTFILES_ROOT/installers/quickshell.sh"

    if [[ ! -x "$installer" ]]; then
        log_warn "quickshell.sh not found or not executable: $installer"
        return 0
    fi

    if ! "$installer"; then
        log_warn "Quickshell control hub installer reported failures"
    fi
}

install_hypr() {
    log_header "Hyprland"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        log_info "Hyprland is Linux-only, skipping"
        return 0
    fi

    if ! command -v hyprctl &>/dev/null; then
        log_warn "Hyprland (hyprctl) not found — linking config anyway (takes effect once Hyprland is installed)"
    fi

    # Symlink config directory to ~/.config/hypr
    link_config_dirs "hypr"

    # Launcher entries (wofi drun). Per-file links: ~/.local/share/applications
    # is shared with entries other apps install there.
    link_target_files "applications" "$HOME/.local/share/applications" "wayle.desktop"

    # Keybinding dependencies (launcher, screenshots, clipboard history). Config-only installer:
    # warn, don't install — package installation stays in tools.sh territory.
    local dep missing=()
    for dep in wofi grim slurp wl-copy wl-paste cliphist awww jq notify-send; do
        command -v "$dep" &>/dev/null || missing+=("$dep")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        log_warn "Missing binaries used by binds: ${missing[*]} (install via your package manager)"
    fi

    # Apply live if a Hyprland session is running
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl &>/dev/null; then
        if hyprctl reload &>/dev/null; then
            local errors
            errors="$(hyprctl configerrors 2>/dev/null)"
            if [ -n "$errors" ] && [ "$errors" != "no errors" ]; then
                log_warn "Hyprland reloaded with config errors:"
                echo "$errors"
            else
                log_success "Hyprland config reloaded"
            fi
        else
            log_warn "hyprctl reload failed — config will apply on next Hyprland start"
        fi
    fi

    run_quickshell_dependency

    echo ""
    log_success "Hyprland configuration complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_hypr
fi
