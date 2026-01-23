#!/usr/bin/env bash
#
# Session Goal Tracker Hook
# Hooks into: SessionStart, UserPromptSubmit
# Tracks the session goal and logs how it evolves
#
# Input (stdin): JSON with hook_event_name, session_id, prompt (for UserPromptSubmit), etc.
# Output: Exit 0, log to file
#

set -euo pipefail

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib-session-dir.sh"

# Read JSON input from stdin
INPUT=$(cat)

# Parse required fields
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
CWD=$(echo "$INPUT" | jq -r '.cwd // "unknown"')

# Get session directory with human-readable name
SESSION_DIR=$(get_session_dir "$SESSION_ID" "$CWD")
GOALS_FILE="${SESSION_DIR}/goals.log"
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "unknown"')

# Extract project name
PROJECT=$(basename "$CWD")

# Get timestamp
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Session state file (tracks current session's goal)
SESSION_STATE_FILE="${SESSION_DIR}/state.json"

handle_session_start() {
  local source
  source=$(echo "$INPUT" | jq -r '.source // "startup"')

  # Initialize session state
  jq -n \
    --arg session "$SESSION_ID" \
    --arg project "$PROJECT" \
    --arg cwd "$CWD" \
    --arg ts "$TIMESTAMP" \
    --arg source "$source" \
    '{
      session_id: $session,
      project: $project,
      cwd: $cwd,
      started_at: $ts,
      source: $source,
      initial_goal: null,
      current_goal: null,
      goal_history: [],
      prompt_count: 0
    }' > "$SESSION_STATE_FILE"

  # Log session start
  local log_entry
  log_entry=$(jq -n \
    --arg ts "$TIMESTAMP" \
    --arg session "$SESSION_ID" \
    --arg project "$PROJECT" \
    --arg event "session_started" \
    --arg source "$source" \
    '{
      timestamp: $ts,
      session_id: $session,
      project: $project,
      event: $event,
      source: $source
    }'
  )
  echo "$log_entry" >> "$GOALS_FILE"
}

