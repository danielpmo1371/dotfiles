# Skill-Forge Reference

Detailed reference documentation for Claude Code skill development.

## Table of Contents
- [Metadata Field Reference](#metadata-field-reference)
- [Tool Restrictions](#tool-restrictions)
- [Context Options](#context-options)
- [Hooks Configuration](#hooks-configuration)
- [Installation Locations](#installation-locations)

---

## Metadata Field Reference

### Required Fields

| Field | Type | Constraints | Purpose |
|-------|------|-------------|---------|
| `name` | String | Max 64 chars, `[a-z0-9-]` only | Unique skill identifier |
| `description` | String | Max 1024 chars, non-empty | Discovery and triggering |

### Optional Fields

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `allowed-tools` | List | All tools | Restrict available tools |
| `model` | String | Inherited | Force specific model |
| `context` | String | `shared` | `fork` for isolated context |
| `agent` | String | `general-purpose` | Agent type when forked |
| `user-invocable` | Boolean | `true` | Show in slash menu |
| `disable-model-invocation` | Boolean | `false` | Prevent programmatic invocation |
| `hooks` | Object | None | Lifecycle event handlers |

---

## Tool Restrictions

Use `allowed-tools` to limit which tools the skill can use:

```yaml
allowed-tools: Read, Grep, Glob        # Read-only skill
allowed-tools: Read, Bash(python:*)    # Allow only Python via Bash
allowed-tools: Read, Write, Edit       # Full file editing
```

### Common Tool Sets

| Purpose | Tools |
|---------|-------|
| Read-only analysis | `Read, Grep, Glob` |
| Code generation | `Read, Write, Edit, Grep, Glob` |
| Automation | `Read, Bash, Grep, Glob` |
| Full capability | (omit field for all tools) |

---

## Context Options

### Shared Context (default)

```yaml
# No context field needed - skill shares main conversation
---
name: inline-helper
description: Helps inline with current task
---
```

### Forked Context

```yaml
---
name: isolated-analyzer
description: Runs analysis in isolation
context: fork
agent: general-purpose
---
```

**When to fork:**
- Long-running tasks that clutter conversation
- Independent verification that shouldn't be influenced
- Parallel execution with main conversation

**Agent types for forked context:**
- `general-purpose` - Default, all capabilities
- `Explore` - Codebase exploration
- `Plan` - Implementation planning
- Custom agents from `.claude/agents/`

---

## Hooks Configuration

Hooks run commands at skill lifecycle events:

```yaml
---
name: secure-ops
description: Operations with security validation
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/validate.sh $TOOL_INPUT"
          once: true
  PostToolUse:
    - matcher: "Write"
      hooks:
        - type: command
          command: "./scripts/audit-write.sh $FILE_PATH"
---
```

### Hook Events

| Event | Trigger | Use Case |
|-------|---------|----------|
| `PreToolUse` | Before tool execution | Validation, security checks |
| `PostToolUse` | After tool execution | Audit, cleanup, verification |
| `Stop` | When skill completes | Final cleanup, reporting |

### Hook Properties

| Property | Required | Purpose |
|----------|----------|---------|
| `matcher` | Yes | Tool name to match |
| `type` | Yes | `command` for shell execution |
| `command` | Yes | Shell command to run |
| `once` | No | Run only first match if true |

---

## Installation Locations

### Priority Order (highest to lowest)

1. **Enterprise** - Organization managed settings
2. **Personal** - `~/.claude/skills/`
3. **Project** - `.claude/skills/` in repository
4. **Plugin** - `skills/` in plugin directory

### Location Characteristics

| Location | Path | Sharing | Use Case |
|----------|------|---------|----------|
| Personal | `~/.claude/skills/` | Self only | Personal workflows |
| Project | `.claude/skills/` | Via git | Team standards |
| Plugin | Plugin's `skills/` | Marketplace | Distribution |

### Skill Discovery

```bash
# List personal skills
ls ~/.claude/skills/

# List project skills
ls .claude/skills/

# All active skills visible via /skills in Claude Code
```

---

## Model Selection

Force a specific model for the skill:

```yaml
model: claude-opus-4-5-20251101    # Use Opus 4.5
model: claude-sonnet-4-20250514    # Use Sonnet 4
```

**When to specify model:**
- Complex analysis requiring Opus capabilities
- Cost optimization with Haiku for simple tasks
- Consistency across different user configurations

---

## Cross-Platform Compatibility

Skills work across:
- Claude Code (CLI)
- Claude.ai (web)
- Claude API
- Claude Agent SDK

**Compatibility notes:**
- Slash commands are Claude Code only
- Skills with `context: fork` may behave differently across platforms
- Tool availability varies by platform
- File paths use forward slashes universally
