#!/bin/bash
#
# tmux-restart.sh - cleanly exit every Claude Code instance running in a tmux
# pane, save the layout with tmux-resurrect, then kill the tmux server.
#
# Why: Claude Code prints `claude --resume <id>` into its pane on a clean exit.
# tmux-resurrect saves pane contents, so if the save happens AFTER claude has
# exited (and BEFORE kill-server), the restored panes carry that hint and
# `cres` / prefix+R (config/shell/aliases.sh) can resume each pane's session.
#
# Flow: find claude panes -> C-c, `/exit` Enter -> wait for exit (re-sending
#       `/exit` every TMUX_RESTART_RETRY seconds; a `/exit` typed right after
#       an interrupt is swallowed while claude re-renders) -> settle ->
#       tmux-resurrect save.sh -> tmux kill-server. Restart with `start`, then
#       prefix+R in each pane runs `cres`.
#
# Note: a claude with no turns yet exits on `/exit` without printing a resume
# hint; there is nothing to resume, so `cres` has nothing to find there.
#
# Single-pane mode (--pane <pane_id>, repeatable): run the same exit sequence
# on just those panes and stop there: no resurrect save, no kill-server. Used
# by prefix + X to test the clean-exit + `cres` round-trip on one pane.
#
# Usage:
#   tmux-restart.sh [--force] [--dry-run] [-L <socket-name>] [-h|--help]
#   tmux-restart.sh --pane <pane_id> [--pane <pane_id> ...] [--dry-run] [-L <socket-name>]
#
# Keybinding: prefix + C-q / prefix + M-q (all panes), prefix + X (this pane)
#             (see config/tmux/tmux.conf)
# Alias:      trs (see config/shell/tmux.sh)

set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# Tunables (all overridable from the environment)
TIMEOUT="${TMUX_RESTART_TIMEOUT:-30}"        # seconds to wait for claude to exit
RETRY="${TMUX_RESTART_RETRY:-5}"             # seconds between /exit re-sends while waiting
POLL="${TMUX_RESTART_POLL:-0.5}"             # seconds between exit checks
SETTLE="${TMUX_RESTART_SETTLE:-1}"           # seconds after last exit before saving (prompt redraw)
KEY_PAUSE="${TMUX_RESTART_KEY_PAUSE:-1}"     # seconds between keystroke batches (interrupt re-render needs ~1s)
DEFAULT_PLUGIN_PATH="$HOME/.tmux/plugins"
SETTINGS_FILE="${TMUX_RESTART_SETTINGS:-$HOME/.claude/settings.json}"
RESURRECT_SAVE_REL="tmux-resurrect/scripts/save.sh"

# A process is "claude" when its args start with, or contain a path ending in,
# the word claude: matches the native binary, a wrapper script named claude on
# PATH (`bash /path/to/claude`) and flagged invocations (`claude --rc ...`).
# It also matches `claude --chrome-native-host` (the Chrome extension host),
# which is harmless: only processes under a pane's process tree are considered.
CLAUDE_ARGS_RE='(^|/)claude( |$)'

FORCE=0
DRY_RUN=0
SOCKET=""
PANE_FILTER=""   # newline-separated pane ids from --pane; empty = every pane

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [--force] [--dry-run] [-L <socket-name>] [-h|--help]
       $SCRIPT_NAME --pane <pane_id> [--pane <pane_id> ...] [--dry-run] [-L <socket-name>]

