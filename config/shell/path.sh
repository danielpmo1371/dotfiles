# Shared PATH additions - works in both bash and zsh
# Source this from .bashrc and .zshrc

# ─────────────────────────────────────────────────────────────────────────────
#   Standard paths
# ─────────────────────────────────────────────────────────────────────────────
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# ─────────────────────────────────────────────────────────────────────────────
#   Development tools
# ─────────────────────────────────────────────────────────────────────────────
# Neovim
[[ -d "/opt/nvim" ]] && export PATH="/opt/nvim:$PATH"

# .NET
[[ -d "$HOME/.dotnet" ]] && export PATH="$HOME/.dotnet:$PATH"
[[ -d "$HOME/.dotnet/tools" ]] && export PATH="$HOME/.dotnet/tools:$PATH"

# Rust/Cargo
[[ -d "$HOME/.cargo/bin" ]] && export PATH="$HOME/.cargo/bin:$PATH"

# Python/pyenv
if [[ -d "$HOME/.pyenv" ]]; then
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
fi

# pipx
[[ -d "$HOME/.local/bin" ]] && export PATH="$PATH:$HOME/.local/bin"

# npm (user-configured global packages)
[[ -d "$HOME/.npm-global/bin" ]] && export PATH="$HOME/.npm-global/bin:$PATH"

# ─────────────────────────────────────────────────────────────────────────────
#   Dotfiles utilities
# ─────────────────────────────────────────────────────────────────────────────
[[ -d "$DOTFILES_DIR/util-scripts" ]] && export PATH="$DOTFILES_DIR/util-scripts:$PATH"
[[ -d "$DOTFILES_DIR/azcli-scripts" ]] && export PATH="$DOTFILES_DIR/azcli-scripts:$PATH"

# ─────────────────────────────────────────────────────────────────────────────
#   App-specific
# ─────────────────────────────────────────────────────────────────────────────
# LM Studio
[[ -d "$HOME/.lmstudio/bin" ]] && export PATH="$PATH:$HOME/.lmstudio/bin"

# Console Ninja
[[ -d "$HOME/.console-ninja/.bin" ]] && export PATH="$HOME/.console-ninja/.bin:$PATH"

# ─────────────────────────────────────────────────────────────────────────────
#   Homebrew (macOS)
# ─────────────────────────────────────────────────────────────────────────────
if [[ -d "/opt/homebrew/bin" ]]; then
    export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
elif [[ -d "/home/linuxbrew/.linuxbrew/bin" ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

