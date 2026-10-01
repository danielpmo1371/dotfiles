#!/usr/bin/env bash
# Start one Claude Code Remote Control tmux session per folder (skips running ones).
# Usage: rc-start.sh [folder...] | rc-start.sh --if-listed
#   With folders: start them and remember them in the folder list.
#   Without:      start every folder in the list (what the login service does).
#   --if-listed:  same, but a missing or empty list is a silent no-op (the
#                 tmux-resurrect post-restore hook uses this).
# A session counts as running only if its pane runs the bridge. A session whose
# only pane is an idle shell (e.g. restored by tmux-resurrect) gets the bridge
# respawned in that pane; a session running anything else is left alone. A
# pane that is not idle yet (a restored login shell still initialising) is
# polled for up to @claude-rc-idle-timeout seconds (tmux option, default 30).
# Env: CLAUDE_BIN, CLAUDE_RC_FOLDERS_FILE, CLAUDE_RC_PERMISSION_MODE,
#      CLAUDE_RC_TMUX_SOCKET (tmux -L socket name; default: the default server)

set -euo pipefail

CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
FOLDERS_FILE="${CLAUDE_RC_FOLDERS_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/claude-rc/folders}"
PERMISSION_MODE="${CLAUDE_RC_PERMISSION_MODE:-bypassPermissions}"
TMUX_SOCKET="${CLAUDE_RC_TMUX_SOCKET:-}"
SESSION_PREFIX="rc-"
# Shells a pane can be idle in (pane_current_command, login "-" stripped).
IDLE_SHELLS=" zsh bash sh dash ksh fish tcsh csh "
DEFAULT_IDLE_TIMEOUT=30
POLL_INTERVAL=0.5
# Consecutive idle polls before respawning, so a shell between two transient
# children (a login still sourcing its rc) is not mistaken for idle.
IDLE_STABLE_POLLS=2

tmx() {
    if [ -n "$TMUX_SOCKET" ]; then tmux -L "$TMUX_SOCKET" "$@"; else tmux "$@"; fi
}

session_name() {
    printf '%s%s' "$SESSION_PREFIX" "$(basename "$1" | tr -c 'A-Za-z0-9_\n-' '_')"
}

remember_folder() {
    mkdir -p "$(dirname "$FOLDERS_FILE")"
    touch "$FOLDERS_FILE"
    grep -qxF "$1" "$FOLDERS_FILE" || printf '%s\n' "$1" >>"$FOLDERS_FILE"
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

# Matches both the bridge itself and the `zsh -lic` that is about to exec it.
has_bridge() {
    process_tree_args "$1" | grep -Eq 'claude remote-control( |$)'
}

has_children() {
    ps -A -o ppid= | awk -v root="$1" '$1 == root { found = 1 } END { exit !found }'
}

# Runs `tmux <subcommand + options> -- <bridge command>` for folder $1.
run_bridge() {
    local dir="$1"
    shift
    tmx "$@" -- \
        zsh -lic 'exec "$0" "$@"' "$CLAUDE_BIN" remote-control \
        --permission-mode "$PERMISSION_MODE" --spawn same-dir --name "$(uname -n | cut -d. -f1)-$(basename "$dir")"
}

# Classify a pane: bridge (runs it), dead, idle (a shell with no children, as
# tmux-resurrect restores it) or busy (anything else).
pane_state() {
    local pid="$1" dead="$2" cmd="${3#-}"
    if [ "$dead" = 1 ]; then
        echo dead
    elif case "$pid" in ''|*[!0-9]*) true ;; *) false ;; esac; then
        echo busy
    elif has_bridge "$pid"; then
        echo bridge
    elif case "$IDLE_SHELLS" in *" $cmd "*) true ;; *) false ;; esac && ! has_children "$pid"; then
        echo idle
    else
        echo busy
    fi
}

# Seconds to wait for a pane to become idle, from the tmux option.
idle_timeout() {
    local value
    value="$(tmx show-options -gqv @claude-rc-idle-timeout 2>/dev/null)" || value=""
    case "$value" in
        '') value="$DEFAULT_IDLE_TIMEOUT" ;;
        *[!0-9]*)
            echo "rc-start: invalid @claude-rc-idle-timeout '$value', using $DEFAULT_IDLE_TIMEOUT" >&2
            value="$DEFAULT_IDLE_TIMEOUT"
            ;;
    esac
    printf '%s' "$value"
}

