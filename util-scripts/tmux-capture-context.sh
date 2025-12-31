#!/bin/bash

# Script to capture the last 80 lines from all tmux panes
# Usage: ./tmux_capture.sh [output_file]

OUTPUT_FILE="${1:-tmux_capture_$(date +%Y%m%d_%H%M%S).txt}"
LINES_TO_CAPTURE=80

# Check if tmux is running
if ! tmux list-sessions &>/dev/null; then
    echo "Error: No tmux sessions found"
    exit 1
fi

# Clear/create output file
> "$OUTPUT_FILE"

echo "Capturing last $LINES_TO_CAPTURE lines from all tmux panes..."
echo ""

# Get all sessions
tmux list-sessions -F '#{session_name}' | while read -r session; do
    echo "========================================" >> "$OUTPUT_FILE"
    echo "SESSION: $session" >> "$OUTPUT_FILE"
    echo "========================================" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"

    # Get all windows in this session
    tmux list-windows -t "$session" -F '#{window_index}:#{window_name}' | while read -r window_info; do
        window_index="${window_info%%:*}"
        window_name="${window_info#*:}"

        echo "  ----------------------------------------" >> "$OUTPUT_FILE"
        echo "  WINDOW $window_index: $window_name" >> "$OUTPUT_FILE"
        echo "  ----------------------------------------" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"

        # Get all panes in this window
        tmux list-panes -t "$session:$window_index" -F '#{pane_index}:#{pane_current_command}:#{pane_pid}' | while read -r pane_info; do
            pane_index="${pane_info%%:*}"
            rest="${pane_info#*:}"
            pane_command="${rest%%:*}"
            pane_pid="${rest#*:}"

            echo "    - - - - - - - - - - - - - - - - - - -" >> "$OUTPUT_FILE"
            echo "    PANE $pane_index (PID: $pane_pid, CMD: $pane_command)" >> "$OUTPUT_FILE"
            echo "    - - - - - - - - - - - - - - - - - - -" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"

            # Capture the last N lines from this pane
            tmux capture-pane -t "$session:$window_index.$pane_index" -p -S -"$LINES_TO_CAPTURE" >> "$OUTPUT_FILE" 2>/dev/null

            echo "" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
        done
    done
done

echo "Output saved to: $OUTPUT_FILE"
echo ""

# Show summary
echo "Summary:"
tmux list-sessions -F '#{session_name}: #{session_windows} window(s)' | while read -r line; do
    echo "  $line"
done

# Display file size
echo ""
echo "File size: $(du -h "$OUTPUT_FILE" | cut -f1)"
