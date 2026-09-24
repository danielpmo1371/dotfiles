#!/bin/bash

# Background services installer — Claude Code Remote Control (claude-rc)
# Linux: systemd user unit from config/systemd-services (linked to ~/.config/systemd)
# macOS: launchd LaunchAgent from config/launchd (copied to ~/Library/LaunchAgents)
# Skips cleanly when Claude Code is not installed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

source "$DOTFILES_ROOT/lib/install-common.sh"

CLAUDE_RC_BIN="$HOME/.local/bin/claude"
CLAUDE_RC_WORKDIR="$HOME/repos"

# Linux (systemd user unit)
CLAUDE_RC_UNIT="claude-rc.service"
CLAUDE_RC_SYSTEMD_SOURCE="$DOTFILES_ROOT/config/systemd-services"
CLAUDE_RC_SYSTEMD_TARGET="$HOME/.config/systemd"

# macOS (launchd LaunchAgent)
CLAUDE_RC_LABEL="com.nuvemlabs.claude-rc"
CLAUDE_RC_PLIST_SOURCE="$DOTFILES_ROOT/config/launchd/$CLAUDE_RC_LABEL.plist"
CLAUDE_RC_LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
CLAUDE_RC_MAC_LOG="$HOME/Library/Logs/claude-rc.log"

# Link only the claude-rc unit into an existing user unit dir that this repo
# does not own (a real directory, or a symlink pointing somewhere else).
_link_claude_rc_unit_only() {
    local user_dir="$CLAUDE_RC_SYSTEMD_TARGET/user"
    ensure_dir "$user_dir"
    create_symlink_with_backup "$CLAUDE_RC_SYSTEMD_SOURCE/user/$CLAUDE_RC_UNIT" "$user_dir/$CLAUDE_RC_UNIT"
}

_install_claude_rc_linux() {
    local resolved
    if [ -L "$CLAUDE_RC_SYSTEMD_TARGET" ]; then
        resolved="$(readlink -f "$CLAUDE_RC_SYSTEMD_TARGET")"
        if [ "$resolved" = "$(readlink -f "$CLAUDE_RC_SYSTEMD_SOURCE")" ]; then
            log_success "Already linked: systemd -> $CLAUDE_RC_SYSTEMD_SOURCE"
        else
            log_warn "$CLAUDE_RC_SYSTEMD_TARGET is a symlink to $resolved (not this repo) — leaving it, linking only $CLAUDE_RC_UNIT"
            _link_claude_rc_unit_only || return 1
        fi
    elif [ -d "$CLAUDE_RC_SYSTEMD_TARGET" ]; then
        log_warn "$CLAUDE_RC_SYSTEMD_TARGET is a real directory (may hold other units) — not replacing it, linking only $CLAUDE_RC_UNIT"
        _link_claude_rc_unit_only || return 1
    else
        ensure_dir "$(dirname "$CLAUDE_RC_SYSTEMD_TARGET")"
        create_symlink_with_backup "$CLAUDE_RC_SYSTEMD_SOURCE" "$CLAUDE_RC_SYSTEMD_TARGET" || return 1
    fi

    # No user systemd bus (Docker, containers, CI): link only, don't fail.
    if ! command -v systemctl &>/dev/null || ! systemctl --user show-environment &>/dev/null; then
        log_warn "No systemd user session — linked but not enabled; run: systemctl --user enable --now $CLAUDE_RC_UNIT"
        return 0
    fi

    systemctl --user daemon-reload || {
        log_error "systemctl --user daemon-reload failed"
        return 1
    }
    systemctl --user enable --now "$CLAUDE_RC_UNIT" || {
        log_error "Failed to enable/start $CLAUDE_RC_UNIT (see: journalctl --user -u $CLAUDE_RC_UNIT)"
        return 1
    }
    log_success "$CLAUDE_RC_UNIT enabled and running"
    log_info "Errors are logged to the journal: journalctl --user -u $CLAUDE_RC_UNIT"

    # Linger keeps the user manager (and this service) alive without a login.
    local user="${USER:-$(id -un)}"
    local linger
    linger="$(loginctl show-user "$user" -p Linger --value 2>/dev/null)"
    if [ "$linger" != "yes" ]; then
        log_info "Linger is off: $CLAUDE_RC_UNIT stops when you log out. To keep it running, run: loginctl enable-linger $user"
    fi
}

_install_claude_rc_macos() {
    local domain dest
    domain="gui/$(id -u)"
    dest="$CLAUDE_RC_LAUNCH_AGENTS_DIR/$CLAUDE_RC_LABEL.plist"

    ensure_dir "$CLAUDE_RC_LAUNCH_AGENTS_DIR"
    # Copy, not symlink: symlinked LaunchAgents are unreliable on recent macOS.
    cp "$CLAUDE_RC_PLIST_SOURCE" "$dest" || {
        log_error "Failed to copy $CLAUDE_RC_PLIST_SOURCE to $dest"
        return 1
    }
    log_success "Copied: $CLAUDE_RC_LABEL.plist -> $dest"

    # Unload a previously loaded copy so the new plist takes effect.
    if launchctl print "$domain/$CLAUDE_RC_LABEL" &>/dev/null; then
        log_info "Reloading $CLAUDE_RC_LABEL"
        launchctl bootout "$domain/$CLAUDE_RC_LABEL" || log_warn "launchctl bootout failed — bootstrap may report it as already loaded"
    fi

    launchctl bootstrap "$domain" "$dest" || {
        log_warn "launchctl bootstrap failed — it needs a logged-in GUI session (not plain SSH). Retry from a desktop terminal: launchctl bootstrap $domain $dest"
        return 1
    }
    log_success "$CLAUDE_RC_LABEL loaded"
    log_info "Errors are logged to $CLAUDE_RC_MAC_LOG"
    log_info "LaunchAgents run only while you are logged in (screen lock is fine); a sleeping Mac drops the connection until it wakes"
}

install_services() {
    log_header "Services (claude-rc Remote Control)"

    # Dependency gate: the service only makes sense with Claude Code installed.
    if [ ! -x "$CLAUDE_RC_BIN" ]; then
        log_info "Claude Code not installed (~/.local/bin/claude) — skipping claude-rc service"
        return 0
    fi

    if [ ! -d "$CLAUDE_RC_WORKDIR" ]; then
        log_warn "$CLAUDE_RC_WORKDIR does not exist — claude-rc will fail to start until it does"
    fi

    if [[ "$OSTYPE" == "darwin"* ]]; then
        _install_claude_rc_macos || return 1
    else
        _install_claude_rc_linux || return 1
    fi

    echo ""
    log_success "Services configuration complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_services
fi
