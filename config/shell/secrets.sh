# Secrets management - works in both bash and zsh
# Uses nuvemlabs/secrets library for cross-platform OS-native secret storage
#
# Usage:
#   secret KEY              - Get a secret on-demand
#   secret_set KEY VALUE    - Store a secret
#   secret_list             - List all stored keys
#   secret_delete KEY       - Remove a secret
#   secret_unlock           - Unlock the macOS login keychain when `secret` reports it locked

# Source the secrets library (nuvemlabs/secrets)
SECRETS_LIB="${HOME}/.local/lib/secrets/secrets.sh"
if [[ -f "$SECRETS_LIB" ]]; then
    export SECRETS_SERVICE="dotfiles"
    # Self-declaration: tells secrets-doctor (nuvemlabs/secrets CLI) which file
    # maps store keys to env vars, so it works from any child process.
    [[ -n "$DOTFILES_DIR" ]] && export SECRETS_EXPORTS_FILE="$DOTFILES_DIR/config/shell/secrets.sh"
    # A locked login keychain makes `security` exit 36 (interaction not allowed)
    # when no GUI prompt can be shown — e.g. a tmux server running outside the
    # Aqua session — so every export below would silently come back empty. The
    # library prompts once on the TTY at shell start. Shells without a TTY
    # (scripts, MCP spawns) are left alone: `secret` then returns 2 with a
    # "run: secret_unlock" hint and secrets-doctor shows STORE=locked.
    export SECRETS_AUTO_UNLOCK=1
    source "$SECRETS_LIB"

    # Source migration logic (dotfiles-specific, not part of nuvemlabs/secrets)
    if [[ -n "$DOTFILES_DIR" && -f "$DOTFILES_DIR/lib/secrets.sh" ]]; then
        source "$DOTFILES_DIR/lib/secrets.sh"
    fi

    # A locked libsecret keyring makes every `secret-tool lookup` below wait on
    # an unlock prompt (gcr-prompter); if the prompt can't be shown, shell
    # startup hangs forever. SearchItems never prompts and returns our items as
    # (unlocked, locked) path arrays; skip loading unless the locked array is
    # empty (reply ends in " 0"). This checks the items we are about to read;
    # a Locked check on the `default` alias still let boot-time shells through
    # to hang.
    if [[ "$__SECRETS_BACKEND" == "libsecret" ]] && ! timeout 2 busctl --user call \
            org.freedesktop.secrets /org/freedesktop/secrets \
            org.freedesktop.Secret.Service SearchItems 'a{ss}' 1 service "$SECRETS_SERVICE" \
            2>/dev/null | grep -qE '^aoao .* 0$'; then
        echo "[secrets] keyring locked or unavailable — secrets not loaded (unlock it, then: exec \$SHELL)" >&2
        return 0
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
    export AZDO_ORG="$(secret AZDO_ORG 2>/dev/null)"
    # AZDO_ORG_URL/AZDO_PROJECT back the "secret:..." refs in config/mcp/servers.json
    # (installers/mcp.sh rewrites those to ${VAR}; Claude Code expands them from this
    # shell's environment when it spawns the azure-devops MCP server).
    export AZDO_ORG_URL="$(secret AZDO_ORG_URL 2>/dev/null)"
    export AZDO_PROJECT="$(secret AZDO_PROJECT 2>/dev/null)"

    # config/claude/hooks/pipeline-guard.sh fails closed (blocks ALL pipeline
    # triggers) when these are unset — see the comment at the top of that file.
    export PIPELINE_GUARD_TERRAFORM_ID="$(secret PIPELINE_GUARD_TERRAFORM_ID 2>/dev/null)"
    export PIPELINE_GUARD_TERRAFORM_APPLY_STAGE="$(secret PIPELINE_GUARD_TERRAFORM_APPLY_STAGE 2>/dev/null)"
    # export CLAUDE_CODE_OAUTH_TOKEN="$(secret CLAUDE_CODE_OAUTH_TOKEN 2>/dev/null)"

    # mcp-memory-service requires X-API-Key on every route. Read by the ${VAR}
    # header in config/mcp/servers.json and by the memory hooks' MemoryClient
    # (see config/claude/hooks/patches/).
    export MEMORY_MCP_API_KEY="$(secret MEMORY_MCP_API_KEY 2>/dev/null)"

    # Groq key for the `llm` quick-query (q function). The llm-groq model classes
    # declare key_env_var="GROQ_API_KEY" (the var llm reads on the prompt path), while
    # an older helper path reads LLM_GROQ_KEY — so export both to cover every code path.
    # Keeps the key in the OS keychain instead of llm's plaintext keys.json.
    __groq_key="$(secret GROQ_API_KEY 2>/dev/null)"
    export GROQ_API_KEY="$__groq_key"
    export LLM_GROQ_KEY="$__groq_key"
    unset __groq_key
    # ntfy topic URL for util-scripts/ntfy-send (phone notifications). The URL is
    # the only access control on ntfy.sh, so it lives in the keychain, not the repo.
    export NTFY_TOPIC_URL="$(secret NTFY_TOPIC_URL 2>/dev/null)"
fi
