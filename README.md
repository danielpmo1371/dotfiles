# Dotfiles

Personal dotfiles with modular installation system. Supports macOS and Linux.

## Quick Install

Run as your local user (not root/sudo):

```bash
curl -fsSL https://raw.githubusercontent.com/danielpmo1371/dotfiles/main/bootstrap.sh | bash
```

Or clone manually:

```bash
git clone https://github.com/danielpmo1371/dotfiles.git ~/repos/dotfiles
cd ~/repos/dotfiles
./install.sh
```

## What's Included

- **Shell**: Zsh (with Zap plugin manager) and Bash configurations
- **Terminal**: Ghostty configuration
- **Tmux**: Config with TPM and plugins (gruvbox, resurrect, continuum, floax)
- **Neovim**: LazyVim-based configuration
- **CLI Tools**: ripgrep, fd, bat, fzf, zoxide, lsd, jq, chafa, htop
- **Claude Code**: CLI settings, custom commands, and skills

## Installation Options

### Interactive Mode (Recommended)

```bash
./install.sh              # Launch interactive dialog installer
```

The dialog mode provides:
- Component selection checklist (brew, tools, shells, tmux, etc.)
- Package profiles: Minimal, Developer, Full, or Custom
- Individual package selection with pre-filled profiles
- Dependency resolution with prompts

### CLI Mode

```bash
./install.sh --all        # Install everything
./install.sh --brew       # Homebrew package manager
./install.sh --tools      # Dev tools (nvim, ripgrep, fzf, etc.)
./install.sh --secrets    # Create ~/.accessTokens template
./install.sh --terminals  # Terminal emulators (Ghostty)
./install.sh --tmux       # Tmux + TPM + plugins
./install.sh --bash       # Bash configuration
./install.sh --zsh        # Zsh + Zap plugin manager
./install.sh --config-dirs # Symlink nvim config
./install.sh --claude     # Claude Code CLI + settings
./install.sh --help       # Show all options
```

## Package Manager

On first run, you'll be prompted to choose a package manager:

```
Available package managers:
  1) brew (will be installed)
  2) pacman

Choose package manager [1-2] (default: 1):
```

Homebrew is recommended and will be installed automatically if selected. Your choice is cached in `~/.dotfiles_pkg_manager`.

## Directory Structure

```
dotfiles/
├── bootstrap.sh          # One-line installer
├── install.sh            # Main installer (dialog + CLI modes)
├── installers/           # Individual installer scripts
│   ├── brew.sh           # Homebrew with OS detection
│   ├── tools.sh          # CLI tools
│   ├── secrets.sh        # ~/.accessTokens template
│   ├── terminals.sh      # Ghostty config
│   ├── tmux.sh           # Tmux + TPM + plugins
│   ├── bash.sh           # Bash configuration
│   ├── zsh.sh            # Zsh + Zap
│   ├── config-dirs.sh    # ~/.config symlinks
│   └── claude.sh         # Claude Code
├── lib/                  # Shared functions
│   ├── install-common.sh # Logging, symlinks, backups
│   ├── install-packages.sh # Package manager abstraction
│   └── dialog-ui.sh      # Dialog TUI wrapper functions
└── config/               # Configuration files
    ├── shell/            # Shared shell configs (env, path, aliases)
    ├── bash/             # Bash-specific
    ├── zsh/              # Zsh-specific
    ├── tmux/             # tmux.conf
    ├── nvim/             # Neovim (LazyVim)
    ├── ghostty/          # Ghostty terminal
    └── claude/           # Claude Code settings
```

## Post-Install

```bash
# Reload shell config
source ~/.zshrc   # or ~/.bashrc

# Configure powerlevel10k prompt (zsh)
p10k configure

# Add API keys
nvim ~/.accessTokens
```

## Requirements

- `git` and `curl` (for bootstrap)
- `dialog` (for interactive mode, optional - falls back to CLI)
- macOS or Linux (Arch, Ubuntu, Fedora, etc.)

## License

MIT
