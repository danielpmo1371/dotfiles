#!/bin/bash
#
# tmux-claude-relaunch.sh - after tmux-resurrect restores the layout (e.g. after
# a crash or power loss), resume the Claude Code session each pane was running.
#
# Input: the pane registry written by config/claude/hooks/tmux-pane-registry.sh
# (SessionStart/SessionEnd hook): $STATE_DIR/panes/<key>, JSON
# {session_id, cwd, transcript_path, epoch}, key = <session_name>:<window_index>.<pane_index>
# with `%` -> %25 and `/` -> %2F.
#
# A pane is relaunched only when ALL of these hold:
#   0. the recorded transcript exists (a session with no turns has none, and
#      --resume would just error); records without transcript_path, written
#      before the field existed, count as unknown and proceed;
#   1. the pane exists in the restored server;
#   2. the restored resurrect snapshot (`last`) shows `claude` running there;
#   3. the pane reaches an idle shell (zsh|bash|sh|fish) and stays there;
#   4. the pane's current path equals the recorded cwd.
# Then `<cmd> --resume '<session_id>'` + Enter is typed into it. <cmd> is
# typed (send-keys) rather than exec'd because the default, `cdang`, is a shell
# alias (config/shell/aliases.sh).
#
# Record removal policy:
#   relaunched       -> removed (the resumed session re-registers via SessionStart)
#   pane missing     -> removed (the layout no longer has that pane)
#   no transcript, not claude in snapshot, cwd mismatch, invalid record -> removed (stale)
#   pane never became an idle shell (timeout) -> KEPT, so a later run can retry
#   no snapshot / tmux unreachable -> nothing touched
#
# Panes are processed in parallel, so the total wait is one timeout, not N.
# Every decision goes to $STATE_DIR/relaunch.log; one display-message summary.
#
# tmux server: plain `tmux`, i.e. the server named by $TMUX. That is set when
# run from a resurrect hook (tmux run-shell); tests point $TMUX at a private
# `tmux -L` server. No separate override mechanism.
#
# Tunables (tmux options):
#   @claude-relaunch          on|off    (default on; off = log and exit)
#   @claude-relaunch-cmd      command   (default cdang)
#   @claude-relaunch-timeout  seconds   (default 30) to wait for an idle shell
#
# Environment (tests): CLAUDE_TMUX_STATE_DIR, RESURRECT_DIR.
#
# Usage: tmux-claude-relaunch.sh   (backgrounded from @resurrect-hook-post-restore-all)

set -euo pipefail

readonly DEFAULT_ENABLED="on"
readonly DEFAULT_CMD="cdang"
readonly DEFAULT_TIMEOUT=30
readonly POLL_INTERVAL=0.5
# Consecutive polls the pane must show a shell, so a shell that is about to
# exec something else (or a login still sourcing its rc) is not mistaken for idle.
readonly SHELL_STABLE_POLLS=2
readonly SHELL_RE='^(zsh|bash|sh|fish)$'
# Session ids are UUIDs; anything else in a record is refused before send-keys.
readonly SESSION_ID_RE='^[0-9a-fA-F-]+$'

# Per-pane outcome, used as the worker subshell's exit status.
readonly OUTCOME_RELAUNCHED=0
readonly OUTCOME_REMOVED=10
readonly OUTCOME_KEPT=11

STATE_DIR="${CLAUDE_TMUX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-tmux}"
readonly PANES_DIR="$STATE_DIR/panes"
readonly LOG_FILE="$STATE_DIR/relaunch.log"

log() {
    printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE"
}

# Twin of encode_key in config/claude/hooks/tmux-pane-registry.sh.
decode_key() {
    local key="${1//%2F//}"
    printf '%s' "${key//%25/%}"
}

tmux_option() {
    local value
    value=$(tmux show-options -gqv "$1" 2>/dev/null) || value=""
    printf '%s' "${value:-$2}"
}

# Same resolution as tmux-resurrect's helpers.sh: @resurrect-dir (with ~,
# $HOME and $HOSTNAME expanded), else ~/.tmux/resurrect if it exists, else XDG.
resolve_resurrect_dir() {
    local default dir
    if [ -n "${RESURRECT_DIR:-}" ]; then
        printf '%s' "$RESURRECT_DIR"
        return
    fi
    if [ -d "$HOME/.tmux/resurrect" ]; then
        default="$HOME/.tmux/resurrect"
    else
        default="${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"
    fi
    dir=$(tmux_option @resurrect-dir "$default")
    dir="${dir//\$HOME/$HOME}"
    dir="${dir//\$HOSTNAME/$(hostname)}"
    printf '%s' "${dir//\~/$HOME}"
}

# Print pane_current_command recorded in snapshot $1 for session $2, window $3,
# pane $4. Pane lines are tab-separated: pane, session, window_index,
# window_active, :flags, pane_index, title, :cwd, pane_active, command, :full.
snapshot_command() {
    awk -F'\t' -v s="$2" -v w="$3" -v p="$4" \
        '$1 == "pane" && $2 == s && $3 == w && $6 == p { print $10; exit }' "$1"
}

# True when a pane with key $1 exists. `display-message -t` is no use here: for
# a missing pane it falls back to another pane (or prints nothing) and exits 0.
pane_exists() {
    tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null \
        | grep -Fxq -- "$1"
}

pane_format() {
    tmux display-message -p -t "$1" "$2" 2>/dev/null
}

