#!/usr/bin/env bash
# Stop Claude Code Remote Control tmux sessions started by rc-start.sh.
# Usage: rc-stop.sh [folder...]
#   With folders: stop them and forget them (they no longer start at login).
#   Without:      stop every folder in the list (list is kept for next login).
# Env: CLAUDE_RC_FOLDERS_FILE, CLAUDE_RC_STOP_TIMEOUT (seconds before force-kill),
#      CLAUDE_RC_TMUX_SOCKET (tmux -L socket name; default: the default server)

set -euo pipefail

FOLDERS_FILE="${CLAUDE_RC_FOLDERS_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/claude-rc/folders}"
SESSION_PREFIX="rc-"
STOP_TIMEOUT="${CLAUDE_RC_STOP_TIMEOUT:-10}"
TMUX_SOCKET="${CLAUDE_RC_TMUX_SOCKET:-}"

tmx() {
    if [ -n "$TMUX_SOCKET" ]; then tmux -L "$TMUX_SOCKET" "$@"; else tmux "$@"; fi
}

session_name() {
    printf '%s%s' "$SESSION_PREFIX" "$(basename "$1" | tr -c 'A-Za-z0-9_\n-' '_')"
}

forget_folder() {
    local remaining
    [ -f "$FOLDERS_FILE" ] || return 0
    remaining="$(grep -vxF "$1" "$FOLDERS_FILE" || true)"
    if [ -n "$remaining" ]; then
        printf '%s\n' "$remaining" >"$FOLDERS_FILE"
    else
        : >"$FOLDERS_FILE"
    fi
}

# Command lines of a pid and all its descendants (POSIX ps, works on macOS).
process_tree_args() {
    ps -A -o pid= -o ppid= -o args= | awk -v root="$1" '
        { pid = $1; ppid = $2; $1 = ""; $2 = ""; args[pid] = $0; parent[pid] = ppid }
        END {
            keep[root] = 1
            do {
                changed = 0
                for (p in parent) if (!(p in keep) && (parent[p] in keep)) { keep[p] = 1; changed = 1 }
            } while (changed)
            for (p in keep) if (p in args) print args[p]
        }'
}

session_has_bridge() {
    local pid
    for pid in $1; do
        process_tree_args "$pid" | grep -Eq 'claude remote-control( |$)' && return 0
    done
    return 1
}

# kill-session only sends SIGHUP, which the bridge ignores, leaving an orphaned
# claude that still holds the folder. SIGTERM shuts it down and deregisters it.
stop_folder() {
    local name pids pid waited=0
    name="$(session_name "$1")"
    if ! tmx has-session -t "=$name" 2>/dev/null; then
        echo "rc-stop: $name not running"
        return 0
    fi

    pids="$(tmx list-panes -s -t "=$name" -F '#{pane_pid}')"
    # No bridge (e.g. a shell restored by tmux-resurrect): nothing to deregister,
    # and an interactive shell ignores SIGTERM, so don't wait out the timeout.
    if ! session_has_bridge "$pids"; then
        tmx kill-session -t "=$name" 2>/dev/null || true
        echo "rc-stop: stopped $name (no bridge was running)"
        return 0
    fi

    for pid in $pids; do kill -TERM "$pid" 2>/dev/null || true; done
    while tmx has-session -t "=$name" 2>/dev/null && [ "$waited" -lt "$STOP_TIMEOUT" ]; do
        sleep 1
        waited=$((waited + 1))
    done

    if tmx has-session -t "=$name" 2>/dev/null; then
        for pid in $pids; do kill -KILL "$pid" 2>/dev/null || true; done
        tmx kill-session -t "=$name" 2>/dev/null || true
        echo "rc-stop: force-stopped $name after ${STOP_TIMEOUT}s"
    else
        echo "rc-stop: stopped $name"
    fi
}

resolve() {
    if [ -d "$1" ]; then (cd "$1" && pwd -P); else printf '%s' "$1"; fi
}

if [ "$#" -gt 0 ]; then
    for arg in "$@"; do
        dir="$(resolve "$arg")"
        stop_folder "$dir"
        forget_folder "$dir"
    done
elif [ -f "$FOLDERS_FILE" ]; then
    while IFS= read -r line; do
        case "$line" in ''|'#'*) continue ;; esac
        stop_folder "$line"
    done <"$FOLDERS_FILE"
else
    echo "rc-stop: no folders given and $FOLDERS_FILE does not exist" >&2
    exit 1
fi
