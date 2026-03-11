# Tmux Ask Claude Feature

## Summary

Replace the standalone `prefix + ?` help popup with a combined menu offering both the keybindings cheat sheet and a "Ask Claude" input that feeds questions into the persistent claude-popup session.

## Flow

```
prefix + ?
    ├── [h] Help        → existing keybindings cheat sheet popup
    └── [a] Ask Claude  → input prompt → sends question to claude-popup session → opens popup
```

## Approach

Uses tmux's native `display-menu` command. Lightweight, no dependencies, perfect for 2 options.

## Components

### 1. tmux.conf binding change

Rebind `prefix + ?` to call `tmux-ask-menu.sh` instead of `tmux-help-popup.sh`.

### 2. `util-scripts/tmux-ask-menu.sh`

Displays a `tmux display-menu` with two options:
- **Help** → runs existing `tmux-help-popup.sh`
- **Ask Claude** → uses `tmux command-prompt` to capture input, then calls `tmux-claude-ask.sh "<question>"`

### 3. `util-scripts/tmux-claude-ask.sh`

Receives a question string as argument:
1. Ensures the `claude-popup` session exists (creates if needed with `~/repos/dotfiles` as cwd)
2. Sends the question as keystrokes to the claude-popup session
3. Opens the popup so user sees the response

## UX

1. `prefix + ?` → small menu appears near cursor
2. Press `h` for help, `a` for ask
3. If "ask": tmux command-prompt appears at bottom: `Ask Claude: |`
4. Type question, hit Enter
5. Claude popup opens with your question already submitted
