# Secrets management - works in both bash and zsh
# Provides lazy loading of secrets from native OS secret stores
#
# Usage:
#   secret KEY              - Get a secret on-demand
#   secret_set KEY VALUE    - Store a secret
#   secret_list             - List all stored keys
#   secret_delete KEY       - Remove a secret

# Source the core secrets library
if [[ -n "$DOTFILES_DIR" && -f "$DOTFILES_DIR/lib/secrets.sh" ]]; then
    source "$DOTFILES_DIR/lib/secrets.sh"

    # Auto-migrate from ~/.accessTokens on first shell load
    __secrets_auto_migrate
fi

# ─────────────────────────────────────────────────────────────────────────────
#   Export secrets as environment variables
# ─────────────────────────────────────────────────────────────────────────────
export AZDO_PAT="$(secret AZDO_PAT 2>/dev/null)"
export AZURE_DEVOPS_PAT="$(secret AZDO_PAT 2>/dev/null)"
export ADO_MCP_AUTH_TOKEN="$(secret AZDO_PAT 2>/dev/null)"
