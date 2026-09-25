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
#   Ripgrep
# ─────────────────────────────────────────────────────────────────────────────
# rg only reads a config file when this is set (symlinked by --config-dirs)
export RIPGREP_CONFIG_PATH="$XDG_CONFIG_HOME/ripgrep/config"

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
# Output stage for `q`. `pretty` renders the finished answer as markdown (glow),
# so bold/bullets/code display as formatting instead of literal `*` markers.
# `raw` streams it line by line through bat instead — lowest time-to-first-token,
# markers stay visible. Per-call override: `Q_RENDER=raw q "..."`.
export Q_RENDER="pretty"    # pretty | raw
# Pager for `q` output: -R keeps colour, -F skips paging when it fits one screen,
# -X leaves the text in the scrollback instead of clearing on exit.
export Q_PAGER="less -RFX"
# Word-wrap column used only when neither $COLUMNS nor tput can report a width
# (non-interactive shell with no terminal), matching glow's own default.
export Q_FALLBACK_WIDTH=80

# ─────────────────────────────────────────────────────────────────────────────
#   Azure DevOps
# ─────────────────────────────────────────────────────────────────────────────
# AZDO_ORG is machine/employer-specific — set via `secret_set AZDO_ORG "<org-slug>"`
# (config/shell/secrets.sh exports it from the OS keychain, same as AZDO_PAT).
export AZDO_ORG
export AZURE_DEVOPS_PAT

# ─────────────────────────────────────────────────────────────────────────────
#   Custom tools
# ─────────────────────────────────────────────────────────────────────────────
export TALKING_AGENT=1
export TTALK_WORD_COUNT=20
# ttalk Piper voice: default (en_GB-cori-high) lives in util-scripts/ttalk. Models are
# downloaded from huggingface.co/rhasspy/piper-voices, not tracked; missing → espeak-ng.
# export PIPER_VOICE="$XDG_DATA_HOME/piper/voices/en_GB-jenny_dioco-medium.onnx"  # optional override

# ─────────────────────────────────────────────────────────────────────────────
#   Colors
# ─────────────────────────────────────────────────────────────────────────────
export LS_COLORS="di=01;34:ln=01;36:so=01;35:pi=40;33:ex=01;32:bd=40;33;01:cd=40;33;01:su=37;41:sg=30;43:tw=30;42:ow=34;42:st=37;44:fi=00"

