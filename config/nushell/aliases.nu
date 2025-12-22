# ~/.config/nushell/aliases.nu
# Aliases - mirrors config/shell/aliases.sh

# ─────────────────────────────────────────────────────────────────────────────
#   Navigation
# ─────────────────────────────────────────────────────────────────────────────
alias root = cd ~/repos/
alias .. = cd ..
alias ... = cd ../..

# ─────────────────────────────────────────────────────────────────────────────
#   Editor & Config
# ─────────────────────────────────────────────────────────────────────────────
alias n = nvim
alias setup-vim = nvim ~/.config/nvim/init.lua
alias setup-nu = nvim ~/.config/nushell/config.nu
alias setup = nvim ~/.config/nushell/config.nu

# reterm - nushell can't reload config, so just exec a new shell
def reterm [] { exec nu }
alias setup-alias = nvim ($env.DOTFILES_DIR | path join "config" "shell" "aliases.sh")
alias setup-tmux = nvim ~/.tmux.conf
alias setup-ghostty = nvim ~/.config/ghostty/config
alias setup-claude = nvim ~/.claude/CLAUDE.md
alias re-tmux = tmux source-file ~/.tmux.conf
alias dot = z dot

# fzf + nvim (nushell style)
def fvim [] {
    let file = (fzf | str trim)
    if ($file | is-not-empty) { nvim $file }
}

alias nz = fvim

# ─────────────────────────────────────────────────────────────────────────────
#   Git
# ─────────────────────────────────────────────────────────────────────────────
alias lz = lazygit
alias gs = git status
alias gsh = git show HEAD
alias cm = git commit -m
alias psh = git push
alias lg = git log --oneline --graph --decorate

# fzf git log
def flg [] {
    let commit = (git log --oneline | fzf --ansi --preview 'git show --color=always {1}' | split row " " | first)
    if ($commit | is-not-empty) { git show $commit }
}

# ─────────────────────────────────────────────────────────────────────────────
#   AI Tools
# ─────────────────────────────────────────────────────────────────────────────
alias cc = claude -p
alias gg = gemini -p
def g [...args] { gemini --model gemini-2.5-flash --prompt ...$args }
alias update-claude = sudo npm i -g @anthropic-ai/claude-code

# ─────────────────────────────────────────────────────────────────────────────
#   Terraform / DevOps
# ─────────────────────────────────────────────────────────────────────────────
alias tf = terraform

# ─────────────────────────────────────────────────────────────────────────────
#   Azure CLI
# ─────────────────────────────────────────────────────────────────────────────
alias az-show = az account show
alias azsetmbdev = az account set --name "INZ_TDS_DEV"
alias azsetmbsit = az account set --name "INZ_TDS_SIT"

# Better az list with nushell's structured output
def azl [] { az account list | from json | select name isDefault | sort-by isDefault -r }
def az-list [] { azl }

# ─────────────────────────────────────────────────────────────────────────────
#   File listing (nushell has great built-in ls)
# ─────────────────────────────────────────────────────────────────────────────
# ls is already great in nushell, but add convenience aliases
alias la = ls -a
alias ll = ls -l

# ─────────────────────────────────────────────────────────────────────────────
#   Utilities
# ─────────────────────────────────────────────────────────────────────────────
alias cls = clear
def myip [] { http get https://ifconfig.me | str trim }
alias todo = nvim ~/todo/todo.list
alias start = tmux new-session -A -s main

# ─────────────────────────────────────────────────────────────────────────────
#   Tmux
# ─────────────────────────────────────────────────────────────────────────────
alias ta = tmux attach -t
alias tl = tmux list-sessions
alias tn = tmux new-session -s
alias tk = tmux kill-session -t

# ─────────────────────────────────────────────────────────────────────────────
#   FZF + Ripgrep integration
# ─────────────────────────────────────────────────────────────────────────────
def rgv [pattern: string] {
    let result = (rg --line-number --color=always $pattern
        | fzf --ansi --delimiter ':' --preview 'bat --color=always {1} --highlight-line {2}'
        | str trim)
    if ($result | is-not-empty) {
        let parts = ($result | split column ":" file line | first)
        nvim $"+($parts.line)" $parts.file
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#   Nushell-native helpers (leverage structured data)
# ─────────────────────────────────────────────────────────────────────────────

# Better ps
def psg [pattern: string] { ps | where name =~ $pattern }

# Find large files
def big [size: filesize = 100mb] { ls -a | where size > $size | sort-by size -r }

# Git status as table
def gst [] {
    git status --porcelain
    | lines
    | parse "{status} {file}"
    | update status { |row|
        match $row.status {
            "M" => "modified"
            "A" => "added"
            "D" => "deleted"
            "??" => "untracked"
            _ => $row.status
        }
    }
}

# Docker containers as table
def dps [] { docker ps --format json | lines | each { from json } }

# Quick JSON exploration
def jq-explore [file: string] { open $file | explore }

# ─────────────────────────────────────────────────────────────────────────────
#   Python
# ─────────────────────────────────────────────────────────────────────────────
alias python = python3
alias pip = pip3
