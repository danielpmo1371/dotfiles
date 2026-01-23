#!/usr/bin/env bash
#
# Shared library for session directory management
# Creates human-readable folder names: {project}_{date}_{time}_{short-id}
# Maintains a mapping file so all hooks find the same folder
#

# Get or create session directory with human-readable name
# Usage: SESSION_DIR=$(get_session_dir "$SESSION_ID" "$CWD")
get_session_dir() {
  local session_id="$1"
  local cwd="$2"
  local base_dir="${HOME}/repos/dotfiles/tmp/claude/sessions"
  local mapping_file="${base_dir}/.session-map"

  # Ensure base directory exists
  mkdir -p "$base_dir"

  # Check if we already have a mapping for this session
  if [[ -f "$mapping_file" ]]; then
    local existing_dir
    existing_dir=$(grep "^${session_id}=" "$mapping_file" 2>/dev/null | head -1 | cut -d'=' -f2)
    if [[ -n "$existing_dir" && -d "${base_dir}/${existing_dir}" ]]; then
      echo "${base_dir}/${existing_dir}"
      return 0
    fi
  fi

  # Create new friendly folder name
  local project
  project=$(basename "$cwd")
  local date_part
  date_part=$(date '+%Y-%m-%d')
  local time_part
  time_part=$(date '+%H-%M-%S')
  local short_id
  short_id=$(echo "$session_id" | cut -c1-8)

  local friendly_name="${project}_${date_part}_${time_part}_${short_id}"
  local session_dir="${base_dir}/${friendly_name}"

  # Create directory
  mkdir -p "$session_dir"

  # Store mapping (append)
  echo "${session_id}=${friendly_name}" >> "$mapping_file"

  # Also store session_id in the folder for reverse lookup
  echo "$session_id" > "${session_dir}/.session-id"

  echo "$session_dir"
}
