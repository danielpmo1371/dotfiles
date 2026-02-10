---
allowed-tools: Bash(*), Read(*), Edit(*), Write(*), Glob(*), Grep(*)
description: Agent team for parallel dotfiles machine setup
---

## Agent Team: Machine Setup

Create an agent team to install and configure this dotfiles system in parallel.
The dotfiles repo is at: $CWD

### Team Structure

Spawn 4 teammates with these roles. Use delegate mode (Shift+Tab) so you coordinate without implementing directly.

**Teammate 1 - "base-setup"**: Install foundational tools, secrets template, and terminal emulators.
- Run `./install.sh --tools` to install dev tools (git, nvim, ripgrep, chafa, etc.)
- Run `./install.sh --secrets` to create ~/.accessTokens template
- Run `./install.sh --terminals` to install terminal emulator configs (Ghostty)
- Validate: confirm all tools are available via `which git nvim chafa rg`
- Report any package manager issues or missing dependencies

**Teammate 2 - "shell-config"**: Install all shell configurations.
- Wait for base-setup to complete tools installation (dependency)
- Run `./install.sh --bash` to install bash configuration
- Run `./install.sh --zsh` to install zsh configuration
- Validate: confirm symlinks exist for ~/.bashrc, ~/.zshrc
- Validate: `source ~/.bashrc` and `source ~/.zshrc` complete without errors
- Report any broken symlinks or sourcing errors

**Teammate 3 - "dev-environment"**: Install tmux, neovim config, and config directory symlinks.
- Wait for base-setup to complete tools installation (dependency)
- Run `./install.sh --tmux` to install tmux + TPM + plugins
- Run `./install.sh --config-dirs` to symlink config directories (nvim -> ~/.config/nvim)
- Validate: `tmux -V` works, `~/.config/nvim` symlink points correctly
- Validate: tmux plugins directory exists at `~/.tmux/plugins/tpm`
- Report any plugin installation failures

**Teammate 4 - "claude-mcp"**: Install Claude Code settings and MCP configuration.
- Wait for base-setup to complete tools installation (dependency: node/npm)
- Run `./install.sh --claude` to install Claude Code CLI and settings
- Run `./install.sh --mcp` to install MCP configuration
- Run `./install.sh --memory-hooks` to install memory service hooks
- Run `./install.sh --logging-hooks` to install session logging hooks
- Validate: ~/.claude/settings.json symlink exists and is valid JSON
- Validate: MCP config is properly linked
- Report any npm install failures or broken config

### Task Dependencies

```
base-setup (no deps)
  -> shell-config (blocked by base-setup)
  -> dev-environment (blocked by base-setup)
  -> claude-mcp (blocked by base-setup)
```

### Completion

After all teammates finish:
1. Synthesize results from all 4 teammates
2. List any failures or warnings
3. Provide a summary of what was installed and any manual steps remaining
4. Suggest running `source ~/.zshrc` to pick up changes
