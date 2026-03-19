#!/bin/bash
# Beautiful Apple logo fetch for macOS
# Combines chafa rendering with fastfetch output in side-by-side layout

LOGO_FILE="$HOME/.config/fastfetch/logos/apple.png"
LOGO_WIDTH=25
LOGO_HEIGHT=20

# Generate logo lines with chafa using better rendering options
# - Increased size for smoother appearance
# - Using all available symbols including half blocks and braille
# - Optimized for terminal display
logo_lines=$(chafa --size "${LOGO_WIDTH}x${LOGO_HEIGHT}" \
  --format symbols \
  --symbols all \
  --fill all \
  --clear \
  "$LOGO_FILE" 2>/dev/null)

# Generate fastfetch output without logo
info_lines=$(fastfetch --logo none --pipe false 2>/dev/null)

# Combine side-by-side
paste -d ' ' \
  <(echo "$logo_lines") \
  <(echo "$info_lines") \
  | sed 's/^/  /'
