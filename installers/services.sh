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

# Per-folder tmux sessions (rc-start.sh / rc-stop.sh, symlinked into ~/bin)
CLAUDE_RC_SCRIPTS=("rc-start.sh" "rc-stop.sh")
CLAUDE_RC_SCRIPTS_SOURCE="$DOTFILES_ROOT/util-scripts"
CLAUDE_RC_BIN_DIR="$HOME/bin"

# Linux (systemd user units)
CLAUDE_RC_UNIT="claude-rc.service"
CLAUDE_RC_SESSIONS_UNIT="claude-rc-sessions.service"
# Started by hyprland.lua on login; brings up graphical-session.target, which
# the units are WantedBy (not default.target, which linger starts at boot).
CLAUDE_RC_SESSION_TARGET="hyprland-session.target"
CLAUDE_RC_SYSTEMD_SOURCE="$DOTFILES_ROOT/config/systemd-services"
CLAUDE_RC_SYSTEMD_TARGET="$HOME/.config/systemd"

# macOS (launchd LaunchAgent)
CLAUDE_RC_LABEL="com.nuvemlabs.claude-rc"
CLAUDE_RC_SESSIONS_LABEL="com.nuvemlabs.claude-rc-sessions"
CLAUDE_RC_LAUNCHD_SOURCE="$DOTFILES_ROOT/config/launchd"
CLAUDE_RC_LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
CLAUDE_RC_MAC_LOG="$HOME/Library/Logs/claude-rc.log"
CLAUDE_RC_SESSIONS_MAC_LOG="$HOME/Library/Logs/claude-rc-sessions.log"

# Link only the claude-rc units (and the session target they start from) into
# an existing user unit dir that this repo does not own (a real directory, or a
# symlink pointing somewhere else).
_link_claude_rc_units_only() {
    local user_dir="$CLAUDE_RC_SYSTEMD_TARGET/user" unit
    ensure_dir "$user_dir"
    for unit in "$CLAUDE_RC_UNIT" "$CLAUDE_RC_SESSIONS_UNIT" "$CLAUDE_RC_SESSION_TARGET"; do
        create_symlink_with_backup "$CLAUDE_RC_SYSTEMD_SOURCE/user/$unit" "$user_dir/$unit" || return 1
    done
}

# rc-start.sh / rc-stop.sh live in util-scripts; ~/bin is where the units and the user call them.
_link_claude_rc_scripts() {
    local script
    ensure_dir "$CLAUDE_RC_BIN_DIR"
    for script in "${CLAUDE_RC_SCRIPTS[@]}"; do
        create_symlink_with_backup "$CLAUDE_RC_SCRIPTS_SOURCE/$script" "$CLAUDE_RC_BIN_DIR/$script" || return 1
    done
}

_install_claude_rc_linux() {
    local resolved
    if [ -L "$CLAUDE_RC_SYSTEMD_TARGET" ]; then
        resolved="$(readlink -f "$CLAUDE_RC_SYSTEMD_TARGET")"
        if [ "$resolved" = "$(readlink -f "$CLAUDE_RC_SYSTEMD_SOURCE")" ]; then
            log_success "Already linked: systemd -> $CLAUDE_RC_SYSTEMD_SOURCE"
        else
            log_warn "$CLAUDE_RC_SYSTEMD_TARGET is a symlink to $resolved (not this repo) — leaving it, linking only the claude-rc units"
            _link_claude_rc_units_only || return 1
        fi
    elif [ -d "$CLAUDE_RC_SYSTEMD_TARGET" ]; then
        log_warn "$CLAUDE_RC_SYSTEMD_TARGET is a real directory (may hold other units) — not replacing it, linking only the claude-rc units"
        _link_claude_rc_units_only || return 1
    else
        ensure_dir "$(dirname "$CLAUDE_RC_SYSTEMD_TARGET")"
        create_symlink_with_backup "$CLAUDE_RC_SYSTEMD_SOURCE" "$CLAUDE_RC_SYSTEMD_TARGET" || return 1
    fi

    # No user systemd bus (Docker, containers, CI): link only, don't fail.
    if ! command -v systemctl &>/dev/null || ! systemctl --user show-environment &>/dev/null; then
        log_warn "No systemd user session — linked but not enabled; run: systemctl --user enable --now $CLAUDE_RC_UNIT $CLAUDE_RC_SESSIONS_UNIT"
        return 0
    fi

    systemctl --user daemon-reload || {
        log_error "systemctl --user daemon-reload failed"
        return 1
    }
    local unit
    for unit in "$CLAUDE_RC_UNIT" "$CLAUDE_RC_SESSIONS_UNIT"; do
        systemctl --user enable --now "$unit" || {
            log_error "Failed to enable/start $unit (see: journalctl --user -u $unit)"
            return 1
        }
        log_success "$unit enabled and running"
        log_info "Errors are logged to the journal: journalctl --user -u $unit"
    done
    log_info "Units start on login via $CLAUDE_RC_SESSION_TARGET (hyprland.lua), not at boot"

    # Linger keeps the user manager (and this service) alive without a login.
    local user="${USER:-$(id -un)}"
    local linger
    linger="$(loginctl show-user "$user" -p Linger --value 2>/dev/null)"
    if [ "$linger" != "yes" ]; then
        log_info "Linger is off: $CLAUDE_RC_UNIT stops when you log out. To keep it running, run: loginctl enable-linger $user"
    fi
}

# Copy one plist into ~/Library/LaunchAgents and (re)load it into the GUI domain.
_load_launch_agent() {
    local label="$1" log="$2" domain dest
    domain="gui/$(id -u)"
    dest="$CLAUDE_RC_LAUNCH_AGENTS_DIR/$label.plist"

    # Copy, not symlink: symlinked LaunchAgents are unreliable on recent macOS.
    cp "$CLAUDE_RC_LAUNCHD_SOURCE/$label.plist" "$dest" || {
        log_error "Failed to copy $CLAUDE_RC_LAUNCHD_SOURCE/$label.plist to $dest"
        return 1
    }
    log_success "Copied: $label.plist -> $dest"

    # Unload a previously loaded copy so the new plist takes effect.
    if launchctl print "$domain/$label" &>/dev/null; then
        log_info "Reloading $label"
        launchctl bootout "$domain/$label" || log_warn "launchctl bootout failed — bootstrap may report it as already loaded"
    fi

    launchctl bootstrap "$domain" "$dest" || {
        log_warn "launchctl bootstrap failed — it needs a logged-in GUI session (not plain SSH). Retry from a desktop terminal: launchctl bootstrap $domain $dest"
        return 1
    }
    log_success "$label loaded"
    log_info "Errors are logged to $log"
}

_install_claude_rc_macos() {
    ensure_dir "$CLAUDE_RC_LAUNCH_AGENTS_DIR"
    _load_launch_agent "$CLAUDE_RC_LABEL" "$CLAUDE_RC_MAC_LOG" || return 1
    _load_launch_agent "$CLAUDE_RC_SESSIONS_LABEL" "$CLAUDE_RC_SESSIONS_MAC_LOG" || return 1
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

    _link_claude_rc_scripts || return 1

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
