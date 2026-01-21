# Skill Templates

## Table of Contents
- [Minimal Skill](#minimal-skill)
- [Standard Skill](#standard-skill)
- [Complex Multi-File Skill](#complex-multi-file-skill)
- [Tool-Automation Skill](#tool-automation-skill)
- [Verification Agent Skill](#verification-agent-skill)
- [Workflow Skill](#workflow-skill)

---

## Minimal Skill

For simple capabilities that fit in one file.

```yaml
---
name: simple-task
description: Brief description of what this does. Use when [specific trigger conditions].
---

# Simple Task

## Quick Start

[2-3 sentences on core usage]

## Instructions

1. [Step one]
2. [Step two]
3. [Step three]

## Example

Input: [example input]
Output: [example output]
```

---

## Standard Skill

For most skills with moderate complexity.

```yaml
---
name: standard-capability
description: [What it does in one sentence]. Use when [trigger keywords and conditions].
allowed-tools: Read, Grep, Glob
---

# Standard Capability

## Quick Start

[Essential workflow for 90% of use cases]

## Core Workflows

### Workflow A: [Name]

1. [Step with context]
2. [Step with context]
3. [Validation/completion criteria]

### Workflow B: [Name]

1. [Step]
2. [Step]

## Common Patterns

### Pattern: [Name]
```
[Code or pseudocode example]
```

### Pattern: [Name]
```
[Code or pseudocode example]
```

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| [Error type] | [Why it happens] | [How to fix] |

## Tips

- [Practical tip 1]
- [Practical tip 2]
```

---

## Complex Multi-File Skill

For comprehensive capabilities requiring progressive disclosure.

### Directory Structure
```
complex-skill/
├── SKILL.md
├── REFERENCE.md
├── EXAMPLES.md
├── TROUBLESHOOTING.md
└── scripts/
    ├── main-action.sh
    └── validate.sh
```

### SKILL.md
```yaml
---
name: complex-capability
description: [Comprehensive description]. Use when [multiple trigger scenarios]. Handles [key features].
allowed-tools: Read, Grep, Glob, Bash
---

# Complex Capability

## Quick Start

[Minimal viable workflow - what to do in 90% of cases]

## Core Concepts

- **[Term 1]**: [Brief definition]
- **[Term 2]**: [Brief definition]

## Main Workflows

### [Primary Use Case]

1. [Step]
2. [Step]
3. Run validation: `scripts/validate.sh`

### [Secondary Use Case]

See [EXAMPLES.md](EXAMPLES.md) for detailed walkthroughs.

## Utility Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `main-action.sh` | [Purpose] | `bash scripts/main-action.sh [args]` |
| `validate.sh` | [Purpose] | `bash scripts/validate.sh [path]` |

## Advanced Topics

For detailed API reference, see [REFERENCE.md](REFERENCE.md)
For troubleshooting, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

## Quick Reference

| Action | Command/Steps |
|--------|---------------|
| [Action 1] | [How to do it] |
| [Action 2] | [How to do it] |
```

---

## Tool-Automation Skill

For skills that wrap external tools or APIs.

```yaml
---
name: tool-automation
description: Automate [tool name] for [purpose]. Use when [trigger conditions]. Requires [prerequisites].
allowed-tools: Read, Bash, Grep
---

# Tool Automation

## Prerequisites

- `TOOL_API_KEY` environment variable set
- [Other requirements]

Verify setup:
```bash
[[ -n "$TOOL_API_KEY" ]] && echo "Ready" || echo "ERROR: Set TOOL_API_KEY"
```

## Quick Start

```bash
# Basic usage
scripts/run-tool.sh "input"

# With options
scripts/run-tool.sh -o option "input"
```

## Script Location

```
~/.config/claude/skills/tool-automation/scripts/run-tool.sh
```

## Usage Patterns

### Pattern 1: [Name]

```bash
scripts/run-tool.sh "example-input"
```

### Pattern 2: [Name]

```bash
scripts/run-tool.sh -f flag "example-input"
```

## Output Format

```json
{
  "success": true,
  "result": "...",
  "metadata": {}
}
```

## Error Handling

| Code | Meaning | Resolution |
|------|---------|------------|
| 401 | Auth failed | Check API key |
| 404 | Not found | Verify input |
| 500 | Server error | Retry later |

## Security Notes

- Never commit API keys
- Clean up temporary files after use
- [Other security considerations]
```

---

## Verification Agent Skill

For testing and validation workflows.

```yaml
---
name: project-verification
description: Comprehensive verification for [project type]. Zero-tolerance testing with evidence-based reporting.
---

# Verification Agent

## Role

You are a **Verification Engineer** conducting pre-production checks. This is an INDEPENDENT verification - assume no prior context.

**Principles:**
- Zero-Tolerance: Every detail matters
- Evidence-Based: All assertions backed by command output
- Independent: Never trust claims without verification
- Non-Lenient: Ambiguous = FAIL

## Verification Protocol

### Phase 1: [Category]

#### 1.1 [Check Name]

```bash
[command to run]
```

**PASS CRITERIA:**
- [Specific condition]
- [Specific condition]

**FAIL IF:**
- [Failure condition]
- [Failure condition]

### Phase 2: [Category]

[Continue pattern...]

## Pass/Fail Summary

### PASS Requirements (ALL must be true):
- [ ] [Requirement 1]
- [ ] [Requirement 2]

### FAIL Conditions (ANY triggers failure):
- [Condition 1]
- [Condition 2]

## Report Format

```markdown
# Verification Report
Date: [timestamp]

## Summary
**STATUS:** [PASS/FAIL]
**Critical Issues:** [count]

## Results
[Phase-by-phase results]

## Evidence Log
[Command outputs]

## Recommendation
[APPROVE/REJECT with justification]
```
```

---

## Workflow Skill

For multi-step business processes.

```yaml
---
name: workflow-process
description: Guide through [process name]. Use when [trigger]. Ensures [outcome].
---

# Workflow Process

## Overview

This workflow ensures [outcome] through [X] phases.

## Phases

### Phase 1: [Name] (Required)

**Goal:** [What this achieves]

**Steps:**
1. [ ] [Action item]
2. [ ] [Action item]
3. [ ] [Validation step]

**Checklist before proceeding:**
- [ ] [Condition met]
- [ ] [Condition met]

### Phase 2: [Name]

**Goal:** [What this achieves]

**Steps:**
1. [ ] [Action item]
2. [ ] [Action item]

**Decision Point:**
- If [condition A]: proceed to Phase 3
- If [condition B]: return to Phase 1

### Phase 3: [Name]

[Continue pattern...]

## Rollback Procedures

If [failure condition]:
1. [Rollback step]
2. [Rollback step]
3. Return to [phase]

## Completion Criteria

- [ ] [Final verification 1]
- [ ] [Final verification 2]
- [ ] [Deliverable produced]
```

---

## Template Selection Guide

| Skill Type | Template | When to Use |
|------------|----------|-------------|
| Simple prompt enhancement | Minimal | Single-purpose, <100 lines |
| General capability | Standard | Moderate complexity, 100-300 lines |
| Enterprise workflow | Complex Multi-File | Many features, team use |
| External tool wrapper | Tool-Automation | API/CLI integration |
| Testing/QA | Verification Agent | Pre-deployment checks |
| Business process | Workflow | Multi-phase procedures |
