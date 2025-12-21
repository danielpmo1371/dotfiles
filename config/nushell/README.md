# Nushell Configuration

Cross-platform nushell configuration for macOS and Linux/WSL.

## Overview

This configuration mirrors the functionality of the zsh/bash setup in `config/shell/` but takes advantage of nushell's structured data and modern shell features.

## Files

- **env.nu** - Environment variables, PATH setup, secrets loading (loaded first)
- **config.nu** - Shell configuration, sources aliases and zoxide (loaded second)
- **aliases.nu** - Aliases and custom commands (sourced from config.nu)

## Installation

The dotfiles installer should create a symlink:
```bash
~/.config/nushell -> ~/repos/dotfiles/config/nushell
```

## Key Features

### Environment Variables
- XDG base directories
- Editor configuration (nvim)
- AI tool settings (Gemini, OpenAI)
- FZF configuration
- Secrets loading from `~/.accessTokens`

### PATH Configuration
Cross-platform PATH setup that automatically detects and includes:
- Homebrew (macOS: `/opt/homebrew`, Linux: `/home/linuxbrew`)
- Standard system paths
- Development tools (.dotnet, cargo, pyenv, etc.)
- Dotfiles utilities (util-scripts, azcli-scripts)
- App-specific paths (lmstudio, console-ninja)

Paths are filtered to only include existing directories.

### Aliases
All aliases from `config/shell/aliases.sh` are mirrored:
- Navigation: `root`, `..`, `...`
- Editor: `n` (nvim), `fvim`, `nz` (nvim with fzf)
- Git: `gs`, `gsh`, `cm`, `psh`, `lg`, `lz` (lazygit), `flg` (fzf git log)
- AI tools: `cc` (claude), `gg` (gemini), `g` (gemini flash)
- Setup shortcuts: `setup-vim`, `setup-nu`, `setup-alias`, etc.
- Azure CLI helpers
- Python: `python` -> `python3`, `pip` -> `pip3`

### Shell Options
- Vi mode editing
- Fuzzy completion
- Persistent history (SQLite format)
- Custom prompt with git branch info
- Ctrl+R for history search

### Zoxide Integration
Smart `z` command for directory jumping. Generated with:
```bash
zoxide init nushell | save -f ~/.zoxide.nu
```

## Important Notes

### Config Loading Behavior

Nushell has different loading modes:

1. **Interactive shell** (just run `nu`): Loads both `env.nu` and `config.nu`
2. **Login mode** (`nu --login` or `nu -l`): Loads both `env.nu` and `config.nu`
3. **Script mode** (`nu -c "command"`): Only loads `env.nu`, NOT `config.nu`

This means:
- Aliases are only available in interactive/login shells
- Environment variables are available in all modes
- To test aliases from command line, use: `nu --login -c 'which alias-name'`

### Pyenv Support

If `~/.pyenv` exists, PYENV_ROOT is set and pyenv bin is added to PATH.
Note: Full pyenv initialization (with shims) requires running:
```nu
# Add to config.nu if you use pyenv actively
if (which pyenv | is-not-empty) {
    ^pyenv init - | save -f ~/.pyenv-init.nu
    source ~/.pyenv-init.nu
}
```

### Secrets Loading

Secrets are loaded from:
1. `~/.accessTokens` (primary location)
2. `$DOTFILES_DIR/.accessTokens` (WSL convenience)

Format: Simple `KEY=VALUE` pairs, one per line. Lines starting with `#` are ignored.

## Cross-Platform Compatibility

The configuration works on both macOS and Linux/WSL:
- PATH entries are filtered to only existing directories
- Both Homebrew locations are supported
- File paths use nushell's `path join` for OS-agnostic path handling
- No platform-specific commands (uses nushell builtins where possible)

## Testing

Test the configuration:
```bash
# Test aliases (requires --login flag for non-interactive shells)
nu --login -c 'which n'
nu --login -c 'which z'

# Test environment
nu -c '$env.EDITOR'
nu -c '$env.DOTFILES_DIR'

# Test vi mode
nu -c '$env.config.edit_mode'  # Should output: vi

# Test PATH
nu -c '$env.PATH | length'
```

## Customization

- To disable vi mode: Change `edit_mode: vi` to `edit_mode: emacs` in config.nu
- To use Starship prompt: Uncomment the starship section in env.nu
- To add custom aliases: Edit aliases.nu
- To add environment variables: Edit env.nu

## Differences from Zsh/Bash Config

### Advantages
- Structured data handling (tables, JSON, etc.)
- Better error messages
- Type-aware completions
- Built-in commands for common operations
- No need for external tools for many tasks

### Nushell-Specific Features
Added aliases that leverage structured data:
- `azl` - Azure account list as a formatted table
- `gst` - Git status as a structured table
- `dps` - Docker ps as structured data
- `psg [pattern]` - Process search
- `big [size]` - Find large files
- `jq-explore [file]` - Interactive JSON exploration

### Things That Don't Work the Same
- No subshells with `$()` - use `( )` instead
- String interpolation uses `$""` or `$''`
- Pipes work on structured data, not just text
- Functions defined with `def`, not `function` or `()`
