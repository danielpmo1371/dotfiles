# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Personal dotfiles repository with modular installation system. Supports macOS and Linux with cross-platform package manager detection (brew, apt, dnf, pacman, choco).

## Installation Commands

```bash
# Full installation
./install.sh

# Individual components
./install.sh --tools        # Dev tools (nvim, ripgrep, fd, bat, etc.)
./install.sh --shell        # Shared shell config (chafa, .accessTokens)
./install.sh --tmux         # Tmux + TPM + plugins (requires: git)
./install.sh --bash         # Bash configuration
./install.sh --zsh          # Zsh configuration (requires: git, zsh)
./install.sh --config-dirs  # Symlink nvim, ghostty to ~/.config/
./install.sh --claude       # Claude Code CLI and settings (requires: node, npm)

# After shell config changes
source ~/.zshrc  # or ~/.bashrc
```

## Architecture

### Directory Structure

```
installers/          # Individual installer scripts (bash.sh, zsh.sh, etc.)
lib/                 # Shared functions
  install-common.sh  # Logging, symlink helpers, backup utilities
  install-packages.sh # Cross-platform package installation
config/              # Configuration files organized by tool
  shell/             # Shared configs sourced by both bash and zsh
  bash/              # Bash-specific (bashrc, bash_aliases, bash_path)
  zsh/               # Zsh-specific (zshrc)
  tmux/              # Tmux configuration (tmux.conf)
  nvim/              # Neovim (LazyVim-based)
  claude/            # Claude Code settings, commands, skills
  ghostty/           # Ghostty terminal config
```

### Key Patterns

**Installation Flow**: `install.sh` dispatches to `installers/*.sh` scripts which source `lib/install-common.sh` for utilities. Order matters for `--all`:
1. tools.sh → shell.sh → tmux.sh → bash.sh → zsh.sh → config-dirs.sh → claude.sh

**Symlink Strategy**:
- `config/` subdirs symlink to `~/.config/` via `link_config_dirs()`
- Individual files use `link_home_files()` for `source:target` mapping
- Claude files use `link_target_files()` to `~/.claude/`

**Shell Config**: Modular design where `~/.zshrc` and `~/.bashrc` source shared files from `config/shell/` (env.sh, path.sh, aliases.sh, git.sh, tmux.sh).

**Package Manager**: Auto-detects available managers, prompts user on first run, caches choice in `~/.dotfiles_pkg_manager`.

### Neovim Setup

LazyVim-based configuration. Plugin definitions in `config/nvim/lua/plugins/`. Custom keymaps in `config/nvim/lua/config/keymaps.lua`.

### Claude Code Setup

Settings symlinked from `config/claude/` to `~/.claude/`:
- `CLAUDE.md` - Global user instructions
- `settings.json` - Permissions and config
- `commands/` - Custom slash commands
- `skills/` - Custom skills

Local files (not synced): `settings.local.json`, `.credentials.json`

## Adding New Configurations

1. Create config in appropriate `config/<tool>/` directory
2. Add installer in `installers/<tool>.sh` following existing pattern
3. Add dispatch case in `install.sh` if standalone option needed
4. Use `lib/install-common.sh` functions for symlinks and backups