# Sets S_PANES and, for the session's pane(s), S_STATE (bridge if any pane runs
# it, else the last pane's state), S_PANE and S_CMD.
inspect_session() {
    local name="$1" pane_id pane_pid pane_dead cmd state
    S_PANES=0 S_STATE="" S_PANE="" S_CMD=""
    # "|" separated: a dead pane has an empty pane_pid, which whitespace
    # splitting would collapse, shifting every field after it.
    while IFS='|' read -r pane_id pane_dead pane_pid cmd; do
        [ -n "$pane_id" ] || continue
        S_PANES=$((S_PANES + 1))
        state="$(pane_state "$pane_pid" "$pane_dead" "$cmd")"
        S_STATE="$state" S_PANE="$pane_id" S_CMD="$cmd"
        [ "$state" = bridge ] && return 0
    done <<EOF
$(tmx list-panes -s -t "=$name" -F '#{pane_id}|#{pane_dead}|#{pane_pid}|#{pane_current_command}' 2>/dev/null)
EOF
    return 0
}

# Session exists: skip if the bridge runs, respawn it into a lone idle or dead
# pane, wait (bounded) for a lone busy pane to become idle, leave anything else
# alone.
revive_session() {
    local name="$1" dir="$2" timeout max_polls polls=0 stable=0
    timeout="$(idle_timeout)"
    max_polls="$(awk -v t="$timeout" -v p="$POLL_INTERVAL" 'BEGIN { printf "%d", t / p }')"
    while :; do
        inspect_session "$name"
        if [ "$S_STATE" = bridge ]; then
            echo "rc-start: $name already running, skipped"
            return 0
        fi
        if [ "$S_PANES" -ne 1 ]; then
            echo "rc-start: $name exists without the bridge but has $S_PANES panes, left alone" >&2
            return 1
        fi
        case "$S_STATE" in
            dead) break ;;
            idle)
                stable=$((stable + 1))
                if [ "$stable" -ge "$IDLE_STABLE_POLLS" ] || [ "$polls" -ge "$max_polls" ]; then break; fi
                ;;
            *) stable=0 ;;
        esac
        if [ "$polls" -ge "$max_polls" ]; then
            echo "rc-start: $name exists without the bridge but runs something else ($S_CMD, not idle within ${timeout}s), left alone" >&2
            return 1
        fi
        polls=$((polls + 1))
        sleep "$POLL_INTERVAL"
    done

    run_bridge "$dir" respawn-pane -k -t "$S_PANE" -c "$dir"
    echo "rc-start: restarted bridge in $name ($dir, pane was $S_STATE $S_CMD)"
}

start_folder() {
    local dir name
    if ! dir="$(cd "$1" 2>/dev/null && pwd -P)"; then
        echo "rc-start: not a directory: $1" >&2
        return 1
    fi
    name="$(session_name "$dir")"

    if tmx has-session -t "=$name" 2>/dev/null; then
        revive_session "$name" "$dir"
        return
    fi

    run_bridge "$dir" new-session -d -s "$name" -c "$dir"
    echo "rc-start: started $name ($dir)"
}

# --if-listed: nothing listed (no file, or only blanks/comments) -> no-op.
if [ "${1:-}" = --if-listed ]; then
    shift
    if [ "$#" -eq 0 ] && ! grep -Eqv '^(#.*)?$' "$FOLDERS_FILE" 2>/dev/null; then
        exit 0
    fi
fi

if [ ! -x "$CLAUDE_BIN" ]; then
    echo "rc-start: claude not found at $CLAUDE_BIN" >&2
    exit 1
fi

folders=()
if [ "$#" -gt 0 ]; then
    for arg in "$@"; do
        if [ -d "$arg" ]; then
            remember_folder "$(cd "$arg" && pwd -P)"
        fi
        folders+=("$arg")
    done
elif [ -f "$FOLDERS_FILE" ]; then
    while IFS= read -r line; do
        case "$line" in ''|'#'*) continue ;; esac
        folders+=("$line")
    done <"$FOLDERS_FILE"
else
    echo "rc-start: no folders given and $FOLDERS_FILE does not exist" >&2
    exit 1
fi

[ "${#folders[@]}" -gt 0 ] || exit 0

status=0
for folder in "${folders[@]}"; do
    start_folder "$folder" || status=1
done
exit "$status"
