#!/usr/bin/env bash
set -euo pipefail

# tmux-save-last.sh
# Extract ONLY the last command's output (between last two prompt markers)
# Optionally also tries to capture the last command text without re-running it.
#
# Usage:
#   tmux-save-last.sh [<pane-id>]
#
# Output file:
#   ~/tmux_last_cmd_output.txt
#
# Clipboard:
#   Copies to system clipboard if xclip / wl-copy / pbcopy / clip.exe is available.

PANE="${1:-${TMUX_PANE:-}}"
if [[ -z "${PANE}" ]]; then
  echo "No pane specified and TMUX_PANE not set. Run inside tmux or pass a pane id (e.g. %1)." >&2
  exit 1
fi

OUT_FILE="${HOME}/tmux_last_cmd_output.txt"
MARK="${PROMPT_MARKER:-__PM__}"

# 1) Capture the entire scrollback for the pane, joining wrapped lines (-J)
TMP="$(mktemp)"
tmux capture-pane -J -p -S - -t "$PANE" > "$TMP"

# 2) Find the last two prompt markers: lines exactly like __PM__<epoch>
START_LINE="$(grep -n "^${MARK}[0-9][0-9]*$" "$TMP" | tail -n 2 | head -n 1 | cut -d: -f1 || true)"
END_LINE="$(grep -n "^${MARK}[0-9][0-9]*$" "$TMP" | tail -n 1 | cut -d: -f1 || true)"

if [[ -z "$START_LINE" || -z "$END_LINE" || "$START_LINE" -ge "$END_LINE" ]]; then
  {
    echo "==== Last command ===="
    echo "(unknown – could not locate two prompt markers; did you reload your shell config?)"
    echo
    echo "==== Last output ===="
    echo "(unavailable – markers not found)"
  } > "$OUT_FILE"
else
  # 3) Extract ONLY the lines strictly between the markers (= last command's output)
  awk -v s=$((START_LINE+1)) -v e=$((END_LINE-1)) 'NR>=s && NR<=e' "$TMP" > "$OUT_FILE"
fi

# 4) Best-effort: get the last command text without re-running it.
# We first try via the interactive shell history (fc), but this may be empty in a non-interactive subshell.
LAST_CMD="$(fc -ln -1 2>/dev/null || true)"

# Fallback: naive attempt to derive the command line from just after START_LINE
# (Often the first non-empty line after the marker is the command you typed.)
if [[ -z "${LAST_CMD}" && -n "${START_LINE:-}" && -n "${END_LINE:-}" && "$START_LINE" -lt "$END_LINE" ]]; then
  # Grab the first non-empty line after START_LINE (skip pure marker/prompt blank lines)
  CANDIDATE="$(awk -v s=$((START_LINE+1)) -v e=$((END_LINE-1)) 'NR>=s && NR<=e { if (!seen && length($0)>0) { print; seen=1 } }' "$TMP" || true)"
  # Strip common prompt decorations heuristically (kept simple on purpose)
  LAST_CMD="$(sed -E 's/^[^$#>]*[#$>] *//' <<<"$CANDIDATE" || true)"
fi

# 5) Prepend headers neatly into the OUT_FILE
TMP2="$(mktemp)"
{
  echo "==== Last command ===="
  if [[ -n "$LAST_CMD" ]]; then
    echo "$LAST_CMD"
  else
    echo "(unknown – shell history not available; marker fallback may have failed)"
  fi
  echo
  echo "==== Last output ===="
  cat "$OUT_FILE"
} > "$TMP2"
mv "$TMP2" "$OUT_FILE"

# 6) Copy to clipboard (Linux/X11, Wayland, macOS, WSL)
copied=0
if command -v xclip >/dev/null 2>&1; then
  xclip -selection clipboard < "$OUT_FILE" && copied=1
elif command -v wl-copy >/dev/null 2>&1; then
  wl-copy < "$OUT_FILE" && copied=1
elif command -v pbcopy >/dev/null 2>&1; then
  pbcopy < "$OUT_FILE" && copied=1
elif command -v clip.exe >/dev/null 2>&1; then
  clip.exe < "$OUT_FILE" && copied=1
fi

# 7) Tell tmux what happened
if [[ "$copied" -eq 1 ]]; then
  tmux display-message "Saved & copied last output to clipboard. File: $OUT_FILE"
else
  tmux display-message "Saved last output to $OUT_FILE (install xclip/wl-copy/pbcopy or use WSL clip.exe to copy)."
fi

rm -f "$TMP"

