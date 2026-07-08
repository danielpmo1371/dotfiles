# Secrets management - works in both bash and zsh
# Uses nuvemlabs/secrets library for cross-platform OS-native secret storage
#
# Usage:
#   secret KEY              - Get a secret on-demand
#   secret_set KEY VALUE    - Store a secret
#   secret_list             - List all stored keys
#   secret_delete KEY       - Remove a secret

# Source the secrets library (nuvemlabs/secrets)
SECRETS_LIB="${HOME}/.local/lib/secrets/secrets.sh"
if [[ -f "$SECRETS_LIB" ]]; then
    export SECRETS_SERVICE="dotfiles"
    source "$SECRETS_LIB"

    # Source migration logic (dotfiles-specific, not part of nuvemlabs/secrets)
    if [[ -n "$DOTFILES_DIR" && -f "$DOTFILES_DIR/lib/secrets.sh" ]]; then
        source "$DOTFILES_DIR/lib/secrets.sh"
    fi

    # Auto-migrate from ~/.accessTokens on first shell load
    __secrets_auto_migrate

    # ─────────────────────────────────────────────────────────────────────────
    #   Export secrets as environment variables
    # ─────────────────────────────────────────────────────────────────────────
    export AZDO_PAT="$(secret AZDO_PAT 2>/dev/null)"
    export AZURE_DEVOPS_PAT="$AZDO_PAT"
    export AZURE_DEVOPS_EXT_PAT="$AZDO_PAT"
    export ADO_MCP_AUTH_TOKEN="$AZDO_PAT"
    # export CLAUDE_CODE_OAUTH_TOKEN="$(secret CLAUDE_CODE_OAUTH_TOKEN 2>/dev/null)"

    # Groq key for the `llm` quick-query (q function). The llm-groq model classes
    # declare key_env_var="GROQ_API_KEY" (the var llm reads on the prompt path), while
    # an older helper path reads LLM_GROQ_KEY — so export both to cover every code path.
    # Keeps the key in the OS keychain instead of llm's plaintext keys.json.
    __groq_key="$(secret GROQ_API_KEY 2>/dev/null)"
    export GROQ_API_KEY="$__groq_key"
    export LLM_GROQ_KEY="$__groq_key"
    unset __groq_key
fi
