# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Personal dotfiles repository with modular installation system. Supports macOS and Linux with cross-platform package manager detection (brew, apt, dnf, pacman, choco).

## Installation Commands

```bash
# Full installation
./install.sh

# Individual components
./install.sh --tools        # Dev tools (git, nvim, chafa, ripgrep, etc.)
./install.sh --secrets      # Create ~/.accessTokens template
./install.sh --tmux         # Tmux + TPM + plugins (requires: git)
./install.sh --bash         # Bash configuration
./install.sh --zsh          # Zsh configuration (requires: git, zsh, curl)
./install.sh --terminals    # Terminal emulators (Ghostty, etc.)
./install.sh --fonts        # Nerd Fonts for Powerlevel10k (requires: curl)
./install.sh --config-dirs  # Symlink nvim to ~/.config/
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
1. tools.sh → secrets.sh → terminals.sh → fonts.sh → tmux.sh → bash.sh → zsh.sh → config-dirs.sh → claude.sh

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
- `scripts/pipeline-validator.sh` - Hard safety rules for pipeline triggers (blocks PRE/PRD)
- `scripts/pipeline-registry.sh` - CWD-based service detection and pipeline ID resolution
- `hooks/pipeline-guard.sh` - PreToolUse hook intercepting direct MCP pipeline calls
- `commands/pipe-deploy.md` - `/pipe-deploy` command for CI/CD orchestration
- `agents/pipeline-runner.md` - Autonomous pipeline trigger/monitor/recovery agent
- `skills/pipeline-ops/` - Auto-discoverable skill matching "deploy", "run pipeline" etc.

Local files (not synced): `settings.local.json`, `.credentials.json`

### MCP Server Configuration

**IMPORTANT**: Claude Code reads MCP servers from `~/.claude.json` (the `mcpServers` key), NOT from `~/.claude/mcp.json` or `settings.json`.

**To add/remove/modify MCP servers:**
1. Edit `config/mcp/servers.json` (canonical source of truth)
2. Run `./install.sh --mcp` (or `./installers/mcp.sh`) to sync into `~/.claude.json`
3. Restart Claude Code to load changes

**Never** edit `~/.claude.json` directly for MCP servers — the installer will overwrite manual changes.

Files:
- `config/mcp/servers.json` - Server definitions (tracked in git)
- `config/mcp/mcp-env.local` - API keys (gitignored)
- `installers/mcp.sh` - Sync script that merges servers into `~/.claude.json`

## Agent Teams (Experimental)

Claude Code Agent Teams are enabled for parallel work on this repo. Teams coordinate multiple Claude Code instances working together with shared tasks and inter-agent messaging. Requires tmux (installed via `--tmux`).

### Available Team Commands

| Command | What it does |
|---------|-------------|
| `/setup-machine` | Spawns 4 teammates to install dotfiles in parallel (base tools, shells, dev env, claude/mcp) |
| `/test-all-distros` | Spawns 3 teammates to run Docker e2e tests on Ubuntu, Debian, and Fedora simultaneously |
| `/review-changes` | Spawns 3 teammates for pre-commit review (cross-platform compat, security, symlink validation) |

### Configuration

Agent teams are enabled in `config/claude/settings.json`:
- `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`: `"1"` enables the feature
- `teammateMode`: `"auto"` uses tmux split panes when inside tmux, in-process otherwise

### Test Harness

Test scripts in `tests/` that teammates (or manual runs) can use:
- `tests/test-installer.sh <component|all>` - Validates a single installer's results
- `tests/test-docker.sh <distro|all>` - Builds Docker image and runs full e2e test
- `tests/validate-symlinks.sh` - Checks all expected symlinks exist and point correctly

## Adding New Configurations

1. Create config in appropriate `config/<tool>/` directory
2. Add installer in `installers/<tool>.sh` following existing pattern
3. Add dispatch case in `install.sh` if standalone option needed
4. Use `lib/install-common.sh` functions for symlinks and backups
