# MCP Configuration

This directory contains MCP (Model Context Protocol) server definitions used by both Claude Code and Claude Desktop.

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
- **Type**: HTTP (`http://memory-mcp:8000/mcp`)
- **Purpose**: Long-term memory storage for Claude
- **Note**: `memory-mcp` resolves via `/etc/hosts` to the LXC container running the memory service

### Browser Servers

There are two browser MCP servers for different use cases:

- **browser-local** (stdio) — Runs `@browsermcp/mcp` locally via npx. Use this when the browser is on the same machine as Claude.
- **browser-network** (SSE at `http://10.0.0.102:3002/sse`) — Connects to a BrowserMCP instance running on another machine on the private network. Use this for remote browser automation.

### Other Servers
- **azure-devops** (stdio) — Azure DevOps MCP for work items, repos, and pipelines
- **sequential-thinking** (stdio) — Step-by-step reasoning
- **puppeteer** (stdio) — Browser automation via Puppeteer
- **fetch** (stdio) — HTTP fetch utility

## Claude Desktop Configuration

Claude Code natively supports `"type": "http"` and `"type": "sse"` server definitions. Claude Desktop (v1.1.x) does not -- it only supports stdio servers.

**Known bug:** Claude Desktop v1.1.x ignores the `{ "url": "..." }` format for MCP servers. URL-based servers must be bridged through `mcp-remote` as a stdio wrapper.

For URL-based servers (memory, browser-network), Claude Desktop uses `mcp-remote`:

```json
{
  "memory": {
    "command": "npx",
    "args": ["mcp-remote", "http://memory-mcp:8000/mcp", "--allow-http"]
  },
  "browser-network": {
    "command": "npx",
    "args": ["mcp-remote", "http://10.0.0.102:3002/sse", "--allow-http", "--transport", "sse-only"]
  }
}
```

Key flags:
- `--allow-http` — Required for plain HTTP URLs on the private network (mcp-remote defaults to HTTPS-only)
- `--transport sse-only` — Required for the browser-network SSE endpoint; tells mcp-remote to use SSE transport instead of attempting Streamable HTTP first

The installer handles this translation automatically when run with `--desktop`.

## Files

- `servers.json` — **Canonical source of truth** for MCP server definitions (edit this to add/remove servers)
- `mcp-env.template` — Template for API keys
- `mcp-env.local` — Your actual API keys (gitignored)
- `.gitignore` — Excludes local files from git

## How It Works

Claude Code reads MCP servers from `~/.claude.json` (the `mcpServers` key). The installer (`installers/mcp.sh`) merges `servers.json` into `~/.claude.json`, preserving other settings.

**Never edit `~/.claude.json` directly for MCP servers** — run the installer instead.

The installer also supports syncing to Claude Desktop (opt-in with `--desktop` flag). When syncing to Desktop, it wraps URL-based servers with `mcp-remote` automatically.

## Troubleshooting

### Memory Server Not Connecting
1. Check hostname resolution: `ping memory-mcp`
2. Check if server is running: `curl -I http://memory-mcp:8000`
3. Verify systemd service on the container: `systemctl status mcp-memory`

### Browser Network Server Not Connecting
1. Check the remote host is reachable: `curl -I http://10.0.0.102:3002/sse`
2. Verify BrowserMCP is running on the remote machine

### MCP Not Loading in Claude Code
1. Restart Claude Code after configuration
2. Check MCP debug output: `claude --mcp-debug`
3. Verify servers are in `~/.claude.json` under `mcpServers` key (run `./install.sh --mcp` to sync)

### Claude Desktop MCP Issues
1. Ensure `mcp-remote` is available: `npx mcp-remote --help`
2. Check Claude Desktop logs for connection errors
3. Re-run `./install.sh --mcp --desktop` to regenerate the Desktop config