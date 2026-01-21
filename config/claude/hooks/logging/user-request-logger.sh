#!/usr/bin/env bash
#
# User Request Logger Hook
# Hooks into: UserPromptSubmit
# Logs all user requests with session, folder, project, and timestamp info
#
# Input (stdin): JSON with hook_event_name, prompt, session_id, cwd, etc.
# Output: Exit 0 (allow prompt), log to file
#

set -euo pipefail

# Configuration
BASE_LOG_DIR="${HOME}/repos/dotfiles/tmp/claude/sessions"

# Read JSON input from stdin
INPUT=$(cat)

# Parse session ID first to create session-specific directory
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')

# Create session-specific directory
SESSION_DIR="${BASE_LOG_DIR}/${SESSION_ID}"
mkdir -p "$SESSION_DIR"

LOG_FILE="${SESSION_DIR}/requests.log"
CWD=$(echo "$INPUT" | jq -r '.cwd // "unknown"')
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""')
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "unknown"')

# Extract project name from cwd (last directory component)
PROJECT=$(basename "$CWD")

# Get timestamp
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
DATE_ONLY=$(date '+%Y-%m-%d')

# Truncate prompt for log (first 500 chars, escape newlines)
PROMPT_TRUNCATED=$(echo "$PROMPT" | head -c 500 | tr '\n' ' ' | sed 's/  */ /g')

# Create log entry as JSON for easy parsing later
LOG_ENTRY=$(jq -n \
  --arg ts "$TIMESTAMP" \
  --arg date "$DATE_ONLY" \
  --arg session "$SESSION_ID" \
  --arg project "$PROJECT" \
  --arg cwd "$CWD" \
  --arg prompt "$PROMPT_TRUNCATED" \
  --arg prompt_length "${#PROMPT}" \
  '{
    timestamp: $ts,
    date: $date,
    session_id: $session,
    project: $project,
    cwd: $cwd,
    prompt_preview: $prompt,
    prompt_length: ($prompt_length | tonumber)
  }'
)

# Append to log file
echo "$LOG_ENTRY" >> "$LOG_FILE"

# Exit 0 to allow the prompt to proceed
exit 0
