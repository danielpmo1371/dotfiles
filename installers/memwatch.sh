#!/bin/bash

# Memory-exhaustion protection (Linux, systemd)
#
# 1. mem-pressure-watch.service (systemd user unit): PSI watcher that logs the
#    top memory users and warns on the desktop and phone before a freeze.
# 2. systemd-oomd with ManagedOOMMemoryPressure=kill on user@.service (system
#    drop-in, needs sudo): kills the runaway pane's cgroup after 20s of high
#    pressure instead of the desktop freezing until the kernel OOM killer fires.
#
# Dependencies: python3, systemd (user manager + systemd-oomd)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"

MEMWATCH_UNIT="mem-pressure-watch.service"
MEMWATCH_UNIT_SOURCE="$DOTFILES_ROOT/config/systemd-services/user/$MEMWATCH_UNIT"
MEMWATCH_USER_UNIT_DIR="$HOME/.config/systemd/user"
OOMD_DROPIN_NAME="90-mem-pressure-kill.conf"
OOMD_DROPIN_SOURCE="$DOTFILES_ROOT/config/systemd-oomd/user@.service.d/$OOMD_DROPIN_NAME"
OOMD_DROPIN_DIR="${MEMWATCH_OOMD_DROPIN_DIR:-/etc/systemd/system/user@.service.d}"

_install_memwatch_user_unit() {
    # ~/.config/systemd is normally the repo's config/systemd-services (linked by
    # --services); otherwise link just this unit into the existing user dir.
    if [[ "$(readlink -f "$MEMWATCH_USER_UNIT_DIR/$MEMWATCH_UNIT" 2>/dev/null)" != "$MEMWATCH_UNIT_SOURCE" ]]; then
        ensure_dir "$MEMWATCH_USER_UNIT_DIR"
        create_symlink_with_backup "$MEMWATCH_UNIT_SOURCE" "$MEMWATCH_USER_UNIT_DIR/$MEMWATCH_UNIT" || return 1
    fi

    if ! command -v systemctl &>/dev/null || ! systemctl --user show-environment &>/dev/null; then
        log_warn "No systemd user session — linked but not enabled; run: systemctl --user enable --now $MEMWATCH_UNIT"
        return 0
    fi
    systemctl --user daemon-reload || { log_error "systemctl --user daemon-reload failed"; return 1; }
    systemctl --user enable --now "$MEMWATCH_UNIT" || {
        log_error "Failed to enable $MEMWATCH_UNIT (see: journalctl --user -u $MEMWATCH_UNIT)"
        return 1
    }
    log_success "$MEMWATCH_UNIT enabled and running (log: ~/.local/state/mem-pressure/events.log)"
}

_install_oomd() {
    local target="$OOMD_DROPIN_DIR/$OOMD_DROPIN_NAME"
    if [[ ! -x /usr/lib/systemd/systemd-oomd ]]; then
        log_warn "systemd-oomd not found — skipping the kill policy (the watcher still runs)"
        return 0
    fi
    if cmp -s "$OOMD_DROPIN_SOURCE" "$target" && systemctl is-active --quiet systemd-oomd; then
        log_info "systemd-oomd already active with $target"
        return 0
    fi
    # A system file: copied, not linked, so root never reads config from $HOME.
    log_info "Installing $target and enabling systemd-oomd (sudo)..."
    sudo install -D -m 0644 "$OOMD_DROPIN_SOURCE" "$target" &&
        sudo systemctl daemon-reload &&
        sudo systemctl enable --now systemd-oomd || {
        log_error "oomd setup failed; run by hand: sudo install -D -m 0644 $OOMD_DROPIN_SOURCE $target && sudo systemctl daemon-reload && sudo systemctl enable --now systemd-oomd"
        return 1
    }
    log_success "systemd-oomd active; check with: oomctl"
}

install_memwatch() {
    log_header "Memory pressure protection (mem-pressure-watch + systemd-oomd)"
    if [[ "$(uname -s)" != "Linux" ]]; then
        log_info "Linux only (PSI and systemd-oomd) — skipping"
        return 0
    fi
    if ! command -v python3 &>/dev/null; then
        log_error "python3 not found (./install.sh --tools)"
        return 1
    fi
    _install_memwatch_user_unit || return 1
    _install_oomd || return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_memwatch
fi
