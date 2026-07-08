# Shared environment variables - works in both bash and zsh
# Source this from .bashrc and .zshrc
# NOTE: Secrets are managed via secrets.sh (native keychain with file fallback)

# ─────────────────────────────────────────────────────────────────────────────
#   XDG Base Directories
# ─────────────────────────────────────────────────────────────────────────────
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"

# ─────────────────────────────────────────────────────────────────────────────
#   Editor
# ─────────────────────────────────────────────────────────────────────────────
export EDITOR="nvim"
export VISUAL="nvim"

# ─────────────────────────────────────────────────────────────────────────────
#   FZF
# ─────────────────────────────────────────────────────────────────────────────
export FZF_COMPLETION_TRIGGER='**'
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'

# ─────────────────────────────────────────────────────────────────────────────
#   AI Tools (non-secret settings)
# ─────────────────────────────────────────────────────────────────────────────
export GEMINI_MODEL="gemini-2.5-flash"
# Quick-query (`q` function in aliases.sh) provider switch. Default Groq = lowest
# time-to-first-token (LPU inference). Provider -> model map lives in aliases.sh.
export AI_PROVIDER="groq"   # groq | gemini | openai | claude
# export AI_MODEL=...        # optional: pin a specific `llm` model id, overrides the provider default

# ─────────────────────────────────────────────────────────────────────────────
#   Azure DevOps
# ─────────────────────────────────────────────────────────────────────────────
export AZDO_ORG="mbie-immigrationnz-prod"
export AZURE_DEVOPS_PAT

# ─────────────────────────────────────────────────────────────────────────────
#   Custom tools
# ─────────────────────────────────────────────────────────────────────────────
export TALKING_AGENT=1
export TTALK_WORD_COUNT=20

# ─────────────────────────────────────────────────────────────────────────────
#   Colors
# ─────────────────────────────────────────────────────────────────────────────
export LS_COLORS="di=01;34:ln=01;36:so=01;35:pi=40;33:ex=01;32:bd=40;33;01:cd=40;33;01:su=37;41:sg=30;43:tw=30;42:ow=34;42:st=37;44:fi=00"

