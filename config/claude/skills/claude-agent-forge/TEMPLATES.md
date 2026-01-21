# Claude Agent Forge - Templates

## Table of Contents

- [Subagent Templates](#subagent-templates)
- [SDK Agent Templates (Python)](#sdk-agent-templates-python)
- [SDK Agent Templates (TypeScript)](#sdk-agent-templates-typescript)
- [Multi-Agent System Templates](#multi-agent-system-templates)
- [Hook Templates](#hook-templates)

---

## Subagent Templates

### Code Reviewer

```yaml
# .claude/agents/code-reviewer.md
---
name: code-reviewer
description: Reviews code for quality, security, and best practices. Use after code changes, before commits, or when requesting code review.
tools: Read, Grep, Glob
model: sonnet
---

You are an expert code reviewer. Analyze code for:

1. **Security**: SQL injection, XSS, command injection, hardcoded secrets
2. **Performance**: N+1 queries, unnecessary loops, memory leaks
3. **Maintainability**: Code clarity, naming, single responsibility
4. **Bugs**: Edge cases, null handling, type mismatches

## Output Format

For each issue found:
```
[SEVERITY] file:line - Issue description
  Context: <relevant code snippet>
  Fix: <specific recommendation>
```

Severity levels: CRITICAL, HIGH, MEDIUM, LOW, INFO

End with a summary: issues found per severity, overall assessment.
```

### Test Writer

```yaml
# .claude/agents/test-writer.md
---
name: test-writer
description: Generates comprehensive tests for code. Use when adding tests, improving coverage, or after implementing features.
tools: Read, Write, Grep, Glob, Bash
model: sonnet
permissionMode: acceptEdits
---

You are a testing specialist. Generate tests that:

1. Cover happy paths and edge cases
2. Test error conditions and boundary values
3. Are maintainable and well-documented
4. Follow the project's existing test patterns

## Workflow

1. Read the code to be tested
2. Identify existing test patterns (framework, style)
3. List scenarios to cover
4. Generate tests
5. Run tests to verify they pass: `npm test` or `pytest`
6. Report coverage changes if possible

## Test Structure

```
describe('ComponentName', () => {
  describe('methodName', () => {
    it('should handle normal input', () => {});
    it('should handle edge case', () => {});
    it('should throw on invalid input', () => {});
  });
});
```
```

### Documentation Generator

```yaml
# .claude/agents/doc-generator.md
---
name: doc-generator
description: Generates documentation from code. Use for API docs, README updates, or inline documentation.
tools: Read, Write, Grep, Glob
model: sonnet
permissionMode: acceptEdits
---

You are a technical writer. Generate documentation that:

1. Explains the "why" not just the "what"
2. Includes usage examples
3. Documents all public interfaces
4. Follows the project's documentation style

## Documentation Types

- **API Reference**: Parameters, return values, examples
- **README**: Overview, installation, quick start
- **Inline Comments**: Complex logic explanation only
- **Architecture Docs**: System design, data flow

## Format Guidelines

- Use present tense ("Returns" not "Will return")
- Lead with the most important information
- Include runnable code examples
- Link to related documentation
```

### Research Agent

```yaml
# .claude/agents/researcher.md
---
name: researcher
description: Researches topics and gathers information. Use for exploring codebases, understanding dependencies, or investigating issues.
tools: Read, Grep, Glob, WebSearch, WebFetch
model: sonnet
---

You are a research specialist. Gather comprehensive information by:

1. Searching the codebase for relevant patterns
2. Reading documentation and comments
3. Checking external resources when needed
4. Synthesizing findings into actionable insights

## Output Format

### Summary
[2-3 sentence overview]

### Key Findings
- Finding 1 with evidence
- Finding 2 with evidence

### Recommendations
1. Specific action with rationale
2. Specific action with rationale

### Sources
- file:line - description
- URL - description
```

### Security Auditor

```yaml
# .claude/agents/security-auditor.md
---
name: security-auditor
description: Audits code for security vulnerabilities. Use before releases, after adding auth/data handling, or for security reviews.
tools: Read, Grep, Glob
model: opus
---

You are a security expert. Audit code for OWASP Top 10 and common vulnerabilities:

1. **Injection**: SQL, command, LDAP, XPath
2. **Broken Authentication**: Weak passwords, session issues
3. **Sensitive Data Exposure**: Hardcoded secrets, logging PII
4. **XXE**: XML external entities
5. **Broken Access Control**: Missing authorization checks
6. **Misconfiguration**: Debug mode, default credentials
7. **XSS**: Reflected, stored, DOM-based
8. **Insecure Deserialization**: Untrusted data parsing
9. **Vulnerable Dependencies**: Outdated packages
10. **Insufficient Logging**: Missing audit trails

## Output Format

```
VULNERABILITY: [Name]
Severity: CRITICAL/HIGH/MEDIUM/LOW
Location: file:line
Description: What the vulnerability is
Impact: What could happen if exploited
Remediation: How to fix it
```
```

---

## SDK Agent Templates (Python)

### Simple Query Agent

```python
"""Simple agent for one-off queries."""
import anyio
from claude_agent_sdk import query, ClaudeAgentOptions, AssistantMessage, TextBlock

async def run_agent(prompt: str, working_dir: str = "."):
    options = ClaudeAgentOptions(
        system_prompt="You are a helpful coding assistant.",
        allowed_tools=["Read", "Grep", "Glob"],
        cwd=working_dir
    )

    async for message in query(prompt=prompt, options=options):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, TextBlock):
                    print(block.text)

if __name__ == "__main__":
    anyio.run(run_agent, "Explain the main function in main.py")
```

### Stateful Conversation Agent

```python
"""Agent for multi-turn conversations."""
import anyio
from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions

async def conversation_agent():
    options = ClaudeAgentOptions(
        system_prompt="You are a coding assistant. Ask clarifying questions when needed.",
        allowed_tools=["Read", "Write", "Edit", "Bash", "Grep", "Glob"],
        permission_mode='acceptEdits'
    )

    async with ClaudeSDKClient(options=options) as client:
        while True:
            user_input = input("\nYou: ").strip()
            if user_input.lower() in ('quit', 'exit'):
                break

            await client.query(user_input)
            print("\nAssistant: ", end="")
            async for msg in client.receive_response():
                if hasattr(msg, 'content'):
                    for block in msg.content:
                        if hasattr(block, 'text'):
                            print(block.text, end="")
            print()

if __name__ == "__main__":
    anyio.run(conversation_agent)
```

### Agent with Custom Tools

```python
"""Agent with custom MCP tools."""
import anyio
from claude_agent_sdk import (
    tool, create_sdk_mcp_server,
    ClaudeSDKClient, ClaudeAgentOptions
)

@tool("analyze_complexity", "Analyze code complexity metrics", {"file_path": str})
async def analyze_complexity(args):
    import subprocess
    path = args["file_path"]
    # Example: use radon for Python complexity
    result = subprocess.run(
        ["radon", "cc", path, "-a"],
        capture_output=True, text=True
    )
    return {
        "content": [{"type": "text", "text": result.stdout or "No output"}]
    }

@tool("count_lines", "Count lines of code", {"directory": str})
async def count_lines(args):
    import subprocess
    directory = args["directory"]
    result = subprocess.run(
        ["find", directory, "-name", "*.py", "-exec", "wc", "-l", "{}", "+"],
        capture_output=True, text=True
    )
    return {
        "content": [{"type": "text", "text": result.stdout or "No files found"}]
    }

async def main():
    server = create_sdk_mcp_server(
        name="code-metrics",
        version="1.0.0",
        tools=[analyze_complexity, count_lines]
    )

    options = ClaudeAgentOptions(
        system_prompt="You analyze code quality and metrics.",
        mcp_servers={"metrics": server},
        allowed_tools=[
            "Read", "Grep", "Glob",
            "mcp__metrics__analyze_complexity",
            "mcp__metrics__count_lines"
        ]
    )

    async with ClaudeSDKClient(options=options) as client:
        await client.query("Analyze the complexity of the src/ directory")
        async for msg in client.receive_response():
            print(msg)

if __name__ == "__main__":
    anyio.run(main)
```

### Agent with Hooks

```python
"""Agent with safety hooks."""
import anyio
from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions, HookMatcher

BLOCKED_PATTERNS = ["rm -rf", "sudo rm", "> /dev/", "chmod 777"]
PROTECTED_PATHS = ["/etc", "/usr", "/var", "~/.ssh"]

async def validate_bash(input_data, tool_use_id, context):
    if input_data["tool_name"] != "Bash":
        return {}

    command = input_data["tool_input"].get("command", "")

    for pattern in BLOCKED_PATTERNS:
        if pattern in command:
            return {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": f"Blocked dangerous pattern: {pattern}"
                }
            }
    return {}

async def validate_write(input_data, tool_use_id, context):
    if input_data["tool_name"] not in ["Write", "Edit"]:
        return {}

    path = input_data["tool_input"].get("file_path", "")

    for protected in PROTECTED_PATHS:
        if path.startswith(protected):
            return {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": f"Protected path: {protected}"
                }
            }
    return {}

async def main():
    options = ClaudeAgentOptions(
        allowed_tools=["Read", "Write", "Edit", "Bash", "Grep", "Glob"],
        permission_mode='acceptEdits',
        hooks={
            "PreToolUse": [
                HookMatcher(matcher="Bash", hooks=[validate_bash]),
                HookMatcher(matcher="Write", hooks=[validate_write]),
                HookMatcher(matcher="Edit", hooks=[validate_write]),
            ]
        }
    )

    async with ClaudeSDKClient(options=options) as client:
        await client.query("Help me organize the project files")
        async for msg in client.receive_response():
            print(msg)

if __name__ == "__main__":
    anyio.run(main)
```

---

## SDK Agent Templates (TypeScript)

### Basic Agent

```typescript
import { query, ClaudeAgentOptions } from '@anthropic-ai/claude-agent-sdk';

async function runAgent(prompt: string): Promise<void> {
  const options: ClaudeAgentOptions = {
    systemPrompt: "You are a helpful coding assistant.",
    allowedTools: ["Read", "Grep", "Glob"],
    cwd: process.cwd()
  };

  for await (const message of query(prompt, options)) {
    if (message.type === 'assistant' && message.content) {
      for (const block of message.content) {
        if (block.type === 'text') {
          console.log(block.text);
        }
      }
    }
  }
}

runAgent("Explain the architecture of this project");
```

---

## Multi-Agent System Templates

### Orchestrator Pattern

```python
"""Multi-agent system with orchestrator."""
import anyio
from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions

AGENTS = {
    "researcher": ClaudeAgentOptions(
        system_prompt="You research and gather information. Report findings clearly.",
        allowed_tools=["Read", "Grep", "Glob", "WebSearch"],
    ),
    "implementer": ClaudeAgentOptions(
        system_prompt="You implement solutions. Write clean, tested code.",
        allowed_tools=["Read", "Write", "Edit", "Bash", "Grep", "Glob"],
        permission_mode='acceptEdits'
    ),
    "reviewer": ClaudeAgentOptions(
        system_prompt="You review code for quality and correctness.",
        allowed_tools=["Read", "Grep", "Glob", "Bash"],
    )
}

async def run_agent(agent_name: str, task: str) -> str:
    options = AGENTS[agent_name]
    results = []

    async with ClaudeSDKClient(options=options) as client:
        await client.query(task)
        async for msg in client.receive_response():
            if hasattr(msg, 'content'):
                for block in msg.content:
                    if hasattr(block, 'text'):
                        results.append(block.text)

    return "\n".join(results)

async def orchestrate(task: str):
    # Step 1: Research
    print("=== Research Phase ===")
    research = await run_agent("researcher", f"Research: {task}")
    print(research)

    # Step 2: Implement
    print("\n=== Implementation Phase ===")
    implementation = await run_agent(
        "implementer",
        f"Based on this research:\n{research}\n\nImplement: {task}"
    )
    print(implementation)

    # Step 3: Review
    print("\n=== Review Phase ===")
    review = await run_agent(
        "reviewer",
        f"Review the implementation for: {task}"
    )
    print(review)

if __name__ == "__main__":
    anyio.run(orchestrate, "Add input validation to the user form")
```

---

## Hook Templates

### Logging Hook

```python
async def log_tool_use(input_data, tool_use_id, context):
    """Log all tool invocations."""
    import json
    from datetime import datetime

    log_entry = {
        "timestamp": datetime.now().isoformat(),
        "tool": input_data["tool_name"],
        "input": input_data["tool_input"],
        "tool_use_id": tool_use_id
    }

    with open("agent_audit.log", "a") as f:
        f.write(json.dumps(log_entry) + "\n")

    return {}  # Allow to proceed
```

### Rate Limiting Hook

```python
from collections import defaultdict
from datetime import datetime, timedelta

TOOL_COUNTS = defaultdict(list)
RATE_LIMITS = {
    "Bash": (10, timedelta(minutes=1)),      # 10 per minute
    "Write": (20, timedelta(minutes=1)),     # 20 per minute
    "WebSearch": (5, timedelta(minutes=1)),  # 5 per minute
}

async def rate_limit_hook(input_data, tool_use_id, context):
    """Enforce rate limits on tool usage."""
    tool = input_data["tool_name"]
    now = datetime.now()

    if tool not in RATE_LIMITS:
        return {}

    limit, window = RATE_LIMITS[tool]

    # Clean old entries
    TOOL_COUNTS[tool] = [t for t in TOOL_COUNTS[tool] if now - t < window]

    if len(TOOL_COUNTS[tool]) >= limit:
        return {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": f"Rate limit: {limit} {tool} calls per {window}"
            }
        }

    TOOL_COUNTS[tool].append(now)
    return {}
```

### Content Filter Hook

```python
SENSITIVE_PATTERNS = [
    r"api[_-]?key",
    r"password",
    r"secret",
    r"token",
    r"credential",
]

async def filter_sensitive_content(input_data, tool_use_id, context):
    """Prevent writing sensitive data."""
    import re

    if input_data["tool_name"] not in ["Write", "Edit"]:
        return {}

    content = str(input_data["tool_input"])

    for pattern in SENSITIVE_PATTERNS:
        if re.search(pattern, content, re.IGNORECASE):
            return {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": f"Content may contain sensitive data: {pattern}"
                }
            }

    return {}
```
