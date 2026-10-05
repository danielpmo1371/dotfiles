#!/bin/bash

# Quickshell control hub installer — Linux only (auto-run by hypr.sh)
# Symlinks config/quickshell/ to ~/.config/quickshell. Hyprland starts it with
# util-scripts/hub-shell and SUPER+A toggles it (config/hypr/hyprland.lua).
#
# Config-only, like hypr.sh: missing packages are reported, not installed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"

# What the hub and its panels call, with the Arch package that provides it.
QUICKSHELL_DEPS=(
    "qs:quickshell"
    "nmcli:networkmanager"
    "bluetoothctl:bluez-utils"
    "wpctl:wireplumber"
    "powerprofilesctl:power-profiles-daemon"
    "wofi:wofi"
    "ghostty:ghostty"
    "notify-send:libnotify"
    "jq:jq"
    "curl:curl"
    "qrencode:qrencode"
)

install_quickshell() {
    log_header "Quickshell control hub"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        log_info "Quickshell is Linux-only, skipping"
        return 0
    fi

    link_config_dirs "quickshell"

    local entry missing=()
    for entry in "${QUICKSHELL_DEPS[@]}"; do
        command -v "${entry%%:*}" &>/dev/null || missing+=("${entry##*:}")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        log_warn "Missing packages for the hub: ${missing[*]} (e.g. sudo pacman -S --needed ${missing[*]})"
    fi

    # Restart a running hub so it picks up the new config.
    if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v qs &>/dev/null; then
        if "$DOTFILES_ROOT/util-scripts/hub-shell" restart; then
            log_success "Control hub restarted"
        else
            log_warn "Control hub restart failed; it starts at the next Hyprland login"
        fi
    fi

    echo ""
    log_success "Quickshell control hub configuration complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_quickshell
fi
