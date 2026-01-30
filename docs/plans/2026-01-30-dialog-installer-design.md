# Dialog-Based Installer Refactor

**Date:** 2026-01-30
**Status:** Approved

## Overview

Refactor the dotfiles installation system to use `dialog` (ncurses-based TUI) for an interactive experience while preserving CLI flags for scripting.

## Goals

- Interactive checklist for component selection
- Guided wizard for tools/package selection with profiles
- Hybrid approach: CLI flags for automation, dialog as default
- Dependency prompts when selections require other packages

## File Structure

```
install.sh                  # Entry point - mode detection + orchestration
lib/
  install-common.sh         # Existing - logging, symlinks, backups
  install-packages.sh       # Existing - cross-platform package install
  dialog-ui.sh              # NEW - dialog wrapper functions
installers/
  brew.sh                   # NEW - Homebrew with OS detection
  tools.sh                  # Existing
  zsh.sh                    # Existing
  bash.sh                   # Existing
  tmux.sh                   # Existing
  terminals.sh              # Existing
  claude.sh                 # Existing
  mcp.sh                    # Existing
```

## Mode Detection

| Invocation | Mode |
|------------|------|
| `./install.sh` | Dialog (if available + interactive terminal) |
| `./install.sh --dialog` | Dialog (forced) |
| `./install.sh --tools` | CLI |
| `./install.sh --all` | CLI |
| `echo "y" \| ./install.sh` | CLI (non-interactive stdin) |

## Dialog Flow

```
┌─────────────────┐
│  Welcome Screen │
│  ─────────────  │
│  1. Install     │
│  2. Configure   │
│  3. Help        │
│  4. Exit        │
└────────┬────────┘
         │ "Install"
         ▼
┌─────────────────┐
│ Component List  │  ← Checklist: brew, tools, shells, tmux, etc.
└────────┬────────┘
         │ if "tools" selected
         ▼
┌─────────────────┐
│ Profile Select  │  ← Minimal / Developer / Full / Custom
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Package List    │  ← Individual checkboxes, profile pre-fills
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Dep Resolution  │  ← "Zsh requires git. Add?" prompts
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Confirmation    │  ← Summary of what will be installed
└────────┬────────┘
         │
         ▼
     [Install]
```

## Package Profiles

| Profile | Packages |
|---------|----------|
| **Minimal** | brew, git, curl, wget |
| **Developer** | Minimal + nvim, tmux, zsh, node, npm, ripgrep, fzf, fd, bat, jq |
| **Full** | Developer + git-delta, lsd, zoxide, eza, chafa, htop, btop, tree, gdu, terminal-notifier, neofetch, tlrc |

## Brew Installer (New)

Cross-platform Homebrew installation with OS detection:

- **macOS:** Xcode CLI tools (installer prompts automatically)
- **Debian/Ubuntu:** `sudo apt-get install build-essential procps curl file git`
- **Fedora:** `sudo dnf group install 'Development Tools' && sudo dnf install procps-ng curl file`
- **Arch:** `sudo pacman -S base-devel procps-ng curl file git`

Install paths:
- Linux: `/home/linuxbrew/.linuxbrew`
- macOS Apple Silicon: `/opt/homebrew`
- macOS Intel: `/usr/local`

## Dialog UI Library

Wrapper functions in `lib/dialog-ui.sh`:

- `dialog_welcome` - Main menu
- `dialog_checklist` - Multi-select with on/off states
- `dialog_menu` - Single-select menu
- `dialog_yesno` - Confirmation prompt
- `dialog_msgbox` - Info display
- `dialog_progress` - Progress gauge

## Dependency Resolution

1. For each selected component, check required packages
2. Skip if package already installed on system (`command -v`)
3. Skip if package already in user's selection
4. Otherwise prompt: "Component X requires Y. Add?"
5. User confirms or declines per dependency
6. Show warning summary for declined dependencies

## Component Dependencies

| Component | Requires |
|-----------|----------|
| zsh | git, zsh, curl |
| tmux | git, tmux |
| claude | node, npm |
| mcp | jq |

## Installation Order

1. Homebrew (if selected)
2. Packages (if tools selected)
3. Component installers: zsh, bash, tmux, terminals, claude, mcp

## Implementation Tasks

1. Create `lib/dialog-ui.sh` - dialog wrapper functions
2. Create `installers/brew.sh` - Homebrew with OS detection
3. Update `install.sh` - mode detection + dialog orchestration
4. Update `lib/install-packages.sh` - add profile definitions
5. Test on macOS, Ubuntu, Fedora
6. Update README with new usage instructions
