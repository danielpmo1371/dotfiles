#!/bin/bash
# tmux-tips-timer.sh - Background timer that shows a tips popup every 10 minutes
# Launched automatically by tmux on session creation
# Only one instance runs at a time (PID file lock)

PIDFILE="/tmp/tmux-tips-timer.pid"
INTERVAL=600  # 10 minutes in seconds
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Check if already running
if [[ -f "$PIDFILE" ]]; then
  EXISTING_PID=$(cat "$PIDFILE" 2>/dev/null)
  if [[ -n "$EXISTING_PID" ]] && kill -0 "$EXISTING_PID" 2>/dev/null; then
    exit 0
  fi
fi

# Write PID and set cleanup trap
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

# Wait for initial interval before first tip
sleep "$INTERVAL"

# Loop while tmux is running
while tmux list-sessions &>/dev/null; do
  # Only show if a client is attached (don't popup into nothing)
  if tmux list-clients -F '#{client_name}' 2>/dev/null | grep -q .; then
    "$SCRIPT_DIR/tmux-tips-popup.sh"
  fi
  sleep "$INTERVAL"
done
