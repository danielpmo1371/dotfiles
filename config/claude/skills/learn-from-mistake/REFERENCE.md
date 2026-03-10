# Learn From Mistake - Detailed Reference Guide

This document provides detailed guidance for each step of the learning process.

## Table of Contents

1. [Root Cause Analysis Techniques](#root-cause-analysis-techniques)
2. [Red Flag Pattern Library](#red-flag-pattern-library)
3. [Safeguard Level Decision Guide](#safeguard-level-decision-guide)
4. [Documentation Best Practices](#documentation-best-practices)
5. [MCP Memory Integration](#mcp-memory-integration)
6. [Common Mistake Categories](#common-mistake-categories)

---

## Root Cause Analysis Techniques

### Five Whys Method

**Purpose**: Drill down from symptom to root cause

**Process**:
1. State the problem as specifically as possible
2. Ask "Why did this happen?" → Answer
3. Take that answer and ask "Why did THAT happen?" → Answer
4. Continue 3-5 times until you reach a systemic issue
5. The final "why" is usually the root cause

**Example** (File Ownership Error):
```
Problem: Edited installed file instead of source

Why 1: Why did you edit the installed file?
→ Because that's where I found the bug

Why 2: Why didn't you check if it was the source?
→ Because I had "fix it where I found it" instinct

Why 3: Why did that instinct override the verification step?
→ Because I didn't have a habit of checking file ownership

Why 4: Why isn't there a habit/protocol for this?
→ Because there's no automated reminder or enforcement

Why 5: Why no automation?
→ ROOT CAUSE: System lacks file ownership verification in workflow
```

### Mental Model Analysis

**Purpose**: Identify flawed assumptions and thinking patterns

**Questions to Ask**:
1. What did I believe was true?
2. What was actually true?
3. Why did I believe the wrong thing?
4. What information did I ignore?
5. What pattern was I following?

**Common Mental Model Failures**:

| Mental Model | Manifestation | Reality | Fix |
|--------------|---------------|---------|-----|
| "Fix it where I found it" | Edit any file with a bug | Files may be derived/installed | Verify ownership first |
| "If it works, it's right" | Test passes = correct solution | May work by accident | Understand why it works |
| "Fast is better" | Skip verification to save time | Verification prevents rework | Verification IS fast |
| "I know this pattern" | Apply familiar solution | Context may differ | Verify applicability |
| "It's just config" | Casual about configuration | Config can be critical | Treat config as code |

### Context Analysis

**Purpose**: Identify information that was available but ignored

**Process**:
1. List all information sources present at the time
2. Mark which were consulted vs ignored
3. Identify why ignored sources were skipped
4. Determine what they would have revealed

**Information Sources**:
- File paths and directory structure
- Git status and repo context
- Documentation (CLAUDE.md, README, etc.)
- Code comments and commit messages
- Existing patterns in the codebase
- Error messages and warnings
- Tool output (linters, tests, etc.)

**Red Flag**: If multiple sources pointed to the correct approach but were all ignored, it's context blindness.

---

## Red Flag Pattern Library

### File System Red Flags

| Path Pattern | What It Means | Correct Action |
|--------------|---------------|----------------|
| `~/.local/lib/` | Installed library | Find source repo |
| `~/.local/bin/` | Installed executable | Find source repo |
| `/usr/local/` | System package | Never edit |
| `~/.cache/` | Generated/temporary | Never edit |
| `~/.config/` | MAY be symlink | Verify with readlink |
| `/tmp/` | Temporary | Never rely on |
| `node_modules/` | Package dependency | Never edit |
| `.git/` | Git internal | Never edit |

### Git Red Flags

| Signal | What It Means | Correct Action |
|--------|---------------|----------------|
| `git ls-files` fails | Not in repo | Investigate before editing |
| File not staged | May not be tracked | Check intentional |
| `.gitignore` match | Intentionally excluded | Understand why |
| Detached HEAD | Not on a branch | Create branch first |
| Merge conflicts | Conflicting changes | Resolve carefully |
| Large diff | Many changes | Review thoroughly |

### Process Red Flags

| Behavior | What It Indicates | Correct Action |
|----------|-------------------|----------------|
| Skipping docs | Assuming knowledge | Read first |
| No test run | Assuming it works | Test first |
| Direct edit | Bypassing process | Follow workflow |
| Force push | Overwriting history | Understand impact |
| Root/sudo | Elevated permissions | Question necessity |
| Production edit | High risk action | Verify multiple times |

### Instinct Red Flags

| Instinct | Risk | Mitigation |
|----------|------|------------|
| "Just this once" | Shortcuts become habits | Always follow process |
| "It's obvious" | Assumptions unverified | Verify anyway |
| "I've done this before" | Context may differ | Check context |
| "Quick fix" | Technical debt | Do it right |
| "No one will notice" | Hiding problems | Transparency |

---

## Safeguard Level Decision Guide

### Decision Matrix

Use this to choose the appropriate safeguard level:

```
                    FREQUENCY
                Low         High
            ┌───────────┬───────────┐
       High │  Level 2  │  Level 3  │
 SEVERITY   │  or 3     │  or 4     │
            ├───────────┼───────────┤
        Low │  Level 1  │  Level 2  │
            │           │  or 3     │
            └───────────┴───────────┘
```

### Level 1: Documentation (Passive)

**When**: Low severity + Low frequency, or highly contextual

**Characteristics**:
- Relies on human reading and remembering
- No enforcement mechanism
- Good for nuanced situations
- Low overhead

**Examples**:
- Guidelines in CLAUDE.md
- Best practices in README
- Comments in code
- Reference documentation

**Pros**:
- Quick to implement
- Flexible and adaptable
- No performance impact
- Easy to update

**Cons**:
- Can be ignored
- Relies on memory
- Not consistent
- No feedback loop

**When to Choose**:
- Mistake is rare and context-dependent
- Judgment call required (can't automate)
- Low impact if repeated
- High variance in correct approach

### Level 2: Process/Checklist (Semi-Active)

**When**: Medium severity or medium frequency

**Characteristics**:
- Structured workflow
- Manual execution
- Active reminder
- Verification steps

**Examples**:
- Pre-commit checklists
- Workflow documentation
- Decision trees
- Review processes

**Pros**:
- More consistent than docs
- Provides structure
- Can be adapted to context
- Creates awareness

**Cons**:
- Can be skipped under pressure
- Requires discipline
- Not foolproof
- Manual overhead

**When to Choose**:
- Mistake happens occasionally
- Requires human judgment
- Medium impact if repeated
- Pattern is learnable

### Level 3: Automation/Validation (Active)

**When**: High severity or high frequency

**Characteristics**:
- Automated checks
- Immediate feedback
- Consistent enforcement
- Prevents errors

**Examples**:
- Pre-commit hooks
- CI/CD checks
- Linters and formatters
- Validation scripts

**Pros**:
- Reliable and consistent
- Immediate feedback
- No human memory required
- Scales well

**Cons**:
- Development overhead
- May have false positives
- Can be bypassed (with effort)
- Maintenance required

**When to Choose**:
- Mistake is common
- Detection is automatable
- High impact if repeated
- Clear right/wrong answer

### Level 4: Architecture (Preventive)

**When**: Critical errors with systemic impact

**Characteristics**:
- Redesign to prevent error class
- Makes error impossible
- Architectural change
- Long-term solution

**Examples**:
- Separate source/install directories
- Type systems preventing invalid states
- Capability-based security
- Immutable infrastructure

**Pros**:
- Eliminates entire error class
- No ongoing enforcement needed
- Long-term solution
- Systemic improvement

**Cons**:
- High initial cost
- May require major refactoring
- Can be over-engineering
- Long implementation time

**When to Choose**:
- Mistake has severe consequences
- Affects many systems/users
- Automation isn't enough
- Pattern repeats despite safeguards

### Implementation Examples

**Level 1 Example** (Documentation):
```markdown
## File Editing Best Practices

Before editing configuration files:
1. Check if file is tracked in git
2. Verify not in installation directory
3. Consider if symlinked from source
```

**Level 2 Example** (Checklist):
```markdown
## Pre-Edit Verification Checklist

- [ ] Run: `git ls-files --error-unmatch <file>`
- [ ] If fails, run: `readlink -f <file>`
- [ ] Check path is not in ~/.local/ or ~/.cache/
- [ ] Verify understanding of file's purpose
```

**Level 3 Example** (Automation):
```bash
#!/bin/bash
# Pre-commit hook: Verify file ownership

for file in $(git diff --cached --name-only); do
  if ! git ls-files --error-unmatch "$file" &>/dev/null; then
    echo "ERROR: $file not tracked in repo"
    exit 1
  fi
done
```

**Level 4 Example** (Architecture):
```
Redesign:
- All source code in ~/repos/
- All installed code in ~/.local/
- Never edit ~/.local/ directly
- Installer creates from source only
- Make ~/.local/ read-only except during install
```

---

## Documentation Best Practices

### Writing Style

**Do**:
- Use active voice ("I edited" not "was edited")
- Be specific (file paths, commands, exact text)
- Include code examples and outputs
- Use markdown formatting
- Cross-reference related docs
- Make it scannable (headers, bullets)

**Don't**:
- Use vague language ("somewhere", "some file")
- Omit important details
- Write walls of text
- Skip code examples
- Create orphaned docs (no links to/from)
- Use jargon without explanation

### Structure

**Analysis Document** (Comprehensive):
```
1. Executive summary (2-3 sentences)
2. The error (what was wrong)
3. Root cause analysis (why it happened)
4. Red flags (what should have stopped it)
5. Proper workflow (correct approach)
6. Learning mechanisms (what was created)
7. Takeaway (key lesson)
```

**Summary Document** (Executive):
```
1. What/why/impact (overview)
2. Root cause (mental model)
3. Proper fix (what was done)
4. Learning mechanisms (checklist)
5. New protocols (procedures)
6. Commits (git references)
7. Takeaway (one sentence)
```

### Length Guidelines

| Document Type | Target Length | Max Length | Purpose |
|---------------|---------------|------------|---------|
| Analysis | 150-200 lines | 300 lines | Deep reference |
| Summary | 100-150 lines | 200 lines | Quick reference |
| CLAUDE.md entry | 20-40 lines | 60 lines | Active enforcement |
| Workflow log | 5-8 lines | 15 lines | Session tracking |

**Rule**: If document exceeds max length, split into multiple files or create REFERENCE.md

### Code Examples

**Do**:
```bash
# Good: Shows context, command, and expected output
$ git ls-files --error-unmatch ~/.local/lib/secrets/secrets.sh
error: pathspec '~/.local/lib/secrets/secrets.sh' did not match any file(s) known to git

# This tells us the file is NOT in the current repo
```

**Don't**:
```bash
# Bad: No context or explanation
git ls-files file.sh
```

### Cross-Referencing

**Create a Web of Documentation**:
```
docs/learning/README.md
├── Links to all incidents
├── Categorizes by type
└── Points to TEMPLATES.md

docs/learning/incident-YYYY-MM-DD.md
├── References SUMMARY-YYYY-MM-DD.md
├── References related incidents
└── Links to affected files

CLAUDE.md
├── References docs/learning/
└── Cites specific incidents as examples
```

---

## MCP Memory Integration

### When to Use MCP Memory

**Use When**:
- MCP memory server is available
- Lesson should be machine-queryable
- Pattern might recur
- Related to other stored lessons

**Skip When**:
- MCP not configured
- One-time unique situation
- Already well-documented elsewhere
- Low value for future queries

### Loading MCP Tool

```javascript
// Use ToolSearch to load memory tool
await toolSearch.search("select:mcp__memory__store_memory");
```

### Storage Format

**Complete Example**:
```json
{
  "name": "lesson-2026-03-11-external-dep-edit",
  "content": {
    "date": "2026-03-11",
    "error": "Edited installed library ~/.local/lib/secrets/secrets.sh instead of source ~/repos/secrets/secrets.sh",
    "root_cause": "Mental model failure: 'fix it where I found it' instinct without verifying file ownership",
    "lesson": "Always verify file ownership with git ls-files before editing any file",
    "safeguards": [
      "Added File Editing Safety Protocol to global CLAUDE.md",
      "Created DEPENDENCIES.md tracking external dependencies",
      "Added pre-edit verification checklist"
    ],
    "severity": "High",
    "files_affected": [
      "~/.local/lib/secrets/secrets.sh",
      "~/repos/secrets/secrets.sh",
      "config/claude/CLAUDE.md",
      "DEPENDENCIES.md"
    ],
    "proper_workflow": "1. Run git ls-files check, 2. Check readlink if symlink, 3. Find source in installers/ or DEPENDENCIES.md, 4. Edit source, 5. Reinstall",
    "red_flags": [
      "Path was ~/.local/lib/ (installation directory)",
      "git ls-files would have failed",
      "CLAUDE.md mentioned external dependency",
      "installer shows source location"
    ],
    "documentation": {
      "analysis": "docs/learning/judgment-error-analysis.md",
      "summary": "docs/learning/LEARNING-SUMMARY-2026-03-11.md"
    }
  },
  "tags": [
    "lesson-learned",
    "file-editing",
    "external-deps",
    "high-severity",
    "mental-model-failure",
    "verification-skipped"
  ]
}
```

### Tag Strategy

**Categories** (use multiple):

1. **Type**: Always include
   - `lesson-learned`

2. **Category**: What was the mistake about?
   - `file-editing`, `git-workflow`, `architecture-decision`
   - `security`, `dependencies`, `deployment`
   - `testing`, `documentation`, `configuration`

3. **System**: What was affected?
   - `dotfiles`, `external-deps`, `infrastructure`
   - `ci-cd`, `tooling`, `environment`

4. **Severity**: How bad was it?
   - `high-severity`, `medium-severity`, `low-severity`

5. **Pattern**: What type of failure?
   - `mental-model-failure`, `context-blindness`
   - `verification-skipped`, `instinct-over-analysis`
   - `assumption-unverified`, `process-shortcut`

**Example Tag Sets**:
```
File editing error: [lesson-learned, file-editing, external-deps, high-severity, mental-model-failure]
Git workflow issue: [lesson-learned, git-workflow, dotfiles, medium-severity, process-shortcut]
Security leak: [lesson-learned, security, configuration, high-severity, context-blindness]
```

### Querying Stored Lessons

**By tag**:
```
Search: tag:file-editing
Returns: All file editing lessons
```

**By pattern**:
```
Search: tag:mental-model-failure
Returns: All mental model failures
```

**By severity**:
```
Search: tag:high-severity
Returns: All high-severity incidents
```

**Combined**:
```
Search: tag:file-editing tag:high-severity
Returns: High-severity file editing lessons
```

---

## Common Mistake Categories

### Category 1: File Ownership Errors

**Pattern**: Editing installed/derived files instead of source

**Examples**:
- Editing `~/.local/lib/` instead of `~/repos/`
- Modifying `node_modules/` instead of source package
- Changing generated files instead of templates

**Root Causes**:
- "Fix it where I found it" instinct
- Not understanding install vs source distinction
- Skipping ownership verification

**Safeguards**:
- Level 1: Document in CLAUDE.md
- Level 2: Pre-edit checklist
- Level 3: git ls-files verification hook

### Category 2: Context Blindness

**Pattern**: Information was available but ignored

**Examples**:
- Documentation exists but not read
- File path indicates type but not noticed
- Existing patterns in codebase not followed

**Root Causes**:
- Rushing to solution
- Overconfidence in existing knowledge
- Not consulting multiple sources

**Safeguards**:
- Level 1: "Read docs first" protocol
- Level 2: Required documentation checklist
- Level 3: CI checks for common patterns

### Category 3: Verification Skipped

**Pattern**: Acting without verifying assumptions

**Examples**:
- Not testing before committing
- Not reading full error message
- Assuming without checking

**Root Causes**:
- Time pressure
- Overconfidence
- "It's obvious" thinking

**Safeguards**:
- Level 1: "Test first" principle
- Level 2: Pre-commit verification checklist
- Level 3: Required CI passing

### Category 4: Process Shortcuts

**Pattern**: Skipping established workflow steps

**Examples**:
- Direct commit to main instead of PR
- Force push without checking
- Skipping code review

**Root Causes**:
- Perceived efficiency
- Impatience
- Underestimating risk

**Safeguards**:
- Level 2: Workflow documentation
- Level 3: Branch protection rules
- Level 4: Architectural enforcement

### Category 5: Mental Model Failures

**Pattern**: Acting on incorrect understanding of system

**Examples**:
- Wrong model of how system works
- Incorrect assumptions about behavior
- Misunderstanding dependencies

**Root Causes**:
- Incomplete knowledge
- Outdated understanding
- Incorrect inference

**Safeguards**:
- Level 1: Architecture documentation
- Level 2: Onboarding materials
- Level 3: Integration tests
- Level 4: Type system / compile-time checks

---

## Additional Resources

### Related Documentation
- Main skill: `SKILL.md`
- Templates: `TEMPLATES.md`
- Examples: `EXAMPLES.md`
- Historical incidents: `../../docs/learning/`

### External References
- Five Whys: https://en.wikipedia.org/wiki/Five_whys
- Root Cause Analysis: https://en.wikipedia.org/wiki/Root_cause_analysis
- Post-Mortem Culture: Site Reliability Engineering book, Chapter 15

### Tools
- MCP Memory: For persistent storage
- Git: For version control of learning docs
- Grep: For searching patterns across codebase
- ToolSearch: For loading MCP tools
