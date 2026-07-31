# Dotfiles

Personal dotfiles with a modular installation system. Supports macOS and Linux
(Arch, Ubuntu, Debian, Fedora) with cross-platform package manager detection.

## Quick Install

Run as your local user (not root/sudo):

```bash
curl -fsSL https://raw.githubusercontent.com/danielpmo1371/dotfiles/main/bootstrap.sh | bash
```

Or clone manually:

```bash
git clone https://github.com/danielpmo1371/dotfiles.git ~/repos/dotfiles
cd ~/repos/dotfiles
./install.sh          # interactive dialog installer
./install.sh --all    # or: install everything non-interactively
```

## Design Principle: Terminal-Agnostic Config

Behaviour lives in the most portable layer that can implement it:
**tmux → shell → app config → terminal emulator**. Emulator configs (Ghostty,
Kitty) stay deliberately thin — rendering, OS integration, and forwarding keys
the OS swallows — so the whole workflow survives switching terminals.
Rationale and the decision test: [docs/terminal-agnostic-config.md](docs/terminal-agnostic-config.md).

## What's Included

What each feature buys you day-to-day:
[docs/features-and-benefits.md](docs/features-and-benefits.md).

- **Shell**: Zsh (Zap plugin manager, Powerlevel10k) and Bash, sharing modular
  configs from `config/shell/` (env, path, aliases, git, tmux)
- **Tmux**: TPM plugins (gruvbox, resurrect + continuum session persistence,
  which-key, vim-tmux-navigator) plus a hand-rolled popup workflow backed by
  `util-scripts/` — highlights (prefix is `C-e`):
  - `prefix i` — Claude pane picker: fzf list of every pane running Claude
    Code with live preview; Enter jumps to it
  - `C-a` / `C-w` / `C-s` — nvim, lazygit, and clean-shell popups
- **Neovim**: LazyVim-based configuration
- **Terminals**: thin Ghostty and Kitty configs; on macOS, Terminal.app's
  default font is set to a Nerd Font automatically
- **CLI tools**: ripgrep, fd, bat, fzf, zoxide, lsd, jq, htop, and more
- **Secrets**: OS-native keychain storage (macOS Keychain / Linux libsecret)
  via the `nuvemlabs/secrets` library — `secret_set KEY VALUE` to store,
  `secret KEY` to read; legacy `~/.accessTokens` files auto-migrate
- **Quick AI query**: `q "your question"` — one-shot LLM answer in the
  terminal, optimized for fast first token (Groq by default; switch providers
  with `AI_PROVIDER`)
