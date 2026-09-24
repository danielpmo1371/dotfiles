#!/bin/bash
# tmux-battery.sh - Print battery status for the tmux status-right segment.
# Cross-platform: Linux (sysfs, no acpi/upower dependency) + macOS (pmset).
# Prints nothing on machines with no battery (desktops/VMs), so the segment
# just disappears from the status bar instead of showing garbage.

if [[ "$(uname)" == "Darwin" ]]; then
  batt_line=$(pmset -g batt 2>/dev/null | grep -o '[0-9]\+%.*charging')
  percentage=$(echo "$batt_line" | grep -o '^[0-9]\+')
  [[ -z "$percentage" ]] && exit 0

  if echo "$batt_line" | grep -q "^[0-9]\+%; charging"; then
    icon="⚡"
  else
    icon="🔋"
  fi
else
  battery_dir=$(find /sys/class/power_supply -maxdepth 1 -iname 'BAT*' 2>/dev/null | head -n1)
  [[ -z "$battery_dir" ]] && exit 0

  percentage=$(cat "$battery_dir/capacity" 2>/dev/null)
  status=$(cat "$battery_dir/status" 2>/dev/null)
  [[ -z "$percentage" ]] && exit 0

  if [[ "$status" == "Charging" || "$status" == "Full" ]]; then
    icon="⚡"
  else
    icon="🔋"
  fi
fi

echo "${icon}${percentage}%"
