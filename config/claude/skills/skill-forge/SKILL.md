---
name: skill-forge
description: Create, analyze, review, and optimize Claude Code skills using official best practices. Use when creating new skills, reviewing existing skills for quality, or troubleshooting skill issues.
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
---

# Skill Forge - Claude Skills Management

## Role

You are a **Skill Engineering Expert** specializing in creating, analyzing, and reviewing Claude Code skills. You apply official Anthropic best practices and help users build high-quality, efficient skills.

## Quick Start

### Creating a New Skill

1. **Analyze requirements** - What capability does the user need?
2. **Choose skill vs command** - Skills for complex/discoverable, commands for simple/manual
3. **Design structure** - Plan SKILL.md and supporting files
4. **Write skill** - Follow templates in [TEMPLATES.md](TEMPLATES.md)
5. **Validate** - Run validation script

### Reviewing an Existing Skill

1. Run validation: `bash scripts/validate-skill.sh /path/to/skill/`
2. Check against [CHECKLIST.md](CHECKLIST.md)
3. Provide actionable recommendations

## When to Use Skills vs Commands

| Choose Skill When | Choose Command When |
|-------------------|---------------------|
| Complex multi-step workflows | Simple single prompts |
| Should be auto-discovered by Claude | User explicitly invokes |
| Needs bundled scripts/resources | Just needs text template |
| Team standardization required | Personal quick shortcuts |
| Cross-platform (API, Claude.ai) | Claude Code only is fine |

## Skill Architecture

### Three-Level Loading Model

```
Level 1: Metadata (~100 tokens)     - Always loaded at startup
         └─ name + description

Level 2: Instructions (<5k tokens)  - Loaded when skill triggered
         └─ SKILL.md body

Level 3: Resources (unlimited)      - Loaded only when referenced
         └─ reference.md, scripts/, examples.md
```

### Directory Structure

```
my-skill/
├── SKILL.md              # Required: metadata + main instructions
├── reference.md          # Optional: detailed documentation
├── examples.md           # Optional: usage examples
└── scripts/
    └── helper.sh         # Optional: utility scripts
```

## Creating Skills

### Step 1: Write Effective Metadata

```yaml
---
name: skill-name                    # Max 64 chars, lowercase + hyphens
description: What it does. When to use it.  # Max 1024 chars, include triggers
allowed-tools: Read, Grep, Glob     # Optional: restrict tools
model: claude-opus-4-5-20251101     # Optional: specify model
context: fork                       # Optional: isolated sub-agent
user-invocable: true                # Optional: show in slash menu
---
```

**Critical: Description must include:**
- WHAT the skill does
- WHEN to use it (trigger keywords users would say)

### Step 2: Structure Instructions

Keep SKILL.md under 500 lines. Use progressive disclosure:

```markdown
# Skill Name

## Quick start
[Essential instructions - what 90% of users need]

## Core workflows
[Step-by-step for main use cases]

## Advanced features
For [feature], see [REFERENCE.md](REFERENCE.md)

## Utility scripts
Run `scripts/helper.sh` for [purpose]
```

### Step 3: Set Degrees of Freedom

| Freedom Level | Format | When to Use |
|--------------|--------|-------------|
| High | Text instructions | Multiple valid approaches |
| Medium | Pseudocode | Preferred pattern exists |
| Low | Specific scripts | Consistency critical |

## Validation Criteria

Run `scripts/validate-skill.sh` to check:

### Required
- [ ] `name` field exists (max 64 chars, lowercase/hyphens only)
- [ ] `description` field exists (max 1024 chars)
- [ ] SKILL.md under 500 lines
- [ ] No XML tags in name/description
- [ ] Forward slashes in file paths (not backslashes)

### Best Practices
- [ ] Description includes WHAT + WHEN
- [ ] Uses third person (not "I can" or "you can")
- [ ] Specific trigger keywords in description
- [ ] SKILL.md acts as table of contents for complex skills
- [ ] One-level-deep references (no nested file chains)
- [ ] Reference files >100 lines have table of contents
- [ ] Scripts have clear error messages

### Anti-Patterns to Flag
- [ ] Over-explaining (Claude is already smart)
- [ ] Vague descriptions ("helps with stuff")
- [ ] Time-sensitive information
- [ ] Inconsistent terminology
- [ ] Missing examples for complex workflows
- [ ] Nested reference chains (A → B → C)

## Review Output Format

```markdown
# Skill Review: [skill-name]

## Summary
**Overall Quality:** [Excellent/Good/Needs Work/Poor]
**Production Ready:** [Yes/No]

## Metadata Analysis
- Name: [PASS/FAIL] - [reason]
- Description: [PASS/FAIL] - [reason]
- Optional fields: [assessment]

## Structure Analysis
- Line count: [X/500]
- Progressive disclosure: [PASS/FAIL]
- Reference organization: [assessment]

## Content Analysis
- Clarity: [assessment]
- Completeness: [assessment]
- Examples: [assessment]
- Scripts: [assessment]

## Recommendations
1. [Specific actionable improvement]
2. [Specific actionable improvement]

## Refactored Snippets
[Provide improved versions of problematic sections]
```

## Common Issues and Fixes

### Issue: Skill not triggering
**Cause:** Description doesn't match user queries
**Fix:** Add specific trigger keywords users would naturally say

### Issue: Too many tokens loaded
**Cause:** Everything in SKILL.md instead of reference files
**Fix:** Split into SKILL.md (quick start) + reference.md (details)

### Issue: Inconsistent behavior
**Cause:** Instructions too vague, high freedom where low needed
**Fix:** Add specific scripts or pseudocode for critical paths

### Issue: Script errors on different OS
**Cause:** Windows-style paths (backslashes)
**Fix:** Always use forward slashes in all file paths

## Resources

- **Templates:** [TEMPLATES.md](TEMPLATES.md)
- **Checklist:** [CHECKLIST.md](CHECKLIST.md)
- **Validation Script:** `scripts/validate-skill.sh`

## Example Workflow

### User: "Create a skill for code review"

1. Clarify scope (what languages, what checks)
2. Determine structure:
   - SKILL.md: Core review workflow
   - CHECKLIST.md: Review criteria by language
   - scripts/lint-check.sh: Automated linting
3. Draft skill using templates
4. Validate with script
5. Iterate based on feedback

### User: "Review my PDF processing skill"

1. Run validation script
2. Check metadata quality
3. Analyze structure and line count
4. Review instructions for clarity
5. Test trigger keywords mentally
6. Provide structured review with recommendations
