#!/bin/bash
# Beautiful Apple logo fetch for macOS
# Combines chafa rendering with fastfetch output in side-by-side layout

LOGO_FILE="$HOME/.config/fastfetch/logos/apple.png"
LOGO_WIDTH=18
LOGO_HEIGHT=18

# Generate logo lines with chafa
logo_lines=$(chafa --size "${LOGO_WIDTH}x${LOGO_HEIGHT}" --format symbols "$LOGO_FILE" 2>/dev/null)

# Generate fastfetch output without logo
info_lines=$(fastfetch --logo none --pipe false 2>/dev/null)

# Combine side-by-side
paste -d ' ' \
  <(echo "$logo_lines") \
  <(echo "$info_lines") \
  | sed 's/^/  /'
