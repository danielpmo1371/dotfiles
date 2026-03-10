# External Dependencies

This document tracks all external dependencies used by this dotfiles repository.

## Purpose

- **Transparency**: Know what external code we depend on
- **Safety**: Prevent editing installed code instead of source
- **Maintenance**: Track versions and update paths

## Dependencies

### 1. nuvemlabs/secrets

**Purpose**: Cross-platform secret management library (macOS Keychain, Linux libsecret, Windows Credential Manager, file fallback)

**Repository**: https://github.com/nuvemlabs/secrets.git
**Local Clone**: `~/repos/secrets/`
**Installed To**: `~/.local/lib/secrets/`
**Installer**: `installers/secrets.sh`
**Entry Point**: `config/shell/secrets.sh` (sources the installed library)

**How to Update**:
```bash
cd ~/repos/secrets
git pull origin main
cd ~/repos/dotfiles
./install.sh --secrets  # Reinstall to apply changes
```

**How to Fix Bugs**:
1. Edit source in `~/repos/secrets/secrets.sh`
2. Commit changes to the secrets repo
3. Re-run `./install.sh --secrets` to apply fix
4. **NEVER** edit `~/.local/lib/secrets/secrets.sh` directly

**Version Tracking**: None (uses local clone's HEAD)
**Last Updated**: 2026-03-11 (zsh compatibility fix)

---

### 2. Tmux Plugin Manager (TPM)

**Purpose**: Tmux plugin management

**Repository**: https://github.com/tmux-plugins/tpm
**Installed To**: `~/.tmux/plugins/tpm/`
**Installer**: `installers/tmux.sh`
**Config**: `config/tmux/tmux.conf`

**How to Update**:
```bash
~/.tmux/plugins/tpm/bin/update_plugins all
```

**Plugins Managed by TPM**:
- `tmux-plugins/tmux-sensible` (sensible defaults)
- `tmux-plugins/tmux-yank` (clipboard integration)
- `tmux-plugins/tmux-resurrect` (session persistence)
- `tmux-plugins/tmux-continuum` (auto-save sessions)

---

### 3. Powerlevel10k

**Purpose**: Zsh theme (fast, customizable prompt)

**Repository**: https://github.com/romkatv/powerlevel10k.git
**Installed To**: `~/.oh-my-zsh/custom/themes/powerlevel10k/`
**Installer**: `installers/zsh.sh`
**Config**: `~/.p10k.zsh` (user-generated via `p10k configure`)

**How to Update**:
```bash
git -C ~/.oh-my-zsh/custom/themes/powerlevel10k pull
```

---

### 4. Oh My Zsh

**Purpose**: Zsh framework

**Repository**: https://github.com/ohmyzsh/ohmyzsh.git
**Installed To**: `~/.oh-my-zsh/`
**Installer**: `installers/zsh.sh`
**Config**: `config/zsh/zshrc`

**How to Update**:
```bash
~/.oh-my-zsh/tools/upgrade.sh
```

**Plugins Used**:
- `git` (git aliases)
- `tmux` (tmux integration)
- `zsh-autosuggestions` (fish-like suggestions)
- `zsh-syntax-highlighting` (command syntax highlighting)

---

### 5. LazyVim

**Purpose**: Neovim distribution (pre-configured with sane defaults)

**Repository**: https://github.com/LazyVim/LazyVim
**Installed To**: Managed by lazy.nvim plugin manager
**Installer**: `installers/tools.sh` (installs nvim), `config/nvim/` (config)
**Config**: `config/nvim/lua/` (entire directory)

**How to Update**:
```bash
nvim  # Then run :Lazy sync
```

**Plugin Manager**: `lazy.nvim` (bundled with LazyVim)

---

## System Packages (via Package Managers)

These are installed but not "owned" by this repo:

### Developer Tools
- `git` (version control)
- `neovim` (editor)
- `tmux` (terminal multiplexer)
- `zsh` (shell)
- `ripgrep` (fast grep)
- `fzf` (fuzzy finder)
- `jq` (JSON processor)
- `chafa` (terminal image viewer)

### Package Manager Used
- macOS: Homebrew (`brew`)
- Ubuntu/Debian: APT (`apt`)
- Fedora: DNF (`dnf`)
- Arch: Pacman (`pacman`)
- Windows: Chocolatey (`choco`)

**Installer**: `lib/install-packages.sh` (cross-platform abstraction)

---

## Fonts

### Nerd Fonts

**Purpose**: Icon-patched fonts for terminal (used by Powerlevel10k)

**Repository**: https://github.com/ryanoasis/nerd-fonts
**Installed To**: `~/Library/Fonts/` (macOS) or `~/.local/share/fonts/` (Linux)
**Installer**: `installers/fonts.sh`
**Fonts Installed**: `Meslo`, `FiraCode`, `JetBrainsMono`, `Hack`

**How to Update**:
```bash
./install.sh --fonts  # Downloads latest releases
```

---

## MCP Servers (Model Context Protocol)

These are NOT tracked in this repo but referenced in `config/mcp/servers.json`:

### mcp-azure-devops
**Purpose**: Azure DevOps integration for Claude Code
**Installation**: `npm install -g mcp-azure-devops`
**Config**: `config/mcp/servers.json`

### memory-mcp
**Purpose**: Persistent memory for Claude Code
**Installation**: Custom (running as service)
**Config**: `config/mcp/servers.json`

### browser-local
**Purpose**: Local browser automation for Claude Code
**Installation**: Part of Claude Code
**Config**: `config/mcp/servers.json`

---

## Contribution Guidelines

When adding new external dependencies:

1. **Add entry to this file** with all relevant info
2. **Create installer** in `installers/<name>.sh` if needed
3. **Document update process** (how to pull latest)
4. **Document fix process** (where to edit source)
5. **Avoid editing installed code** — always fix at source

---

## Quick Reference: Where to Edit

| What | Edit Here | Never Edit Here |
|------|-----------|-----------------|
| Secrets library | `~/repos/secrets/` | `~/.local/lib/secrets/` |
| Dotfiles config | `~/repos/dotfiles/config/` | `~/.config/` (symlinks) |
| Installers | `~/repos/dotfiles/installers/` | N/A |
| Tmux plugins | Use TPM commands | `~/.tmux/plugins/` |
| Zsh theme | Use `p10k configure` | `~/.oh-my-zsh/` |
| Neovim plugins | `config/nvim/lua/plugins/` | Lazy cache |
| System packages | Report upstream | `/usr/local/`, `/opt/` |

**Golden Rule**: If it's in `~/.local/lib/`, `~/.local/bin/`, `~/.oh-my-zsh/`, `~/.tmux/plugins/`, or any install directory → find the source, edit there, then reinstall.
