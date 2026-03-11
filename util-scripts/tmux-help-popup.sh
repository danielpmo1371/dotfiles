#!/bin/bash
# tmux-help-popup.sh
# Display custom tmux keybindings in a popup

HELP_TEXT="
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    TMUX KEYBINDINGS CHEAT SHEET
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  PREFIX: Cmd+e  (or Ctrl+e)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  SESSIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Cmd+e  N        Create new session and switch to it
  Cmd+e  s        Choose session (interactive tree)
  Cmd+e  $        Rename current session
  Cmd+e  (        Switch to previous session
  Cmd+e  )        Switch to next session

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  WINDOWS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Cmd+e  c        Create new window
  Cmd+e  ,        Rename current window
  Cmd+e  n        Next window
  Cmd+e  p        Previous window
  Cmd+e  w        Choose window (interactive list)
  Cmd+e  &        Kill current window (with confirmation)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  GENERAL
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Cmd+e  r        Reload tmux config
  Cmd+e  e        Toggle synchronize panes
  Cmd+e  :        Enter tmux command mode

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  PANE NAVIGATION (with prefix)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Cmd+e  h        Select pane left
  Cmd+e  j        Select pane down
  Cmd+e  k        Select pane up
  Cmd+e  l        Select pane right

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  PANE NAVIGATION (without prefix)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Cmd+h           Select pane left
  Cmd+j           Select pane down
  Cmd+k           Select pane up
  Cmd+l           Select pane right

  Option+h        Quick cycle pane left
  Option+j        Quick cycle pane down
  Option+k        Quick cycle pane up
  Option+l        Quick cycle pane right

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  PANE RESIZING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Cmd+e  H        Resize pane left (repeatable)
  Cmd+e  J        Resize pane down (repeatable)
  Cmd+e  K        Resize pane up (repeatable)
  Cmd+e  L        Resize pane right (repeatable)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  PANE MANAGEMENT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Cmd+e  |        Split pane horizontally
  Cmd+e  -        Split pane vertically
  Cmd+e  p        Display pane numbers (press # to jump)
  Cmd+e  m        Swap pane (shows numbers, press # to swap)
  Cmd+e  x        Close pane (with confirmation)
  Cmd+e  z        Toggle zoom pane (fullscreen)
  Cmd+e  {        Swap pane with previous
  Cmd+e  }        Swap pane with next
  Cmd+e  !        Break pane into new window

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  COPY MODE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Cmd+e  [        Enter copy mode
  Cmd+e Cmd+e     Enter copy mode

  (In copy mode: Vi keybindings active)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  CLAUDE CODE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Cmd+e Cmd+n     Toggle Claude Code popup
  Cmd+e  q        Close Claude popup
  Esc             Close popup (session persists)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  HELP & ASK CLAUDE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Cmd+e  ?        Menu: [h] Help  [a] Ask Claude

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Press q to close (or type a question for Claude after closing)
"

SCRIPTS_DIR="$HOME/repos/dotfiles/util-scripts"
SESSION_NAME="claude-popup"
DOTFILES_DIR="$HOME/repos/dotfiles"

# Display help in a popup, then prompt to ask Claude
tmux display-popup -E -w 80% -h 90% "bash -c '
echo \"$HELP_TEXT\" | less -R

# After less exits, offer Ask Claude prompt
printf \"\n\033[1;33m Ask Claude:\033[0m \"
read -r question
if [ -n \"\$question\" ]; then
    # Ensure claude session exists
    if ! tmux has-session -t $SESSION_NAME 2>/dev/null; then
        tmux new-session -d -s $SESSION_NAME -c $DOTFILES_DIR claude
        sleep 2
    fi
    # Send question to claude session
    tmux send-keys -t $SESSION_NAME \"\$question\" Enter
    # Schedule claude popup to open after this one closes
    tmux run-shell -b \"sleep 0.3 && $SCRIPTS_DIR/tmux-claude-popup.sh\"
fi
'"