# Poll until pane $1 shows a shell for SHELL_STABLE_POLLS consecutive polls.
# Returns 1 after $2 seconds.
wait_for_idle_shell() {
    local target="$1" timeout="$2"
    local max_polls stable=0 i command
    max_polls=$(awk -v t="$timeout" -v p="$POLL_INTERVAL" 'BEGIN { printf "%d", t / p }')
    for ((i = 0; i < max_polls; i++)); do
        command=$(pane_format "$target" '#{pane_current_command}') || return 1
        if [[ "$command" =~ $SHELL_RE ]]; then
            stable=$((stable + 1))
            [ "$stable" -ge "$SHELL_STABLE_POLLS" ] && return 0
        else
            stable=0
        fi
        sleep "$POLL_INTERVAL"
    done
    return 1
}

# Decide and act on one record. Exits with an OUTCOME_* status.
process_record() {
    local record="$1" snapshot="$2" cmd="$3" timeout="$4"
    local key target session window pane session_id cwd transcript snap_cmd pane_path
    # Appended to every log line once the record is parsed: the log is the
    # manual-resume reference for sessions that could not be relaunched.
    local record_ref=""

    key=$(decode_key "$(basename "$record")")
    session="${key%:*}"
    window="${key##*:}"; window="${window%.*}"
    pane="${key##*.}"
    # `=` makes tmux match the session name exactly instead of by prefix.
    target="=$key"

    drop() {
        log "$key: skipped, record removed — $1$record_ref"
        rm -f "$record"
        exit "$OUTCOME_REMOVED"
    }

    session_id=$(jq -r '.session_id // "" | strings' "$record" 2>/dev/null) || session_id=""
    cwd=$(jq -r '.cwd // "" | strings' "$record" 2>/dev/null) || cwd=""
    [[ "$session_id" =~ $SESSION_ID_RE ]] || drop "invalid session_id in record"
    [ -n "$cwd" ] || drop "no cwd in record (session $session_id)"
    record_ref=" (session $session_id, cwd $cwd)"

    transcript=$(jq -r '.transcript_path // "" | strings' "$record" 2>/dev/null) || transcript=""
    if [ -n "$transcript" ] && [ ! -f "$transcript" ]; then
        drop "no transcript at $transcript — session had no turns"
    fi

    pane_exists "$key" || drop "pane does not exist"

    snap_cmd=$(snapshot_command "$snapshot" "$session" "$window" "$pane")
    [ "$snap_cmd" = "claude" ] \
        || drop "snapshot shows '${snap_cmd:-<no pane>}', not claude"

    if ! wait_for_idle_shell "$target" "$timeout"; then
        log "$key: skipped, record kept — no idle shell within ${timeout}s$record_ref"
        exit "$OUTCOME_KEPT"
    fi

    pane_path=$(pane_format "$target" '#{pane_current_path}') || pane_path=""
    [ "$pane_path" = "$cwd" ] \
        || drop "pane cwd '$pane_path' != recorded"

    # -l sends the text literally so tmux does not parse key names inside it.
    # session_id is validated above, so single quotes are enough.
    tmux send-keys -t "$target" -l "$cmd --resume '$session_id'"
    tmux send-keys -t "$target" Enter
    rm -f "$record"
    log "$key: relaunched — $cmd --resume $session_id$record_ref"
    exit "$OUTCOME_RELAUNCHED"
}

main() {
    local enabled cmd timeout snapshot record pid status skipped
    local relaunched=0 removed=0 kept=0 failed=0
    local -a pids=()

    [ -d "$PANES_DIR" ] || exit 0

    enabled=$(tmux_option @claude-relaunch "$DEFAULT_ENABLED")
    if [ "$enabled" != "on" ]; then
        log "disabled (@claude-relaunch=$enabled), nothing done"
        exit 0
    fi
    # Without a reachable server every pane would look missing and every record
    # would be dropped; bail out before touching anything.
    if ! tmux display-message -p '#{pid}' > /dev/null 2>&1; then
        log "tmux server unreachable (TMUX=${TMUX:-<unset>}), nothing done"
        exit 0
    fi
    command -v jq > /dev/null 2>&1 || { log "jq not found, nothing done"; exit 0; }

    cmd=$(tmux_option @claude-relaunch-cmd "$DEFAULT_CMD")
    timeout=$(tmux_option @claude-relaunch-timeout "$DEFAULT_TIMEOUT")
    if ! [[ "$timeout" =~ ^[0-9]+$ ]]; then
        log "invalid @claude-relaunch-timeout '$timeout', using $DEFAULT_TIMEOUT"
        timeout="$DEFAULT_TIMEOUT"
    fi

    snapshot="$(resolve_resurrect_dir)/last"
    if [ ! -r "$snapshot" ]; then
        log "no resurrect snapshot at $snapshot, nothing done"
        exit 0
    fi

    log "run: snapshot $(readlink -f "$snapshot"), cmd '$cmd', timeout ${timeout}s"
    shopt -s nullglob
    for record in "$PANES_DIR"/*; do
        [ -f "$record" ] || continue
        ( process_record "$record" "$snapshot" "$cmd" "$timeout" ) &
        pids+=("$!")
    done

    for pid in "${pids[@]}"; do
        status=0
        wait "$pid" || status=$?
        case "$status" in
            "$OUTCOME_RELAUNCHED") relaunched=$((relaunched + 1)) ;;
            "$OUTCOME_REMOVED") removed=$((removed + 1)) ;;
            "$OUTCOME_KEPT") kept=$((kept + 1)) ;;
            *) failed=$((failed + 1)); log "worker $pid failed with status $status" ;;
        esac
    done
    skipped=$((removed + kept + failed))

    log "done: $relaunched relaunched, $skipped skipped ($removed removed, $kept kept, $failed failed)"
    # No attached client (e.g. tests) makes display-message fail; not an error.
    tmux display-message -l \
        "claude-relaunch: $relaunched relaunched, $skipped skipped — see $LOG_FILE" \
        2>/dev/null || true
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
