---
name: claude-agent-forge
description: Create, analyze, and review Claude agents using official Anthropic best practices. Use when building agents with the Agent SDK, creating subagents, designing multi-agent systems, or reviewing agent quality. Covers Python/TypeScript SDK, subagents, and agentic patterns.
allowed-tools: Read, Grep, Glob, Bash, Write, Edit, WebFetch, WebSearch
---

# Claude Agent Forge

## Role

You are an **Agent Engineering Expert** specializing in creating, analyzing, and reviewing Claude agents. You apply official Anthropic best practices and help users build production-ready agents using the Claude Agent SDK, subagents, and skills.

## Quick Start

### What Type of Agent?

| Type | Use Case | Location |
|------|----------|----------|
| **Subagent** | Task-specific assistant within Claude Code | `.claude/agents/` or `~/.claude/agents/` |
| **SDK Agent** | Programmatic agent in Python/TypeScript | Application code |
| **Skill** | Reusable domain expertise for any agent | `.claude/skills/` or `~/.claude/settings/skills/` |

### Creating a Subagent (5 min)

```yaml
# .claude/agents/code-reviewer.md
---
name: code-reviewer
description: Reviews code for quality, security, and best practices. Use after code changes or before commits.
tools: Read, Grep, Glob
model: sonnet
---

You are a code review specialist. Analyze code for:
1. Security vulnerabilities
2. Performance issues
3. Code style consistency
4. Potential bugs

Provide specific, actionable feedback with file:line references.
```

### Creating an SDK Agent (Python)

```python
from claude_agent_sdk import query, ClaudeAgentOptions

options = ClaudeAgentOptions(
    system_prompt="You are a helpful coding assistant",
    allowed_tools=["Read", "Write", "Bash"],
    permission_mode='acceptEdits'
)

async for message in query(prompt="Fix the bug in main.py", options=options):
    print(message)
```

## Agent Architecture Principles

### The Agent Loop

All Claude agents follow this feedback loop:

```
Gather Context → Take Action → Verify Work → Repeat
```

Design agents with tools that support each phase:
- **Context**: Read, Grep, Glob, WebSearch, MCP integrations
- **Action**: Write, Edit, Bash, custom tools
- **Verification**: Linting, tests, visual feedback, LLM-as-judge

### Workflows vs Agents

| Workflows | Agents |
|-----------|--------|
| Predefined code paths | Dynamic, autonomous decisions |
| Deterministic steps | Open-ended problem solving |
| Lower cost, predictable | Higher cost, flexible |
| Use for: known processes | Use for: exploration, complex tasks |

**Start simple**: Most tasks don't need full agents. Try single LLM calls with good prompts first.

## Subagent Reference

### YAML Frontmatter Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Max 64 chars, lowercase + hyphens |
| `description` | Yes | WHAT it does + WHEN to use it |
| `tools` | No | Allowlist: `Read, Grep, Glob, Bash, Write, Edit` |
| `disallowedTools` | No | Denylist (alternative to allowlist) |
| `model` | No | `sonnet`, `opus`, `haiku`, or `inherit` |
| `permissionMode` | No | `default`, `acceptEdits`, `bypassPermissions`, `plan` |
| `skills` | No | Auto-load specific skills |

### Storage Locations

- **Project**: `.claude/agents/` (checked into repo)
- **User**: `~/.claude/agents/` (personal, all projects)
- **Priority**: Project agents override user agents with same name

### Tool Configuration Best Practices

```yaml
# Restrictive (recommended for most agents)
tools: Read, Grep, Glob

# Read-heavy (research agents)
tools: Read, Grep, Glob, WebSearch, WebFetch

# Full write access (implementation agents)
tools: Read, Write, Edit, Bash, Grep, Glob
```

**Warning**: Omitting `tools` grants ALL tools including MCP. Always whitelist explicitly.

## SDK Reference

### Python SDK

**Installation:**
```bash
pip install claude-agent-sdk  # Requires Python 3.10+
```

**Core Methods:**
- `query()` - Simple async queries (stateless)
- `ClaudeSDKClient` - Bidirectional conversations (stateful)

**Custom Tools:**
```python
from claude_agent_sdk import tool, create_sdk_mcp_server

@tool("analyze", "Analyze code quality", {"path": str})
async def analyze_code(args):
    # Tool implementation
    return {"content": [{"type": "text", "text": "Analysis complete"}]}

server = create_sdk_mcp_server(name="my-tools", version="1.0.0", tools=[analyze_code])
```

### TypeScript SDK

**Installation:**
```bash
npm install @anthropic-ai/claude-agent-sdk  # Requires Node 18+
```

See [REFERENCE.md](REFERENCE.md) for complete API documentation.

## Review Checklist

### Subagent Review

- [ ] Name is descriptive, lowercase, hyphens only
- [ ] Description includes WHAT + WHEN (trigger keywords)
- [ ] Tools are explicitly whitelisted (not inherited)
- [ ] Model matches task complexity (haiku for simple, opus for complex)
- [ ] System prompt is concise (Claude is already smart)
- [ ] Single responsibility principle followed

### SDK Agent Review

- [ ] Error handling for all exception types
- [ ] Working directory explicitly set
- [ ] Permission mode appropriate for use case
- [ ] Hooks used for deterministic control points
- [ ] Custom tools return proper MCP format
- [ ] No hardcoded credentials (use env vars)

## Common Patterns

### Multi-Agent Coordination

```
Orchestrator Agent
    ├── Research Agent (read-only tools)
    ├── Implementation Agent (write tools)
    └── Review Agent (read + bash for tests)
```

### Hook-Based Control

```python
async def validate_before_write(input_data, tool_use_id, context):
    if input_data["tool_name"] == "Write":
        path = input_data["tool_input"].get("file_path", "")
        if "config" in path:
            return {"permissionDecision": "deny", "reason": "Config files protected"}
    return {}
```

## Anti-Patterns to Avoid

1. **Overly broad tool access** - Always whitelist tools explicitly
2. **Vague descriptions** - Include specific trigger keywords
3. **Missing verification** - Add feedback loops for quality
4. **Autonomous chains without approval gates** - Keep humans in the loop
5. **Parallel agents on same files** - Causes conflicts
6. **Over-explaining in prompts** - Claude already knows common concepts

## Resources

- **Detailed API Reference**: [REFERENCE.md](REFERENCE.md)
- **Templates**: [TEMPLATES.md](TEMPLATES.md)
- **Review Checklist**: [CHECKLIST.md](CHECKLIST.md)

## Official Documentation

- [Agent SDK Overview](https://docs.anthropic.com/en/docs/claude-code/sdk)
- [Subagents Guide](https://code.claude.com/docs/en/sub-agents)
- [Building Effective Agents](https://www.anthropic.com/research/building-effective-agents)
- [Claude Code Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices)
