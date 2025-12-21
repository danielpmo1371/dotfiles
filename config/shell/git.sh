# Shared git configuration - works in both bash and zsh
# Source this from .bashrc and .zshrc

# ─────────────────────────────────────────────────────────────────────────────
#   Git aliases (configured globally, idempotent)
# ─────────────────────────────────────────────────────────────────────────────
git config --global alias.co checkout 2>/dev/null
git config --global alias.s status 2>/dev/null
git config --global alias.ds "diff --staged" 2>/dev/null
git config --global alias.rs "restore --staged" 2>/dev/null
git config --global alias.r "restore" 2>/dev/null
git config --global alias.cm "commit -m" 2>/dev/null
git config --global alias.ca "commit --amend" 2>/dev/null
git config --global alias.lg "log --oneline --graph --decorate" 2>/dev/null

# ─────────────────────────────────────────────────────────────────────────────
#   Git settings
# ─────────────────────────────────────────────────────────────────────────────
# Default branch name
git config --global init.defaultBranch main 2>/dev/null

# Better diff
git config --global diff.algorithm histogram 2>/dev/null

# Auto-setup remote tracking
git config --global push.autoSetupRemote true 2>/dev/null

# WSL: convert CRLF to LF on commit (safe on macOS too)
git config --global core.autocrlf input 2>/dev/null
