#!/usr/bin/env bash
#
# Response Summarizer Hook
# Hooks into: Stop
# Creates ~100 word AI-generated summary of what Claude did/responded
#
# Input (stdin): JSON with hook_event_name, session_id, transcript_path, etc.
# Output: Exit 0 (don't block stop), log to file
#
# Uses Claude Code CLI (-p flag) for AI summarization with haiku model
#

set -euo pipefail

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib-session-dir.sh"

# Configuration
USE_AI_SUMMARY="${CLAUDE_HOOK_AI_SUMMARY:-true}"  # Set to "false" to disable AI summarization
AI_MODEL="haiku"  # Use haiku for fast, cheap summarization

# Read JSON input from stdin
INPUT=$(cat)

# Parse required fields
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
CWD=$(echo "$INPUT" | jq -r '.cwd // "unknown"')

# Get session directory with human-readable name
SESSION_DIR=$(get_session_dir "$SESSION_ID" "$CWD")
LOG_FILE="${SESSION_DIR}/summaries.log"
DEBUG_LOG="${SESSION_DIR}/hook-debug.log"

# Debug: log raw input to see what we receive
echo "=== $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$DEBUG_LOG"
echo "$INPUT" | jq . >> "$DEBUG_LOG" 2>&1 || echo "$INPUT" >> "$DEBUG_LOG"
echo "" >> "$DEBUG_LOG"
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "unknown"')

# Extract project name
PROJECT=$(basename "$CWD")

# Get timestamp
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Initialize summary components
TOOLS_USED=""
FILES_MODIFIED=""
SUMMARY=""
AI_SUMMARY=""

# If transcript exists, extract information
# Transcript is JSONL format (one JSON object per line)
if [[ -n "$TRANSCRIPT_PATH" && -f "$TRANSCRIPT_PATH" ]]; then
  # Extract tool names from assistant messages (tool_use content blocks)
  # Format: {"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Read", ...}]}}
  TOOLS_USED=$(jq -rs '
    [.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | .name]
    | unique | join(", ")
  ' "$TRANSCRIPT_PATH" 2>/dev/null || echo "unknown")

  # Extract files modified (from Write/Edit tool inputs)
  FILES_MODIFIED=$(jq -rs '
    [.[] | select(.type == "assistant") | .message.content[]? |
      select(.type == "tool_use" and (.name == "Write" or .name == "Edit")) |
      .input.file_path // .input.path]
    | unique | .[-5:] | join(", ")
  ' "$TRANSCRIPT_PATH" 2>/dev/null || echo "none")

  # Count tool calls
  TOOL_COUNT=$(jq -rs '
    [.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")]
    | length
  ' "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")

  # Build basic metadata summary
  SUMMARY="Used ${TOOL_COUNT} tool calls."
  if [[ -n "$TOOLS_USED" && "$TOOLS_USED" != "unknown" ]]; then
    SUMMARY="${SUMMARY} Tools: ${TOOLS_USED}."
  fi
  if [[ "$FILES_MODIFIED" != "none" && -n "$FILES_MODIFIED" ]]; then
    SUMMARY="${SUMMARY} Modified: ${FILES_MODIFIED}."
  fi

  # Generate AI summary using Claude Code CLI
  if [[ "$USE_AI_SUMMARY" == "true" ]] && command -v claude &> /dev/null; then
    # Extract recent conversation context (last 20 user/assistant messages, truncated)
    # User messages: .message.content (string or array)
    # Assistant messages: .message.content[].text (for text blocks)
    CONTEXT=$(jq -rs '
      [.[-40:] | .[] |
        select(.type == "user" or .type == "assistant") |
        if .type == "user" then
          "USER: " + (if .message.content | type == "string" then .message.content else (.message.content[0].text // "[tool result]") end)
        else
          "ASSISTANT: " + ([.message.content[]? | select(.type == "text") | .text] | join(" "))
        end
      ] | .[-20:] | map(.[0:500]) | join("\n---\n")
    ' "$TRANSCRIPT_PATH" 2>/dev/null | head -c 4000 || echo "")

    if [[ -n "$CONTEXT" && ${#CONTEXT} -gt 50 ]]; then
      # Use Claude CLI with haiku for fast summarization
      AI_SUMMARY=$(claude -p \
        --model "$AI_MODEL" \
        --tools "" \
        --permission-mode bypassPermissions \
        --no-session-persistence \
        "Summarize this Claude Code session in exactly 100 words. Focus on: what was requested, what actions were taken, what was accomplished. Be specific about files and tools. Output ONLY the summary, no preamble:

$CONTEXT" 2>/dev/null | head -c 800 || echo "")

      if [[ -n "$AI_SUMMARY" ]]; then
        SUMMARY="${SUMMARY} AI Summary: ${AI_SUMMARY}"
      fi
    fi
  fi
else
  SUMMARY="No transcript available for analysis."
fi

# Create log entry as JSON
LOG_ENTRY=$(jq -n \
  --arg ts "$TIMESTAMP" \
  --arg session "$SESSION_ID" \
  --arg project "$PROJECT" \
  --arg cwd "$CWD" \
  --arg tools "$TOOLS_USED" \
  --arg files "$FILES_MODIFIED" \
  --arg summary "$SUMMARY" \
  '{
    timestamp: $ts,
    session_id: $session,
    project: $project,
    cwd: $cwd,
    tools_used: $tools,
    files_modified: $files,
    summary: $summary
  }'
)

# Append to log file
echo "$LOG_ENTRY" >> "$LOG_FILE"

# Exit 0 to allow stop to proceed (don't block)
exit 0
