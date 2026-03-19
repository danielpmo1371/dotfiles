#!/bin/bash
# Fastfetch with custom Apple logo
# The trick: use the raw logo type which bypasses auto-detection

# Direct chafa rendering
chafa --size 20x20 --format symbols "$HOME/.config/fastfetch/logos/apple.png"
echo ""
fastfetch --logo none "$@"
