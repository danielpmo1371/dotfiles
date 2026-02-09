#!/bin/bash

# Dialog wrapper functions for interactive installer
# Provides consistent styling and simplified API

DIALOG_HEIGHT=20
DIALOG_WIDTH=70
DIALOG_MENU_HEIGHT=12
DIALOG_BACKTITLE="Dotfiles Installer"

# Display welcome menu
# Returns: selected option (install, configure, help, exit)
dialog_welcome() {
    dialog --clear --backtitle "$DIALOG_BACKTITLE" \
        --title "Welcome" \
        --menu "Choose an option:" $DIALOG_HEIGHT $DIALOG_WIDTH 4 \
        "install"   "Install components" \
        "configure" "Change settings" \
        "help"      "Show help" \
        "exit"      "Exit installer" \
        2>&1 >/dev/tty
}

# Multi-select checklist
# Usage: dialog_checklist "title" "item1:desc1:on" "item2:desc2:off" ...
# Returns: space-separated list of selected items
dialog_checklist() {
    local title="$1"; shift
    local items=()

    for item in "$@"; do
        IFS=':' read -r tag desc status <<< "$item"
        items+=("$tag" "$desc" "$status")
    done

    dialog --clear --backtitle "$DIALOG_BACKTITLE" \
        --title "$title" \
        --checklist "Space to toggle, Enter to confirm:" \
        $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
        "${items[@]}" \
        2>&1 >/dev/tty
}

# Single-select menu
# Usage: dialog_menu "title" "item1:description1" "item2:description2" ...
# Returns: selected item tag
dialog_menu() {
    local title="$1"; shift
    local items=()

    for item in "$@"; do
        IFS=':' read -r tag desc <<< "$item"
        items+=("$tag" "$desc")
    done

    dialog --clear --backtitle "$DIALOG_BACKTITLE" \
        --title "$title" \
        --menu "Select one:" $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
        "${items[@]}" \
        2>&1 >/dev/tty
}

# Yes/No confirmation dialog
# Usage: dialog_yesno "message"
# Returns: 0 for yes, 1 for no
dialog_yesno() {
    local message="$1"
    dialog --clear --backtitle "$DIALOG_BACKTITLE" \
        --title "Confirm" \
        --yesno "$message" 10 $DIALOG_WIDTH
}

# Information message box
# Usage: dialog_msgbox "title" "message"
dialog_msgbox() {
    local title="$1"
    local message="$2"
    dialog --clear --backtitle "$DIALOG_BACKTITLE" \
        --title "$title" \
        --msgbox "$message" $DIALOG_HEIGHT $DIALOG_WIDTH
}

# Scrollable text box for long content
# Usage: dialog_textbox "title" "content"
dialog_textbox() {
    local title="$1"
    local content="$2"
    local tmpfile
    tmpfile=$(mktemp)
    echo -e "$content" > "$tmpfile"
    dialog --clear --backtitle "$DIALOG_BACKTITLE" \
        --title "$title" \
        --textbox "$tmpfile" $DIALOG_HEIGHT $DIALOG_WIDTH
    rm -f "$tmpfile"
}

# Progress info box (non-blocking display)
# Usage: dialog_infobox "message"
dialog_infobox() {
    local message="$1"
    dialog --backtitle "$DIALOG_BACKTITLE" \
        --infobox "$message" 5 $DIALOG_WIDTH
}

# Check if dialog is available
dialog_available() {
    command -v dialog &>/dev/null
}

# Check if running in interactive terminal
is_interactive() {
    [[ -t 0 ]]
}
