#!/usr/bin/env bash
#
# tmux Pane Registry Hook
# Hooks into: SessionStart, SessionEnd
# Records which Claude Code session runs in which tmux pane, so that
# util-scripts/tmux-claude-relaunch.sh can resume it after a crash / power loss
# once tmux-resurrect has restored the layout.
#
# Input (stdin): JSON with hook_event_name, session_id, cwd, transcript_path, and source
#                (SessionStart) or reason (SessionEnd)
# Output: Exit 0 (always), nothing on stdout. SessionStart stdout is injected
#         into Claude's context, so every command's stdout is discarded.
#
# Record: $STATE_DIR/panes/<key>, a JSON object
#   {session_id, cwd, transcript_path, epoch}.
#   <key> = <session_name>:<window_index>.<pane_index> — the pane's position,
#   which tmux-resurrect preserves (pane ids like %3 are not preserved).
#   Written atomically (mktemp in the same dir + mv).
#   Removed on a deliberate exit (SessionEnd reason prompt_input_exit or
#   logout), and only when it still holds this session's id, so a newer session
#   in the same pane keeps its record. Any other reason (a crash, a signal,
#   /clear, resume) keeps it: that is exactly what the relaunch is for.
#
# Nested sessions: a headless `claude -p` started from inside a pane (Claude's
# Bash tool, scripts) inherits $TMUX_PANE, and its SessionStart would overwrite
# the pane's record with the headless id. SessionStart is therefore recorded
# only when exactly ONE process named claude sits between this hook and the
# pane's shell (#{pane_pid}). SessionEnd needs no such guard: removal already
# requires the recorded id to match.
#
# The registry is best-effort: outside tmux, without jq, or on any error the
# hook silently does nothing. `-e` is deliberately omitted from `set` for that
# reason — every path falls through to `exit 0`.
#

set -uo pipefail

STATE_DIR="${CLAUDE_TMUX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-tmux}"
readonly PANES_DIR="$STATE_DIR/panes"
readonly CLAUDE_PROCESS_NAME="claude"
# Upper bound on the ancestry walk; a pane's claude is a few levels up at most.
readonly MAX_ANCESTRY_DEPTH=32

# Make a pane key usable as a file name. tmux already replaces `:` and `.` in
# session names, but `/` is allowed, so percent-encode it (and `%` itself first,
# so decoding is unambiguous). Twin: encode_key in util-scripts/tmux-claude-relaunch.sh.
encode_key() {
    local key="${1//%/%25}"
    printf '%s' "${key//\//%2F}"
}

# Print field $1 of the hook payload, or nothing when absent / malformed.
payload_field() {
    printf '%s' "$INPUT" | jq -r --arg f "$1" '.[$f] // "" | strings' 2>/dev/null
}

# True when walking up from this hook's parent reaches pane shell pid $1 having
# passed exactly one claude process. `ps -o comm=` is basenamed because macOS
# may print the full path.
started_by_pane_claude() {
    local pane_pid="$1" pid="$PPID" ppid comm depth claudes=0
    for ((depth = 0; depth < MAX_ANCESTRY_DEPTH; depth++)); do
        if [ "$pid" = "$pane_pid" ]; then
            [ "$claudes" -eq 1 ]
            return
        fi
        read -r ppid comm < <(ps -o ppid=,comm= -p "$pid" 2>/dev/null) || return 1
        [ "${comm##*/}" = "$CLAUDE_PROCESS_NAME" ] && claudes=$((claudes + 1))
        [ -n "$ppid" ] && [ "$ppid" -gt 1 ] || return 1
        pid="$ppid"
    done
    return 1
}

# Write the record for this pane, replacing any previous one.
write_record() {
    local record="$1" tmp
    mkdir -p "$PANES_DIR" || return
    tmp=$(mktemp "$PANES_DIR/.record.XXXXXX") || return
    if jq -n --arg id "$SESSION_ID" --arg cwd "$CWD" --arg transcript "$TRANSCRIPT_PATH" \
        --argjson epoch "$(date +%s)" \
        '{session_id: $id, cwd: $cwd, transcript_path: $transcript, epoch: $epoch}' > "$tmp"; then
        mv -f "$tmp" "$record"
    else
        rm -f "$tmp"
    fi
}

# Remove the record for this pane if it still belongs to this session.
remove_record() {
    local record="$1" recorded_id
    [ -f "$record" ] || return
    recorded_id=$(jq -r '.session_id // ""' "$record" 2>/dev/null)
    [ "$recorded_id" = "$SESSION_ID" ] && rm -f "$record"
}

main() {
    local resolved pane_id pane_pid key record reason

    # Drain stdin first so the writer never sees a broken pipe on an early return.
    INPUT=$(cat 2>/dev/null) || INPUT=""

    [ -n "${TMUX_PANE:-}" ] || return
    command -v tmux &> /dev/null || return
    command -v jq &> /dev/null || return

    SESSION_ID=$(payload_field session_id)
    CWD=$(payload_field cwd)
    TRANSCRIPT_PATH=$(payload_field transcript_path)
    [ -n "$SESSION_ID" ] || return

    # For a pane id that no longer exists, display-message falls back to another
    # pane and still exits 0, so the pane id is echoed back and checked.
    resolved=$(tmux display-message -p -t "$TMUX_PANE" \
        '#{pane_id} #{pane_pid} #{session_name}:#{window_index}.#{pane_index}' 2>/dev/null) \
        || return
    # Split by hand, not with read: that would trim spaces a session name may carry.
    pane_id="${resolved%% *}"
    resolved="${resolved#* }"
    pane_pid="${resolved%% *}"
    key="${resolved#* }"
    [ "$pane_id" = "$TMUX_PANE" ] || return
    record="$PANES_DIR/$(encode_key "$key")"

    case "$(payload_field hook_event_name)" in
        SessionStart)
            started_by_pane_claude "$pane_pid" && write_record "$record"
            ;;
        SessionEnd)
            reason=$(payload_field reason)
            case "$reason" in
                prompt_input_exit|logout) remove_record "$record" ;;
            esac
            ;;
    esac
}

main > /dev/null

# Exit 0 to allow normal flow
exit 0
