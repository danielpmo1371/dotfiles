# MCP Configuration for Claude Code

This directory contains MCP (Model Context Protocol) configuration for Claude Code.

## Setup

1. Run the installer:
   ```bash
   ./install.sh --mcp
   ```

2. Edit `mcp-env.local` with your API keys (created from template during install)

3. Start Claude Code with MCP environment:
   ```bash
   # Option 1: Use the helper function (after sourcing shell config)
   claude-mcp

   # Option 2: Manually source environment
   export $(grep -v '^#' ~/repos/dotfiles/config/mcp/mcp-env.local | xargs)
   claude
   ```

## Available MCP Servers

### Memory Server
- **URL**: http://192.168.1.107:8000
- **Purpose**: Long-term memory storage for Claude
- **Running on**: LXC container 107

### Task Master AI
- **Purpose**: Task management and project planning
- **Tool Tiers**:
  - `core` (7 tools) - default
  - `standard` (14 tools)
  - `all` (44+ tools)
- **Configuration**: Edit `TASK_MASTER_TOOLS` in servers.json

## Files

- `servers.json` - **Canonical source of truth** for MCP server definitions (edit this to add/remove servers)
- `mcp-env.template` - Template for API keys
- `mcp-env.local` - Your actual API keys (gitignored)
- `.gitignore` - Excludes local files from git

## How It Works

Claude Code reads MCP servers from `~/.claude.json` (the `mcpServers` key). The installer (`installers/mcp.sh`) merges `servers.json` into `~/.claude.json`, preserving other settings.

**Never edit `~/.claude.json` directly for MCP servers** — run the installer instead.

The installer also supports syncing to Claude Desktop (opt-in with `--desktop` flag).

## Required API Keys

At least one of these is required for Task Master:
- ANTHROPIC_API_KEY (recommended)
- PERPLEXITY_API_KEY (for research features)
- OPENAI_API_KEY
- GOOGLE_API_KEY
- Other providers (see mcp-env.template)

## Troubleshooting

### Memory Server Not Connecting
1. Check if server is running:
   ```bash
   curl -I http://192.168.1.107:8000
   ```
2. Verify systemd service:
   ```bash
   ssh admin@192.168.1.107 "systemctl status mcp-memory"
   ```

### Task Master Not Working
1. Check Node.js and npx are installed
2. Verify API keys are set in mcp-env.local
3. Test with: `npx task-master-ai --help`

### MCP Not Loading in Claude Code
1. Restart Claude Code after configuration
2. Check MCP debug output: `claude --mcp-debug`
3. Verify servers are in `~/.claude.json` under `mcpServers` key (run `./install.sh --mcp` to sync)