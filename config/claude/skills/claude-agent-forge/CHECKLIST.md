# Claude Agent Forge - Review Checklist

Use this checklist when creating or reviewing Claude agents.

---

## Subagent Review Checklist

### Metadata Quality

- [ ] **Name** is lowercase, hyphens only, max 64 chars
- [ ] **Name** reflects the agent's purpose (e.g., `code-reviewer`, `test-writer`)
- [ ] **Description** states WHAT it does
- [ ] **Description** states WHEN to use it (trigger keywords)
- [ ] **Description** is under 1024 chars
- [ ] **Description** uses third person ("Reviews code" not "I review code")

### Tool Configuration

- [ ] **Tools explicitly listed** (not inherited by default)
- [ ] **Minimum required tools** (least privilege)
- [ ] **Read-only tools for research agents** (Read, Grep, Glob)
- [ ] **Write tools only when needed** (Write, Edit, Bash)
- [ ] **MCP tools use fully qualified names** (`ServerName:tool_name`)

### Model Selection

- [ ] **Haiku** for simple, high-volume tasks
- [ ] **Sonnet** for balanced tasks (default)
- [ ] **Opus** for complex reasoning, critical decisions
- [ ] **Inherit** when context continuity matters

### System Prompt Quality

- [ ] **Concise** - Claude is already smart, don't over-explain
- [ ] **Role clearly defined** - "You are a..."
- [ ] **Output format specified** if structured output needed
- [ ] **Constraints stated** - what NOT to do
- [ ] **Workflow outlined** for multi-step tasks

### Security

- [ ] **No hardcoded secrets** in prompts
- [ ] **Permission mode appropriate** for use case
- [ ] **Hooks configured** for sensitive operations
- [ ] **Protected paths excluded** from write access

---

## SDK Agent Review Checklist

### Code Quality

- [ ] **Error handling** for all SDK exception types
- [ ] **Async/await** used correctly
- [ ] **Context manager** (`async with`) for ClaudeSDKClient
- [ ] **Resource cleanup** ensured (connections closed)

### Configuration

- [ ] **Working directory** explicitly set
- [ ] **System prompt** provided for context
- [ ] **Tools allowlisted** (not default all)
- [ ] **Permission mode** matches automation level
- [ ] **Max turns** set if bounded execution needed

### Custom Tools

- [ ] **@tool decorator** used with all required fields
- [ ] **Description is clear** and includes when to use
- [ ] **Parameters documented** with types
- [ ] **Return format** matches MCP spec (`{"content": [...]}`)
- [ ] **Error cases** handled gracefully

### Hooks

- [ ] **PreToolUse** for validation/blocking
- [ ] **PostToolUse** for logging/cleanup
- [ ] **Matcher patterns** correctly target tools
- [ ] **Return format** correct for hook type
- [ ] **No blocking operations** in hooks (async)

### Security

- [ ] **Environment variables** for credentials
- [ ] **Input validation** in custom tools
- [ ] **Rate limiting** for expensive operations
- [ ] **Audit logging** for compliance
- [ ] **Sandboxed testing** before production

---

## Multi-Agent System Checklist

### Architecture

- [ ] **Clear agent responsibilities** (single purpose each)
- [ ] **Handoff protocol defined** between agents
- [ ] **Orchestrator pattern** if coordination needed
- [ ] **Parallel execution** only on independent tasks
- [ ] **No overlapping file access** between parallel agents

### Communication

- [ ] **Structured output format** for inter-agent data
- [ ] **Context passed explicitly** (not assumed)
- [ ] **Error states communicated** clearly
- [ ] **Progress tracking** implemented

### Human Oversight

- [ ] **Approval gates** between critical steps
- [ ] **Rollback capability** for destructive actions
- [ ] **Audit trail** of all agent decisions
- [ ] **Manual intervention points** defined

---

## Performance Checklist

### Token Efficiency

- [ ] **Prompts are concise** (no redundant explanation)
- [ ] **Tools match task** (not over-provisioned)
- [ ] **Model matches complexity** (haiku for simple)
- [ ] **Context compaction** for long conversations

### Execution Speed

- [ ] **Parallel tool calls** where independent
- [ ] **Caching** for repeated lookups
- [ ] **Batched operations** where possible
- [ ] **Timeout handling** for slow operations

### Cost Optimization

- [ ] **Haiku for high-volume** simple tasks
- [ ] **Max turns limited** to prevent runaway
- [ ] **Early termination** conditions defined
- [ ] **Tool usage monitored** and limited

---

## Review Output Template

```markdown
# Agent Review: [agent-name]

## Summary
**Type:** Subagent / SDK Agent / Multi-Agent
**Overall Quality:** Excellent / Good / Needs Work / Poor
**Production Ready:** Yes / No

## Metadata Analysis
- Name: [PASS/FAIL] - [reason]
- Description: [PASS/FAIL] - [reason]
- Model: [appropriate/needs change]

## Tool Analysis
- Configuration: [PASS/FAIL] - [reason]
- Security: [PASS/FAIL] - [reason]
- Least Privilege: [PASS/FAIL] - [reason]

## Prompt Analysis
- Clarity: [assessment]
- Conciseness: [assessment]
- Completeness: [assessment]

## Security Analysis
- Credential Handling: [PASS/FAIL]
- Permission Mode: [appropriate/needs change]
- Hook Coverage: [adequate/insufficient]

## Recommendations
1. [Specific actionable improvement]
2. [Specific actionable improvement]
3. [Specific actionable improvement]

## Refactored Examples
[Provide improved versions of problematic sections]
```

---

## Quick Reference: Common Issues

| Issue | Symptom | Fix |
|-------|---------|-----|
| Agent not triggering | Doesn't activate for relevant tasks | Add trigger keywords to description |
| Over-broad access | Agent modifies unexpected files | Whitelist specific tools |
| Slow execution | Takes too long for simple tasks | Use haiku model |
| Poor output quality | Inconsistent or incomplete results | Add output format to prompt |
| Security violation | Accesses sensitive data | Add hooks for validation |
| Context overflow | Runs out of context | Enable compaction, reduce tool output |
| Runaway execution | Never terminates | Set max_turns limit |
| Tool failures | Tools return errors | Check tool permissions and paths |