Exit every Claude Code instance running in a tmux pane (so each prints its
\`claude --resume <id>\` hint), run tmux-resurrect save, then kill the server.
With --pane, only exit claude in the given pane(s) and stop: the layout is not
saved and the server keeps running (prefix + R / \`cres\` then resumes it).

Options:
  --pane <pane_id>   Only target this pane (repeatable, e.g. %3). Skips the
                     resurrect save and kill-server. A pane without claude is
                     a no-op (warning, exit 0). Cannot be combined with
                     --force: there is nothing to force in this mode.
  --force            Kill the server even if some claude processes are still
                     running after the timeout (they get SIGHUP from tmux) or
                     the tmux-resurrect save script cannot be found (layout
                     and resume hints are then lost).
  --dry-run          List the panes that would be exited and stop.
  -L <socket-name>   tmux socket name, passed to every tmux call (tests).
  -h, --help         Show this help.

Environment:
  TMUX_RESTART_TIMEOUT    Seconds to wait for claude to exit   (default 30)
  TMUX_RESTART_RETRY      Seconds between /exit re-sends to
                          panes still running claude           (default 5)
  TMUX_RESTART_POLL       Seconds between exit checks          (default 0.5)
  TMUX_RESTART_SETTLE     Seconds to wait after the last exit
                          before saving, so prompts redraw     (default 1)
  TMUX_RESTART_KEY_PAUSE  Seconds between keystroke batches    (default 1)
  TMUX_RESTART_SETTINGS   Claude settings.json used to detect
                          "vimMode" (default ~/.claude/settings.json)
  TMUX_PLUGIN_MANAGER_PATH
                          Where tmux-resurrect lives. Resolved like TPM does:
                          the tmux server's global environment first
                          (set-environment -g in tmux.conf), then this
                          variable, then ~/.tmux/plugins. A leading ~ is
                          expanded and a trailing / dropped.

Exit status: 0 on success; 1 when no server is reachable, claude did not exit
in time, or save.sh is missing (the last two proceed with --force).
With --pane: 0 when claude is gone from every given pane (or was not running
there), 1 on timeout or an unknown pane id.
EOF
}

log() { printf '%s: %s\n' "$SCRIPT_NAME" "$*"; }
warn() { printf '%s: warning: %s\n' "$SCRIPT_NAME" "$*" >&2; }
die() { printf '%s: error: %s\n' "$SCRIPT_NAME" "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --force) FORCE=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --pane)
            [ $# -ge 2 ] || die "--pane requires a pane id (e.g. %3)"
            PANE_FILTER="${PANE_FILTER:+$PANE_FILTER
}$2"
            shift
            ;;
        -L)
            [ $# -ge 2 ] || die "-L requires a socket name"
            SOCKET="$2"
            shift
            ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown option: $1" ;;
    esac
    shift
done

# Every tmux call goes through here so -L applies uniformly.
tmux_cmd() {
    if [ -n "$SOCKET" ]; then
        tmux -L "$SOCKET" "$@"
    else
        tmux "$@"
    fi
}

PANE_MODE=0
[ -n "$PANE_FILTER" ] && PANE_MODE=1
if [ "$PANE_MODE" -eq 1 ] && [ "$FORCE" -eq 1 ]; then
    die "--force cannot be combined with --pane (single-pane mode never saves or kills the server)"
fi

tmux_cmd list-sessions >/dev/null 2>&1 \
    || die "no tmux server reachable${SOCKET:+ on socket '$SOCKET'} - nothing to restart"

if [ "$PANE_MODE" -eq 1 ]; then
    ALL_PANES="$(tmux_cmd list-panes -a -F '#{pane_id}')"
    while IFS= read -r wanted; do
        [ -n "$wanted" ] || continue
        grep -qxF "$wanted" <<<"$ALL_PANES" || die "unknown pane id: $wanted"
    done <<<"$PANE_FILTER"
fi

# tmux.conf sets TMUX_PLUGIN_MANAGER_PATH via `set-environment -g` with a
# literal `~/.tmux/plugins/`: tmux never expands the tilde, so the value that
# reaches run-shell (and any outer shell that inherited it) is not a path yet.
# Resolve exactly like TPM: server global env -> process env -> default, then
# expand a leading ~ and drop a trailing slash.
resolve_plugin_path() {
    local raw="" server_env
    server_env="$(tmux_cmd show-environment -g TMUX_PLUGIN_MANAGER_PATH 2>/dev/null || true)"
    case "$server_env" in
        TMUX_PLUGIN_MANAGER_PATH=*) raw="${server_env#TMUX_PLUGIN_MANAGER_PATH=}" ;;
    esac
    [ -n "$raw" ] || raw="${TMUX_PLUGIN_MANAGER_PATH:-}"
    [ -n "$raw" ] || raw="$DEFAULT_PLUGIN_PATH"
    raw="${raw/#\~/$HOME}"
    raw="${raw%/}"
    printf '%s\n' "$raw"
}

PLUGIN_PATH="$(resolve_plugin_path)"
RESURRECT_SAVE="$PLUGIN_PATH/$RESURRECT_SAVE_REL"

# Snapshot of every process: "pid ppid args". One ps call per scan, portable
# to macOS and Linux (no procps-specific pgrep flags).
ps_snapshot() {
    ps -Ao pid=,ppid=,args=
}

# pane_has_claude <pane_pid> <snapshot>: true when the pane's process or any
# descendant matches CLAUDE_ARGS_RE.
pane_has_claude() {
    local root="$1" snapshot="$2"
    printf '%s\n' "$snapshot" | awk -v root="$root" -v re="$CLAUDE_ARGS_RE" '
        {
            pid = $1; ppid = $2
            $1 = ""; $2 = ""
            sub(/^[[:space:]]+/, "")
            args[pid] = $0
            kids[ppid] = kids[ppid] " " pid
        }
        END {
            n = 1; stack[n] = root
            while (n > 0) {
                cur = stack[n]; n--
                if (cur in args && args[cur] ~ re) { found = 1; break }
                split(kids[cur], children, " ")
                for (i in children) if (children[i] != "") { n++; stack[n] = children[i] }
            }
            exit found ? 0 : 1
        }'
}

# Prints "pane_id<TAB>pane_pid<TAB>session:window<TAB>window_name" for every
# pane whose process tree contains claude (restricted to --pane ids if given).
find_claude_panes() {
    local snapshot pane_id pane_pid location window_name
    snapshot="$(ps_snapshot)"
    while IFS=$'\t' read -r pane_id pane_pid location window_name; do
        if [ "$PANE_MODE" -eq 1 ] && ! grep -qxF "$pane_id" <<<"$PANE_FILTER"; then
            continue
        fi
        if pane_has_claude "$pane_pid" "$snapshot"; then
            printf '%s\t%s\t%s\t%s\n' "$pane_id" "$pane_pid" "$location" "$window_name"
        fi
    done < <(tmux_cmd list-panes -a -F $'#{pane_id}\t#{pane_pid}\t#{session_name}:#{window_index}\t#{window_name}')
}

# Claude's vim mode starts in NORMAL; `/exit` must be typed in INSERT mode.
vim_mode_enabled() {
    [ -r "$SETTINGS_FILE" ] || return 1
    if command -v jq >/dev/null 2>&1; then
        jq -e '.vimMode == true' "$SETTINGS_FILE" >/dev/null 2>&1
    else
        grep -Eq '"vimMode"[[:space:]]*:[[:space:]]*true' "$SETTINGS_FILE"
    fi
}

# Type `/exit` and submit it in one pane.
send_exit_command() {
    local pane_id="$1"
    tmux_cmd send-keys -t "$pane_id" -l '/exit'
    sleep "$KEY_PAUSE"
    tmux_cmd send-keys -t "$pane_id" Enter
}

# First attempt for one pane: C-c interrupts a running turn / clears typed
# input, then `/exit` is typed and submitted. Retries (see below) never
# re-send C-c: a second C-c on an empty input is claude's hard-exit path,
# which skips the resume hint we are after.
send_exit() {
    local pane_id="$1"
    tmux_cmd send-keys -t "$pane_id" C-c
    sleep "$KEY_PAUSE"
    if [ "$VIM_MODE" -eq 1 ]; then
        tmux_cmd send-keys -t "$pane_id" Escape i
        sleep "$KEY_PAUSE"
    fi
    send_exit_command "$pane_id"
}

# Given the initial target list, print the lines whose pane still exists and
# still has a claude descendant.
remaining_targets() {
    local targets="$1" snapshot pane_id pane_pid location window_name live_panes
    snapshot="$(ps_snapshot)"
    live_panes="$(tmux_cmd list-panes -a -F '#{pane_id}')"
    while IFS=$'\t' read -r pane_id pane_pid location window_name; do
        [ -n "$pane_id" ] || continue
        grep -qxF "$pane_id" <<<"$live_panes" || continue
        if pane_has_claude "$pane_pid" "$snapshot"; then
            printf '%s\t%s\t%s\t%s\n' "$pane_id" "$pane_pid" "$location" "$window_name"
        fi
    done <<<"$targets"
}

print_targets() {
    local pane_id pane_pid location window_name
    while IFS=$'\t' read -r pane_id pane_pid location window_name; do
        [ -n "$pane_id" ] || continue
        printf '  %s  %s  (%s)\n' "$pane_id" "$location" "$window_name"
    done <<<"$1"
}

TARGETS="$(find_claude_panes)"
TARGET_COUNT=0
[ -n "$TARGETS" ] && TARGET_COUNT="$(printf '%s\n' "$TARGETS" | wc -l | tr -d ' ')"

PANE_LIST="$(printf '%s' "$PANE_FILTER" | tr '\n' ' ')"

if [ "$DRY_RUN" -eq 1 ]; then
    if [ "$TARGET_COUNT" -eq 0 ]; then
        if [ "$PANE_MODE" -eq 1 ]; then
            log "dry-run: no claude running in pane(s) $PANE_LIST- nothing to do"
        else
            log "dry-run: no panes running claude"
        fi
    else
        log "dry-run: would send /exit to $TARGET_COUNT pane(s):"
        print_targets "$TARGETS"
    fi
    if [ "$PANE_MODE" -eq 1 ]; then
        log "dry-run: --pane mode: would neither save the layout nor kill the server"
        exit 0
    fi
    if [ -x "$RESURRECT_SAVE" ]; then
        log "dry-run: would then run $RESURRECT_SAVE and kill the tmux server"
    else
        log "dry-run: tmux-resurrect save.sh NOT found at $RESURRECT_SAVE (real run would abort without --force)"
    fi
    exit 0
fi

if [ "$PANE_MODE" -eq 1 ] && [ "$TARGET_COUNT" -eq 0 ]; then
    warn "no claude running in pane(s) $PANE_LIST- nothing to do"
    exit 0
fi

VIM_MODE=0
vim_mode_enabled && VIM_MODE=1

if [ "$TARGET_COUNT" -gt 0 ]; then
    VIM_NOTE=""
    [ "$VIM_MODE" -eq 1 ] && VIM_NOTE=" (vim mode on: sending Escape+i before /exit)"
    log "exiting claude in $TARGET_COUNT pane(s)$VIM_NOTE"
    while IFS=$'\t' read -r pane_id pane_pid location window_name; do
        [ -n "$pane_id" ] || continue
        send_exit "$pane_id"
    done <<<"$TARGETS"

    START=$SECONDS
    LAST_SEND=$SECONDS
    ATTEMPT=1
    REMAINING="$TARGETS"
    while :; do
        REMAINING="$(remaining_targets "$TARGETS")"
        [ -z "$REMAINING" ] && break
        if [ $((SECONDS - START)) -ge "$TIMEOUT" ]; then
            break
        fi
        if [ $((SECONDS - LAST_SEND)) -ge "$RETRY" ]; then
            ATTEMPT=$((ATTEMPT + 1))
            REMAINING_COUNT="$(printf '%s\n' "$REMAINING" | wc -l | tr -d ' ')"
            log "attempt $ATTEMPT: re-sending /exit to $REMAINING_COUNT pane(s) still running claude"
            while IFS=$'\t' read -r pane_id pane_pid location window_name; do
                [ -n "$pane_id" ] || continue
                send_exit_command "$pane_id"
            done <<<"$REMAINING"
            LAST_SEND=$SECONDS
        fi
        sleep "$POLL"
    done

    if [ -n "$REMAINING" ]; then
        printf '%s: claude still running after %ss in:\n' "$SCRIPT_NAME" "$TIMEOUT" >&2
        print_targets "$REMAINING" >&2
        if [ "$PANE_MODE" -eq 1 ]; then
            die "aborting; exit it manually (server left running)"
        elif [ "$FORCE" -eq 1 ]; then
            warn "--force given: continuing anyway (these panes lose their resume hint)"
        else
            die "aborting; exit them manually or re-run with --force"
        fi
    else
        log "all claude instances exited"
    fi
fi

if [ "$PANE_MODE" -eq 1 ]; then
    EXITED_PANES="$(printf '%s\n' "$TARGETS" | cut -f1 | tr '\n' ' ')"
    log "claude exited in ${EXITED_PANES% }; prefix+R (cres) resumes it"
    exit 0
fi

sleep "$SETTLE"

if [ -x "$RESURRECT_SAVE" ]; then
    # save.sh talks to the server via plain `tmux`, which resolves the socket
    # from \$TMUX (socket_path,server_pid,session_id). Point it at ours so -L
    # sockets and out-of-tmux invocations save the right server.
    SOCKET_PATH="$(tmux_cmd display-message -p '#{socket_path}')"
    SERVER_PID="$(tmux_cmd display-message -p '#{pid}')"
    log "saving layout with tmux-resurrect"
    TMUX="$SOCKET_PATH,$SERVER_PID,0" "$RESURRECT_SAVE" quiet \
        || warn "tmux-resurrect save.sh exited non-zero; continuing"
elif [ "$FORCE" -eq 1 ]; then
    warn "tmux-resurrect save.sh not found at $RESURRECT_SAVE; --force given, killing without saving (layout and resume hints are lost)"
else
    die "tmux-resurrect save.sh not found at $RESURRECT_SAVE; server left running. Check TMUX_PLUGIN_MANAGER_PATH or re-run with --force to kill without saving"
fi

log "killing tmux server"
# Must be the very last statement: when run via run-shell this script is a
# child of the server and dies with it.
tmux_cmd kill-server
