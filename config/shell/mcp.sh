#!/bin/bash
# MCP environment configuration loader
# Sources MCP environment variables if the config file exists

# Check if mcp-env.local exists and source it
MCP_ENV_FILE="$HOME/repos/dotfiles/config/mcp/mcp-env.local"

if [ -f "$MCP_ENV_FILE" ]; then
    # Export all non-comment lines as environment variables
    set -a  # Mark all new variables for export
    source <(grep -v '^#' "$MCP_ENV_FILE" | grep -v '^\s*$')
    set +a  # Turn off auto-export

    # Optional: Show which MCP servers are configured
    if [ -n "$SHOW_MCP_STATUS" ]; then
        echo "MCP environment loaded from $MCP_ENV_FILE"
        [ -n "$ANTHROPIC_API_KEY" ] && echo "  ✓ Anthropic API configured"
        [ -n "$PERPLEXITY_API_KEY" ] && echo "  ✓ Perplexity API configured"
        [ -n "$OPENAI_API_KEY" ] && echo "  ✓ OpenAI API configured"
    fi
fi

# Function to quickly start Claude Code with MCP
claude-mcp() {
    if [ -f "$MCP_ENV_FILE" ]; then
        # Source environment and start Claude
        export $(grep -v '^#' "$MCP_ENV_FILE" | xargs)
        claude "$@"
    else
        echo "Warning: MCP environment file not found at $MCP_ENV_FILE"
        echo "Run './install.sh --mcp' from dotfiles directory to set up MCP"
        claude "$@"
    fi
}