handle_user_prompt() {
  local prompt
  prompt=$(echo "$INPUT" | jq -r '.prompt // ""')

  # Skip if no prompt
  [[ -z "$prompt" ]] && return 0

  # Load or create session state
  if [[ ! -f "$SESSION_STATE_FILE" ]]; then
    # Session state doesn't exist, create it
    handle_session_start
  fi

  # Read current state
  local state
  state=$(cat "$SESSION_STATE_FILE")

  local prompt_count
  prompt_count=$(echo "$state" | jq -r '.prompt_count // 0')
  prompt_count=$((prompt_count + 1))

  # Extract first 200 chars of prompt as goal summary
  local goal_summary
  goal_summary=$(echo "$prompt" | head -c 200 | tr '\n' ' ' | sed 's/  */ /g')

  # Detect if this is a goal-changing prompt
  local is_goal_change=false
  local current_goal
  current_goal=$(echo "$state" | jq -r '.current_goal // ""')

  # Use AI to detect goal changes (optional, controlled by env var)
  USE_AI_GOAL_DETECTION="${CLAUDE_HOOK_AI_GOALS:-false}"

  if [[ $prompt_count -eq 1 ]]; then
    # First prompt is always the initial goal
    is_goal_change=true
  elif [[ "$USE_AI_GOAL_DETECTION" == "true" ]] && command -v claude &> /dev/null && [[ -n "$current_goal" ]]; then
    # Use AI to detect if this is a significant goal change
    AI_DECISION=$(claude -p \
      --model haiku \
      --tools "" \
      --permission-mode bypassPermissions \
      --no-session-persistence \
      "Current goal: $current_goal

New prompt: $goal_summary

Is this a SIGNIFICANT change in direction/goal? Answer only 'yes' or 'no'." 2>/dev/null | tr '[:upper:]' '[:lower:]' | grep -oE '(yes|no)' | head -1 || echo "no")

    if [[ "$AI_DECISION" == "yes" ]]; then
      is_goal_change=true
    fi
  else
    # Fallback to heuristics
    if echo "$prompt" | grep -qiE '^(now |instead |let.s |change |switch |forget |new task|actually )'; then
      # Detected goal-changing language
      is_goal_change=true
    elif [[ ${#prompt} -gt 200 && $prompt_count -gt 1 ]]; then
      # Very long prompt might indicate a new direction
      is_goal_change=true
    fi
  fi

  # Update state
  if $is_goal_change; then
    # Add current goal to history if it exists
    if [[ -n "$current_goal" ]]; then
      state=$(echo "$state" | jq \
        --arg ts "$TIMESTAMP" \
        --arg goal "$current_goal" \
        '.goal_history += [{timestamp: $ts, goal: $goal}]'
      )
    fi

    # Set new goal
    state=$(echo "$state" | jq \
      --arg goal "$goal_summary" \
      --argjson count "$prompt_count" \
      '.current_goal = $goal | .prompt_count = $count'
    )

    # Set initial goal if first prompt
    if [[ $prompt_count -eq 1 ]]; then
      state=$(echo "$state" | jq \
        --arg goal "$goal_summary" \
        '.initial_goal = $goal'
      )
    fi

    # Log goal change
    local log_entry
    log_entry=$(jq -n \
      --arg ts "$TIMESTAMP" \
      --arg session "$SESSION_ID" \
      --arg project "$PROJECT" \
      --arg event "goal_updated" \
      --arg goal "$goal_summary" \
      --argjson prompt_num "$prompt_count" \
      '{
        timestamp: $ts,
        session_id: $session,
        project: $project,
        event: $event,
        prompt_number: $prompt_num,
        new_goal: $goal
      }'
    )
    echo "$log_entry" >> "$GOALS_FILE"
  else
    # Just increment prompt count
    state=$(echo "$state" | jq --argjson count "$prompt_count" '.prompt_count = $count')
  fi

  # Save updated state
  echo "$state" > "$SESSION_STATE_FILE"
}

handle_session_end() {
  local reason
  reason=$(echo "$INPUT" | jq -r '.reason // "unknown"')

  # Load session state if exists
  if [[ -f "$SESSION_STATE_FILE" ]]; then
    local state
    state=$(cat "$SESSION_STATE_FILE")

    local initial_goal current_goal prompt_count goal_history_count
    initial_goal=$(echo "$state" | jq -r '.initial_goal // "none"')
    current_goal=$(echo "$state" | jq -r '.current_goal // "none"')
    prompt_count=$(echo "$state" | jq -r '.prompt_count // 0')
    goal_history_count=$(echo "$state" | jq '.goal_history | length')

    # Log session end with summary
    local log_entry
    log_entry=$(jq -n \
      --arg ts "$TIMESTAMP" \
      --arg session "$SESSION_ID" \
      --arg project "$PROJECT" \
      --arg event "session_ended" \
      --arg reason "$reason" \
      --arg initial_goal "$initial_goal" \
      --arg final_goal "$current_goal" \
      --argjson prompt_count "$prompt_count" \
      --argjson goal_changes "$goal_history_count" \
      '{
        timestamp: $ts,
        session_id: $session,
        project: $project,
        event: $event,
        reason: $reason,
        initial_goal: $initial_goal,
        final_goal: $final_goal,
        total_prompts: $prompt_count,
        goal_changes: $goal_changes
      }'
    )
    echo "$log_entry" >> "$GOALS_FILE"

    # Clean up session state file
    rm -f "$SESSION_STATE_FILE"
  fi
}

# Route to appropriate handler based on hook event
case "$HOOK_EVENT" in
  SessionStart)
    handle_session_start
    ;;
  UserPromptSubmit)
    handle_user_prompt
    ;;
  SessionEnd)
    handle_session_end
    ;;
  *)
    # Unknown event, ignore
    ;;
esac

# Exit 0 to allow normal flow
exit 0
