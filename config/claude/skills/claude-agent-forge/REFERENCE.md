# Claude Agent Forge - Technical Reference

## Table of Contents

- [Python SDK Complete API](#python-sdk-complete-api)
- [TypeScript SDK Complete API](#typescript-sdk-complete-api)
- [Subagent Configuration](#subagent-configuration)
- [Hooks Reference](#hooks-reference)
- [MCP Integration](#mcp-integration)
- [Error Handling](#error-handling)
- [Authentication](#authentication)

---

## Python SDK Complete API

### Installation

```bash
pip install claude-agent-sdk
```

**Requirements:** Python 3.10+, Node.js 18+ (for CLI)

### ClaudeAgentOptions

```python
from claude_agent_sdk import ClaudeAgentOptions

options = ClaudeAgentOptions(
    system_prompt: str = None,           # System prompt for Claude
    max_turns: int = None,               # Maximum conversation turns
    allowed_tools: List[str] = None,     # Tool allowlist
    permission_mode: str = None,         # 'acceptEdits', 'default', etc.
    cwd: str | Path = None,              # Working directory
    cli_path: str = None,                # Custom Claude CLI path
    mcp_servers: Dict[str, ...] = None,  # MCP server configurations
    hooks: Dict[str, List] = None,       # Hook handlers
)
```

### query() Function

Simple async iterator for stateless queries:

```python
from claude_agent_sdk import query, ClaudeAgentOptions, AssistantMessage, TextBlock

options = ClaudeAgentOptions(
    system_prompt="You are a code assistant",
    allowed_tools=["Read", "Write", "Bash"],
    permission_mode='acceptEdits',
    cwd="/path/to/project"
)

async for message in query(prompt="Refactor main.py", options=options):
    if isinstance(message, AssistantMessage):
        for block in message.content:
            if isinstance(block, TextBlock):
                print(block.text)
```

### ClaudeSDKClient

Stateful client for bidirectional conversations:

```python
from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions

async with ClaudeSDKClient(options=options) as client:
    await client.query("Your prompt here")
    async for msg in client.receive_response():
        print(msg)

    # Continue conversation
    await client.query("Follow-up question")
    async for msg in client.receive_response():
        print(msg)
```

### Custom Tools with @tool Decorator

```python
from claude_agent_sdk import tool, create_sdk_mcp_server

@tool(
    name="search_codebase",
    description="Search for patterns in the codebase",
    parameters={"pattern": str, "file_type": str}
)
async def search_codebase(args):
    pattern = args["pattern"]
    file_type = args.get("file_type", "*")
    # Implementation
    results = do_search(pattern, file_type)
    return {
        "content": [
            {"type": "text", "text": f"Found {len(results)} matches"}
        ]
    }

# Create MCP server
server = create_sdk_mcp_server(
    name="codebase-tools",
    version="1.0.0",
    tools=[search_codebase]
)

# Use in options
options = ClaudeAgentOptions(
    mcp_servers={"codebase": server},
    allowed_tools=["mcp__codebase__search_codebase"]
)
```

### Message Types

```python
from claude_agent_sdk import (
    AssistantMessage,    # Claude's responses
    UserMessage,         # User inputs
    SystemMessage,       # System messages
    ResultMessage,       # Tool results
    TextBlock,           # Text content
    ToolUseBlock,        # Tool invocations
    ToolResultBlock      # Tool outputs
)
```

---

## TypeScript SDK Complete API

### Installation

```bash
npm install @anthropic-ai/claude-agent-sdk
```

**Requirements:** Node.js 18+

### Basic Usage

```typescript
import { query, ClaudeAgentOptions } from '@anthropic-ai/claude-agent-sdk';

const options: ClaudeAgentOptions = {
  systemPrompt: "You are a helpful assistant",
  allowedTools: ["Read", "Write", "Bash"],
  permissionMode: 'acceptEdits',
  cwd: '/path/to/project'
};

for await (const message of query("Fix the bug", options)) {
  console.log(message);
}
```

### Stateful Client

```typescript
import { ClaudeSDKClient } from '@anthropic-ai/claude-agent-sdk';

const client = new ClaudeSDKClient(options);
await client.connect();

await client.query("Initial prompt");
for await (const msg of client.receiveResponse()) {
  console.log(msg);
}

await client.disconnect();
```

---

## Subagent Configuration

### Complete YAML Frontmatter

```yaml
---
# Required fields
name: agent-name                    # Max 64 chars, lowercase + hyphens
description: What it does. When to use it.  # Max 1024 chars

# Tool access (choose one approach)
tools: Read, Grep, Glob, Bash       # Allowlist (recommended)
# OR
disallowedTools: Write, Edit        # Denylist

# Model selection
model: sonnet                       # sonnet, opus, haiku, or inherit

# Permission handling
permissionMode: default             # default, acceptEdits, bypassPermissions, plan

# Skill auto-loading
skills:                             # Load these skills automatically
  - code-review
  - testing

# Hooks (subagent-specific)
hooks:
  PreToolUse:
    - matcher: Bash
      command: "echo 'About to run bash'"
---

Your system prompt goes here in the markdown body.
```

### Model Selection Guide

| Model | Use Case | Cost | Speed |
|-------|----------|------|-------|
| `haiku` | Simple tasks, high volume | Low | Fast |
| `sonnet` | Balanced tasks (default) | Medium | Medium |
| `opus` | Complex reasoning, critical tasks | High | Slower |
| `inherit` | Match parent conversation | Varies | Varies |

### Permission Modes

| Mode | Behavior |
|------|----------|
| `default` | Prompts for all write operations |
| `acceptEdits` | Auto-accepts file modifications |
| `bypassPermissions` | Skips all permission checks (dangerous) |
| `plan` | Planning mode, no writes allowed |

---

## Hooks Reference

### Hook Types

| Hook | Trigger | Use Case |
|------|---------|----------|
| `PreToolUse` | Before tool execution | Validation, logging |
| `PostToolUse` | After tool execution | Cleanup, verification |
| `SubagentStop` | When subagent completes | Handoff suggestions |
| `Stop` | When main agent stops | Summary, next steps |

### Python Hook Example

```python
from claude_agent_sdk import ClaudeAgentOptions, HookMatcher

async def validate_bash(input_data, tool_use_id, context):
    if input_data["tool_name"] != "Bash":
        return {}

    command = input_data["tool_input"].get("command", "")

    # Block dangerous commands
    dangerous = ["rm -rf", "sudo", "chmod 777"]
    for pattern in dangerous:
        if pattern in command:
            return {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": f"Blocked: {pattern}"
                }
            }
    return {}

options = ClaudeAgentOptions(
    hooks={
        "PreToolUse": [
            HookMatcher(matcher="Bash", hooks=[validate_bash])
        ]
    }
)
```

### Subagent Hook Configuration

```yaml
---
name: safe-executor
description: Executes code with safety checks
hooks:
  PreToolUse:
    - matcher: Bash
      command: "python /path/to/validate.py"
  PostToolUse:
    - matcher: Write
      command: "python /path/to/verify.py"
---
```

---

## MCP Integration

### SDK MCP Server (In-Process)

```python
from claude_agent_sdk import tool, create_sdk_mcp_server

@tool("get_weather", "Get weather for a city", {"city": str})
async def get_weather(args):
    city = args["city"]
    # Fetch weather data
    return {"content": [{"type": "text", "text": f"Weather in {city}: Sunny"}]}

server = create_sdk_mcp_server(
    name="weather",
    version="1.0.0",
    tools=[get_weather]
)

options = ClaudeAgentOptions(
    mcp_servers={"weather": server},
    allowed_tools=["mcp__weather__get_weather"]
)
```

### External MCP Server

```python
options = ClaudeAgentOptions(
    mcp_servers={
        "github": {
            "type": "stdio",
            "command": "npx",
            "args": ["-y", "@modelcontextprotocol/server-github"]
        }
    }
)
```

### Mixed MCP Configuration

```python
options = ClaudeAgentOptions(
    mcp_servers={
        "internal": sdk_server,           # In-process
        "external": {"type": "stdio", ...} # Subprocess
    }
)
```

---

## Error Handling

### Python Exception Types

```python
from claude_agent_sdk import (
    ClaudeSDKError,        # Base error
    CLINotFoundError,      # Claude Code CLI not installed
    CLIConnectionError,    # Connection failed
    ProcessError,          # Process terminated abnormally
    CLIJSONDecodeError     # Response parsing failed
)

try:
    async for message in query(prompt="Hello", options=options):
        pass
except CLINotFoundError:
    print("Install Claude Code: curl -fsSL https://claude.ai/install.sh | bash")
except CLIConnectionError as e:
    print(f"Connection failed: {e}")
except ProcessError as e:
    print(f"Process exited with code {e.exit_code}")
except CLIJSONDecodeError as e:
    print(f"Invalid response: {e}")
except ClaudeSDKError as e:
    print(f"SDK error: {e}")
```

---

## Authentication

### Environment Variables

```bash
# Primary: Anthropic API
export ANTHROPIC_API_KEY="sk-ant-..."

# Alternative: AWS Bedrock
export CLAUDE_CODE_USE_BEDROCK=1
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."

# Alternative: Google Vertex AI
export CLAUDE_CODE_USE_VERTEX=1
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/credentials.json"
```

### Custom CLI Path

```python
options = ClaudeAgentOptions(
    cli_path="/custom/path/to/claude"
)
```

---

## Best Practices Summary

### Agent Design

1. **Start simple** - Single LLM calls before multi-agent systems
2. **Clear interfaces** - Document tool inputs/outputs explicitly
3. **Verification loops** - Add feedback after actions
4. **Human oversight** - Approval gates between autonomous steps

### Tool Configuration

1. **Explicit allowlists** - Never rely on default tool inheritance
2. **Least privilege** - Grant minimum required tools
3. **Separate read/write** - Research agents shouldn't write

### Performance

1. **Use haiku for simple tasks** - Lower cost, faster
2. **Batch operations** - Group related tool calls
3. **Context management** - Use compaction for long conversations

### Security

1. **Validate inputs** - Use hooks to check tool parameters
2. **Sandbox execution** - Test agents in isolated environments
3. **Audit logging** - Track all tool invocations
4. **No credentials in prompts** - Use environment variables