- **Claude Code**: settings, custom commands, skills, agents, safety hooks,
  and MCP server sync — see [Claude Code Setup](#claude-code-setup)

## Installation Options

`./install.sh` with no arguments launches an interactive dialog installer
(component checklist, package profiles, dependency resolution). All flags below
run non-interactively.

### Everything, or the core

```bash
./install.sh --all        # Phase 1 (dotfiles core) then Phase 2 (Claude Code)
./install.sh --dotfiles   # Phase 1 only: terminal & tmux workflow, no Claude Code
```

Phase 1 runs, in order: brew (macOS) → tools → casks → secrets → fonts → tmux →
bash → zsh → terminals → config-dirs → mcp → memory-hooks → logging-hooks →
pipeline-hooks. Phase 2 installs the Claude Code CLI and symlinks its config.

### Individual components

```bash
./install.sh --brew         # Homebrew package manager
./install.sh --tools        # Dev tools (git, nvim, ripgrep, fzf, etc.)
./install.sh --casks        # macOS GUI apps from config/brew/Brewfile (macOS only)
./install.sh --secrets      # Keychain-backed secrets library (needs ~/repos/secrets clone)
./install.sh --fonts        # MesloLGS Nerd Fonts for Powerlevel10k
./install.sh --tmux         # Tmux + TPM + plugins
./install.sh --bash         # Bash configuration
./install.sh --zsh          # Zsh + Zap plugin manager
./install.sh --terminals    # Ghostty/Kitty configs + Terminal.app font (macOS)
./install.sh --config-dirs  # Symlink nvim and fastfetch into ~/.config/
```

### Claude Code & AI

```bash
./install.sh --claude       # Claude Code CLI + settings (also installs pipeline hooks)
./install.sh --mcp          # Sync config/mcp/servers.json into ~/.claude.json
./install.sh --llm          # llm CLI + Groq plugin — powers the `q` quick-query
./install.sh --memory-hooks # Persistent-memory hooks for Claude Code
./install.sh --logging-hooks # Session logging hooks
./install.sh --claude-azdo-pipeline-hooks  # Azure DevOps pipeline guard hooks
```

### Backup & restore

Installers back up anything they replace. Manage backups with:

```bash
./install.sh --restore              # Interactive restore from backup
./install.sh --list-backups         # List available backups
./install.sh --cleanup-backups [N]  # Keep only N most recent (default: 5)
```

`./install.sh --help` shows the full list.

## Package Manager

On first run you're prompted to choose from the package managers detected on
your system (brew, apt, dnf, pacman, choco); the choice is cached in
`~/.dotfiles_pkg_manager`. Homebrew is recommended and can be installed
automatically.

## Claude Code Setup

`config/claude/` is symlinked into `~/.claude/`: global instructions
(`CLAUDE.md`), `settings.json`, custom slash commands, skills, and agents.
Safety comes from PreToolUse hooks — a destructive-ops guard and three Azure
DevOps pipeline guards that block accidental production triggers.

MCP servers are defined once in `config/mcp/servers.json` and synced into
`~/.claude.json` with `./install.sh --mcp`; secret references are rewritten to
env-var placeholders so credentials never land on disk. Never edit
`~/.claude.json` by hand — the installer overwrites it.

Details: [CLAUDE.md](CLAUDE.md) and [config/mcp/README.md](config/mcp/README.md).

## Testing

```bash
tests/test-installer.sh <component|all>   # Validate an installer's results
tests/validate-symlinks.sh                # Check all expected symlinks
tests/test-docker.sh <distro|all>         # Full e2e install in Docker (arch, ubuntu, debian, fedora)
tests/test-pipeline-validator.sh          # Hermetic safety tests for the pipeline validator
tests/test-pipeline-hooks.sh              # Hermetic safety tests for the guard hooks
```

## Directory Structure

```
dotfiles/
├── bootstrap.sh          # One-line installer
├── install.sh            # Main installer (dialog + CLI modes)
├── installers/           # One script per component (tools, zsh, tmux, claude, mcp, ...)
├── lib/                  # Shared functions (logging, symlinks, backups, packages, secrets)
├── config/               # Configuration files, one directory per tool
│   ├── shell/            # Shared shell configs sourced by bash and zsh
│   ├── bash/  zsh/       # Shell-specific configs
│   ├── tmux/             # tmux.conf
│   ├── nvim/             # Neovim (LazyVim)
│   ├── ghostty/  kitty/  # Terminal emulator configs (+ Ghostty shaders)
│   ├── brew/             # Brewfile for macOS GUI apps
│   ├── mcp/              # MCP server definitions (canonical source)
│   └── claude/           # Claude Code settings, commands, skills, agents, hooks
├── util-scripts/         # Scripts backing the tmux popup workflow
├── tests/                # Test harness + Docker e2e images
└── docs/                 # Design docs, plans, and post-mortem learning notes
```

External dependencies and where to edit them: [DEPENDENCIES.md](DEPENDENCIES.md).

## Post-Install

```bash
source ~/.zshrc              # reload shell config (or ~/.bashrc)
p10k configure               # configure the zsh prompt
secret_set GROQ_API_KEY ...  # store API keys in the OS keychain
```

## Requirements

- `git` and `curl` (for bootstrap)
- `dialog` (only for interactive mode)
- macOS or Linux (Arch, Ubuntu, Debian, Fedora)

## License

MIT
