#!/bin/bash
# tmux-claude-fork.sh
# Fork the Claude Code session running in a tmux pane into a new side-by-side pane
#
# Usage:
#   tmux-claude-fork.sh <pane_id> <name>
#
# Bound in tmux.conf to `prefix B` (prompts for <name>). The new pane is split
# to the right of <pane_id>, starts in the origin session's cwd, and gets
#   cdang --resume <sessionId> --fork-session -n <name>
# typed into its interactive shell. `cdang` is a shell alias (aliases.sh), so it
# has to go through send-keys; it also leaves the pane a shell once claude exits.
#
# Session lookup: Claude Code writes $CLAUDE_SESSIONS_DIR/<pid>.json for every
# running process (observed in 2.1.x). This is an INTERNAL, UNDOCUMENTED file
# format and may change without notice. Stale files from crashed processes are
# left behind, so only a LIVE descendant of the pane's shell is accepted. There
# is deliberately no fallback to "newest transcript": once a fork exists, the
# newest transcript is the fork, not the origin.

CLAUDE_SESSIONS_DIR="${CLAUDE_SESSIONS_DIR:-$HOME/.claude/sessions}"
FORK_COMMAND="${CLAUDE_FORK_COMMAND:-cdang}"

# Print the first live pid (breadth-first) among the descendants of $1 that has
# a sessions json. Returns 1 when none is found.
find_claude_session_pid() {
    local root_pid="$1"
    local queue=("$root_pid")
    local pid child

    while [ "${#queue[@]}" -gt 0 ]; do
        pid="${queue[0]}"
        queue=("${queue[@]:1}")
        for child in $(pgrep -P "$pid"); do
            if [ -f "$CLAUDE_SESSIONS_DIR/$child.json" ] && kill -0 "$child" 2>/dev/null; then
                echo "$child"
                return 0
            fi
            queue+=("$child")
        done
    done
    return 1
}

# Print a single field of the sessions json for pid $1.
read_session_field() {
    local pid="$1" field="$2"
    jq -er --arg f "$field" '.[$f] // empty' "$CLAUDE_SESSIONS_DIR/$pid.json"
}

# Single-quote $1 for the pane's interactive shell (zsh or bash). Not bash's
# printf %q: its backslash style leaves e.g. `#` bare mid-word, which zsh with
# EXTENDED_GLOB treats as a glob operator. Inside '...' both shells take every
# character literally (history expansion included); a ' is written as '\''.
quote_for_shell() {
    printf "'%s'" "${1//\'/\'\\\'\'}"
}

# Print the command line typed into the new pane.
build_fork_command() {
    local session_id="$1" name="$2"
    printf '%s --resume %s --fork-session -n %s' \
        "$FORK_COMMAND" "$(quote_for_shell "$session_id")" "$(quote_for_shell "$name")"
}

fail() {
    # -l: literal text, so a pane id like %3 is not taken as a strftime spec.
    tmux display-message -l "claude fork: $1"
    exit 1
}

main() {
    local pane_id="$1" name="$2"
    local pane_pid claude_pid session_id cwd new_pane cmd

    [ -n "$pane_id" ] || fail "usage: tmux-claude-fork.sh <pane_id> <name>"
    [[ "$name" =~ [^[:space:]] ]] || fail "name must not be empty"
    command -v jq >/dev/null 2>&1 || fail "jq not found (needed to read $CLAUDE_SESSIONS_DIR)"

    pane_pid=$(tmux display-message -p -t "$pane_id" '#{pane_pid}') \
        || fail "cannot resolve pane $pane_id"
    claude_pid=$(find_claude_session_pid "$pane_pid") \
        || fail "no running claude session found in pane $pane_id"
    session_id=$(read_session_field "$claude_pid" sessionId) \
        || fail "no sessionId in $CLAUDE_SESSIONS_DIR/$claude_pid.json"
    cwd=$(read_session_field "$claude_pid" cwd) \
        || fail "no cwd in $CLAUDE_SESSIONS_DIR/$claude_pid.json"

    new_pane=$(tmux split-window -h -P -F '#{pane_id}' -t "$pane_id" -c "$cwd") \
        || fail "split-window failed"

    cmd=$(build_fork_command "$session_id" "$name")
    # -l sends the text literally so tmux does not parse key names inside it.
    tmux send-keys -t "$new_pane" -l "$cmd"
    tmux send-keys -t "$new_pane" Enter
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
