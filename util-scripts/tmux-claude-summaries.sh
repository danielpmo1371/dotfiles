#!/usr/bin/env bash
#
# tmux-claude-summaries.sh - show the Claude conversation summaries for the
# current project in a scrollable view
#
# Usage:
#   tmux-claude-summaries.sh   # needs a tty; tmux.conf wraps it in display-popup
#                              # project is inferred from $PWD (popup passes pane cwd via -d)
#
# Keybinding: Cmd+e u (see config/tmux/tmux.conf)
#
# Reads summaries.log written by the response-summarizer Stop hook
# (config/claude/hooks/logging/response-summarizer.sh): JSON entries, one
# metadata entry per Stop plus optional "ai_summary" enrichment entries.
# Picks the newest session dir for the current project that has a
# summaries.log, falling back to the newest across all projects.

set -euo pipefail

SESSIONS_DIR="$HOME/repos/dotfiles/tmp/claude/sessions"
PROJECT="$(basename "$PWD")"

pause_and_exit() {
    echo "$1"
    echo
    read -r -n 1 -s -p "press any key to close"
    exit 0
}

[[ -d "$SESSIONS_DIR" ]] || pause_and_exit "No Claude session logs yet ($SESSIONS_DIR missing)."

# Newest dir that actually has a summaries.log, project-scoped first
find_log() {
    local pattern="$1" dir
    while IFS= read -r dir; do
        if [[ -f "${dir}summaries.log" ]]; then
            echo "${dir}summaries.log"
            return 0
        fi
    done < <(ls -dt "$SESSIONS_DIR"/${pattern}*/ 2>/dev/null)
    return 1
}

LOG_FILE=$(find_log "${PROJECT}_" || find_log "") \
    || pause_and_exit "No summaries.log found in any session under $SESSIONS_DIR."

SESSION_NAME="$(basename "$(dirname "$LOG_FILE")")"

# Render the JSON entry stream as markdown: heading per entry, summary as body
render() {
    jq -r '
        (if .type == "ai_summary"
         then "## \(.timestamp) · AI summary (\(.model))"
         else "## \(.timestamp) · \(.project) — tools: \(.tools_used // "none")"
         end),
        "",
        .summary,
        (if (.files_modified // "") != "" then "\n*modified:* \(.files_modified)" else empty end),
        ""
    ' "$LOG_FILE"
}

if command -v bat >/dev/null 2>&1; then
    render | bat --style=plain --paging=always --language=markdown \
                 --file-name "$SESSION_NAME"
else
    render | less
fi
