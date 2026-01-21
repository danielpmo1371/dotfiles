# Skill Quality Checklist

Use this checklist when reviewing or creating Claude Code skills.

## Table of Contents
- [Required Validations](#required-validations)
- [Best Practice Checks](#best-practice-checks)
- [Anti-Pattern Detection](#anti-pattern-detection)
- [Security Review](#security-review)
- [Performance Considerations](#performance-considerations)

---

## Required Validations

These MUST pass for a skill to be valid.

### Metadata

- [ ] **Name exists** and is non-empty
- [ ] **Name format** - Max 64 chars, lowercase letters, numbers, hyphens only
- [ ] **Name avoids reserved words** - No "anthropic", "claude" prefixes
- [ ] **Name has no XML tags** - No `<`, `>` characters
- [ ] **Description exists** and is non-empty
- [ ] **Description length** - Max 1024 characters
- [ ] **Description has no XML tags**

### File Structure

- [ ] **SKILL.md exists** in skill directory
- [ ] **SKILL.md under 500 lines** (optimal performance)
- [ ] **Forward slashes in paths** - No backslashes (Windows compatibility)
- [ ] **Valid YAML frontmatter** - Proper `---` delimiters

### References

- [ ] **No broken links** - All referenced files exist
- [ ] **One-level references** - No nested reference chains (A → B → C)
- [ ] **Reference files accessible** - Correct relative paths

---

## Best Practice Checks

These significantly improve skill quality.

### Description Quality

- [ ] **Includes WHAT** - Clear statement of capability
- [ ] **Includes WHEN** - Trigger conditions/keywords
- [ ] **Third person** - Not "I can" or "you can"
- [ ] **Specific triggers** - Keywords users would actually say
- [ ] **Action-oriented** - Starts with verb or describes action

**Good examples:**
```
"Extract text and tables from PDF files. Use when working with PDFs or document extraction."
"Analyze code quality with detailed reports. Use when reviewing code or before commits."
```

**Bad examples:**
```
"Helps with stuff" (too vague)
"I can help you with PDFs" (first person)
"PDF helper" (no trigger context)
```

### Instruction Structure

- [ ] **Quick start section** - Essential workflow first
- [ ] **Progressive disclosure** - Details in reference files
- [ ] **Clear headings** - Scannable structure
- [ ] **Concrete examples** - Input/output pairs
- [ ] **Table of contents** - For files >100 lines

### Content Quality

- [ ] **Assumes Claude intelligence** - Only adds novel context
- [ ] **Consistent terminology** - Same term used throughout
- [ ] **No time-sensitive info** - No calendar dates
- [ ] **Complete workflows** - No "TODO" or placeholders
- [ ] **Error handling documented** - What to do when things fail

### Scripts (if present)

- [ ] **Clear purpose** - Comments explain intent
- [ ] **Error messages** - Helpful when failures occur
- [ ] **Exit codes** - Proper success/failure indication
- [ ] **No hardcoded secrets** - Uses environment variables
- [ ] **Cross-platform** - Works on macOS/Linux (or documents limitations)

---

## Anti-Pattern Detection

Flag these issues during review.

### Structural Anti-Patterns

| Anti-Pattern | Problem | Fix |
|--------------|---------|-----|
| Everything in SKILL.md | Token bloat | Split into reference files |
| Nested references (A→B→C) | Hard to navigate | Flatten to one level |
| No examples | Unclear usage | Add input/output pairs |
| Monolithic scripts | Hard to debug | Split into focused scripts |

### Content Anti-Patterns

| Anti-Pattern | Problem | Fix |
|--------------|---------|-----|
| Over-explaining basics | Wastes tokens | Remove obvious info |
| Vague descriptions | Poor triggering | Add specific keywords |
| Mixed terminology | Confusion | Pick one term, use consistently |
| Outdated info | Wrong guidance | Remove time-sensitive content |
| "I/you" language | Informal | Use third person |

### Technical Anti-Patterns

| Anti-Pattern | Problem | Fix |
|--------------|---------|-----|
| Backslash paths | Breaks Unix | Use forward slashes |
| Hardcoded paths | Inflexible | Use relative or ~ paths |
| Missing prerequisites | Fails silently | Document requirements |
| No error handling | Confusing failures | Add clear error messages |

---

## Security Review

Critical for skills with file access or external calls.

### File Operations

- [ ] **No secrets in files** - API keys, tokens, passwords
- [ ] **Safe file paths** - No path traversal vulnerabilities
- [ ] **Appropriate permissions** - Scripts executable, configs readable
- [ ] **Temp file cleanup** - Remove sensitive temporary data

### External Access

- [ ] **Environment variables for secrets** - Never hardcoded
- [ ] **HTTPS for URLs** - No plain HTTP for sensitive data
- [ ] **Input validation** - Scripts validate user input
- [ ] **Rate limiting awareness** - Don't overwhelm external APIs

### Trust Boundaries

- [ ] **Document required permissions** - What the skill needs access to
- [ ] **Minimal privilege** - Only request necessary tools
- [ ] **Audit trail** - Log significant actions for review

---

## Performance Considerations

Optimize for token efficiency and responsiveness.

### Token Budget

| Component | Recommended | Max |
|-----------|-------------|-----|
| Metadata (Level 1) | ~100 tokens | ~150 tokens |
| SKILL.md body (Level 2) | <3000 tokens | <5000 tokens |
| Reference files (Level 3) | As needed | Unlimited |

### Loading Optimization

- [ ] **Essential content in SKILL.md** - Common workflows only
- [ ] **Rare content in references** - Edge cases, detailed API docs
- [ ] **Scripts execute, don't load** - Only output counts toward tokens
- [ ] **Images/binaries as resources** - Not inline in markdown

### Responsiveness

- [ ] **Fast path first** - Most common use case at top
- [ ] **Decision trees** - Help Claude find right workflow quickly
- [ ] **Avoid ambiguity** - Clear when to use which approach

---

## Quick Scoring Guide

Rate each category 1-5, calculate average.

| Score | Meaning |
|-------|---------|
| 5 | Excellent - Follows all best practices |
| 4 | Good - Minor improvements possible |
| 3 | Acceptable - Works but needs polish |
| 2 | Needs Work - Significant issues |
| 1 | Poor - Fundamental problems |

### Scoring Categories

1. **Metadata Quality** (name + description)
2. **Structure** (organization, progressive disclosure)
3. **Content** (clarity, completeness, examples)
4. **Technical** (scripts, paths, error handling)
5. **Security** (secrets, permissions, trust)

**Production Ready:** Average score >= 3.5 with no category below 2

---

## Review Template

```markdown
# Skill Review: [name]

## Scores
- Metadata: [1-5]
- Structure: [1-5]
- Content: [1-5]
- Technical: [1-5]
- Security: [1-5]
- **Average: [X.X]**

## Required Issues
[List any failed required validations]

## Recommendations
1. [Priority 1 fix]
2. [Priority 2 fix]
3. [Priority 3 fix]

## Production Ready: [Yes/No]
```
