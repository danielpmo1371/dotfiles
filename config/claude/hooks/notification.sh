#!/usr/bin/env bash
#
# Desktop Notification Hook
# Hooks into: Notification
# Surfaces Claude Code notifications on the desktop (notify-send / osascript)
#
# Input (stdin): JSON with hook_event_name, message, title, notification_type, session_id, cwd
# Output: Exit 0 (always), desktop notification as a side effect
#
# Notifications are best-effort: a missing notifier, an absent notification
# daemon, or malformed input must never fail the hook. `-e` is deliberately
# omitted from `set` for that reason — every path falls through to `exit 0`.
#

set -uo pipefail

# Shown as the notification's application name, and as the title when the
# payload carries neither a title nor a notification type.
readonly APP_NAME="Claude Code"

# Read JSON input from stdin
INPUT=$(cat 2>/dev/null) || INPUT=""

# jq is this repo's standard hook stdin parser; without it there is nothing to show.
command -v jq &> /dev/null || exit 0

# Parse notification fields (empty stdin and malformed JSON both yield empty strings)
MESSAGE=$(printf '%s' "$INPUT" | jq -r '.message // ""' 2>/dev/null) || MESSAGE=""
TITLE=$(printf '%s' "$INPUT" | jq -r '.title // ""' 2>/dev/null) || TITLE=""
NOTIFICATION_TYPE=$(printf '%s' "$INPUT" | jq -r '.notification_type // ""' 2>/dev/null) || NOTIFICATION_TYPE=""

# Nothing worth surfacing
[[ -z "$MESSAGE" ]] && exit 0

# `title` is optional in the payload; fall back to the notification type, then
# to the app name, so the popup always has a heading.
[[ -z "$TITLE" ]] && TITLE="${NOTIFICATION_TYPE:-$APP_NAME}"

# Send the notification via whichever notifier the platform provides.
# Message text is arbitrary (quotes, newlines, unicode) so it is always passed
# as an argument, never interpolated into a command or an AppleScript source.
send_notification() {
  if command -v notify-send &> /dev/null; then
    # `--` stops option parsing so a message starting with `-` is not read as a flag.
    notify-send --app-name="$APP_NAME" -- "$TITLE" "$MESSAGE"
    return
  fi

  # The repo's declared macOS notifier (installers/tools.sh); `-title`/`-message`
  # take the text as separate arguments, so nothing needs quoting.
  if command -v terminal-notifier &> /dev/null; then
    terminal-notifier -title "$TITLE" -message "$MESSAGE"
    return
  fi

  if command -v osascript &> /dev/null; then
    # `-` reads the script from stdin; the trailing words become `argv`.
    osascript - "$TITLE" "$MESSAGE" <<'APPLESCRIPT'
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
APPLESCRIPT
    return
  fi

  # No notifier available: silently no-op.
  return
}

send_notification &> /dev/null || true

# Exit 0 to allow normal flow
exit 0
