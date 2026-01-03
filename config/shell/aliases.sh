# Shared shell aliases - works in both bash and zsh
# Source this from .bashrc and .zshrc

# ─────────────────────────────────────────────────────────────────────────────
#   Navigation
# ─────────────────────────────────────────────────────────────────────────────
alias root='cd ~/repos/'
alias ..='cd ..'
alias ...='cd ../..'

# ─────────────────────────────────────────────────────────────────────────────
#   Editor & Config
# ─────────────────────────────────────────────────────────────────────────────
alias n='nvim'
alias fvim='nvim "$(fzf)"'
alias nz='nvim $(fzf)'
alias setup-vim='nvim ~/.config/nvim/init.lua'
alias setup-alias="nvim $DOTFILES_DIR/config/shell/aliases.sh"
alias setup-tmux='nvim ~/.tmux.conf'
alias setup-ghostty='nvim ~/.config/ghostty/config'
alias setup-claude='nvim ~/.claude/CLAUDE.md'
alias re-tmux='tmux source-file ~/.tmux.conf'
alias dot='z dot'

# ─────────────────────────────────────────────────────────────────────────────
#   Git
# ─────────────────────────────────────────────────────────────────────────────
alias lz='lazygit'
alias gs='git status'
alias cm='git cm'
alias psh='git push'
alias lg='git log --pretty'
alias flg="git log --oneline | fzf --ansi --preview 'git show --color=always {1}' | awk '{print \$1}' | xargs git show"

# Git show with syntax highlighting (uses delta > bat > git native)
gshow() {
    local ref="${1:-HEAD}"
    if command -v delta &>/dev/null; then
        git show --color=always "$ref" | delta
    elif command -v bat &>/dev/null; then
        git show --color=always "$ref" | bat --style=plain --paging=never
    else
        git show --color=always "$ref"
    fi
}
alias gsh='gshow'

# ─────────────────────────────────────────────────────────────────────────────
#   AI Tools
# ─────────────────────────────────────────────────────────────────────────────
alias cc='claude -p'
alias gg='gemini -p'
alias g='gemini --model gemini-2.5-flash --prompt'
alias update-claude='sudo npm i -g @anthropic-ai/claude-code'

# ─────────────────────────────────────────────────────────────────────────────
#   Terraform / DevOps
# ─────────────────────────────────────────────────────────────────────────────
alias tf='terraform'

# ─────────────────────────────────────────────────────────────────────────────
#   Azure CLI
# ─────────────────────────────────────────────────────────────────────────────
alias az-show='az account show'
alias azl='az account list | grep name'
alias az-list='az account list | grep name'
alias azsetmbdev='az account set --name "INZ_TDS_DEV"'
alias azsetmbsit='az account set --name "INZ_TDS_SIT"'

# ─────────────────────────────────────────────────────────────────────────────
#   File listing (uses lsd if available, falls back to ls)
# ─────────────────────────────────────────────────────────────────────────────
if command -v lsd &> /dev/null; then
    alias ls='lsd'
    alias la='lsd -la'
    alias ll='lsd -l'
else
    alias ls='ls -G'
    alias la='ls -la'
    alias ll='ls -l'
fi

# ─────────────────────────────────────────────────────────────────────────────
#   Utilities
# ─────────────────────────────────────────────────────────────────────────────
alias cls='clear'
alias myip='curl -s ifconfig.me'
alias todo='nvim ~/todo/todo.list'
alias start='tmux new-session -A -n dan'
alias awake='caffeinate -d'  # Keep Mac awake (display on, system won't sleep)
alias node="/home/linuxbrew/.linuxbrew/Cellar/node/25.2.1/bin/node"
alias nvim="/home/linuxbrew/.linuxbrew/Cellar/neovim/0.11.5_1/bin/nvim"


# ─────────────────────────────────────────────────────────────────────────────
#   FZF + Ripgrep integration
# ─────────────────────────────────────────────────────────────────────────────
alias rgv='rg --line-number --color=always "$1" | fzf --ansi --delimiter : --preview "bat --color=always {1} --highlight-line {2}" | awk -F: '"'"'{ print "+"$2" "$1 }'"'"' | xargs nvim'

# ─────────────────────────────────────────────────────────────────────────────
#   Python
# ─────────────────────────────────────────────────────────────────────────────
alias python=python3
alias pip=pip3

# ─────────────────────────────────────────────────────────────────────────────
#   Image Display (chafa)
# ─────────────────────────────────────────────────────────────────────────────
# Manual image display - auto-display disabled in tmux due to compatibility issues
# if command -v chafa &>/dev/null; then
#     # Show image with automatic format detection and size limit (max 1/4 terminal width)
#     show-img() {
#         local max_width=$(($(tput cols) / 4))
#
#         if [[ -n "$TMUX" ]]; then
#             # In tmux: use symbols for stability (or try passthrough at your own risk)
#             chafa -f symbols --size="${max_width}x" "$@"
#         else
#             # Outside tmux: use high-quality graphics
#             chafa --size="${max_width}x" "$@"
#         fi
#     }
#
#     # Show startup image
#     show-start() {
#         if [[ -f "$DOTFILES_DIR/images/start.png" ]]; then
#             show-img "$DOTFILES_DIR/images/start.png"
#         else
#             echo "Startup image not found: $DOTFILES_DIR/images/start.png"
#         fi
#     }
# fi
