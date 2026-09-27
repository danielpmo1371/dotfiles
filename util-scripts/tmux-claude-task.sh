#!/bin/bash
#
# tmux-claude-task.sh - open a Claude Code session in a new tmux window with a
# prepared task prompt. Built for scheduled follow-ups (systemd user timers):
# the task shows up as a normal interactive session you can read and continue.
#
# Usage: tmux-claude-task.sh <tmux-session> <window-name> <working-dir> <prompt-file>
#
# The session is created (detached) if it doesn't exist. Claude starts inside
# `zsh -lic` so ~/.zshrc runs and secrets are exported (timers start with a
# bare environment), and via $TMUX_CLAUDE_TASK_CMD (default `cdang`, a shell
# alias from config/shell/aliases.sh) so it matches interactive use. The prompt
# is passed by file path in the window's environment, never re-quoted.
#
# Every launch is logged to ${XDG_STATE_HOME:-~/.local/state}/claude-tasks/tasks.log.

set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-tasks"
LOG_FILE="$STATE_DIR/tasks.log"
TASK_CMD="${TMUX_CLAUDE_TASK_CMD:-cdang}"

log() {
    mkdir -p "$STATE_DIR"
    printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE"
}

if [[ $# -ne 4 ]]; then
    echo "usage: $(basename "$0") <tmux-session> <window-name> <working-dir> <prompt-file>" >&2
    exit 2
fi

session=$1 window=$2 workdir=$3 prompt_file=$4

if [[ ! -d "$workdir" ]]; then
    log "FAIL $session:$window - working dir missing: $workdir"
    exit 1
fi
if [[ ! -s "$prompt_file" ]]; then
    log "FAIL $session:$window - prompt file missing or empty: $prompt_file"
    exit 1
fi

if ! tmux has-session -t "=$session" 2>/dev/null; then
    tmux new-session -d -s "$session" -c "$workdir"
    log "created tmux session $session"
fi

# Single quotes are deliberate: $TASK_PROMPT_FILE is expanded by the window's
# zsh, not here, so the prompt text never passes through this script's quoting.
# shellcheck disable=SC2016
tmux new-window -t "=$session:" -n "$window" -c "$workdir" \
    -e "TASK_PROMPT_FILE=$prompt_file" \
    "zsh -lic '$TASK_CMD \"\$(cat \"\$TASK_PROMPT_FILE\")\"'"

log "launched $session:$window in $workdir with $prompt_file"
