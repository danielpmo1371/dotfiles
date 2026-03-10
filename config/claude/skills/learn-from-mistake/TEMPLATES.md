# Documentation Templates

This file provides copy-paste templates for creating learning documentation.

## Template 1: Analysis Document (Comprehensive)

**File**: `docs/learning/incident-YYYY-MM-DD-short-name.md`

```markdown
# Root Cause Analysis: [Mistake Description]

## Date: YYYY-MM-DD

## The Error

[Describe what was done wrong in 2-3 sentences]

### What Was Done

[Show the incorrect action with code/commands if applicable]

### What Should Have Been Done

[Show the correct action with code/commands]

## Root Cause Analysis

### 1. Why This Mistake Happened

**Mental Model Failure: "[Name the flawed mental model]"**
- [Describe the incorrect assumption or instinct]
- [Explain why this seemed right at the time]
- [Identify the gap in understanding]

**Missing Verification Step: "[Name the skipped check]"**
- [What check was skipped]
- [Why it was skipped]
- [What it would have revealed]

**Context Blindness**
- [What information was available but not noticed]
- [Where this information existed (docs, file paths, etc.)]
- [Why it was ignored or missed]

### 2. What Signals Should Have Triggered "Wait..."

**Red Flags That Should Have Stopped Me:**

1. **[Signal Category]**: [Specific signal]
   - What it means: [Interpretation]
   - What should happen: [Correct response]

2. **[Signal Category]**: [Specific signal]
   - What it means: [Interpretation]
   - What should happen: [Correct response]

3. **[Signal Category]**: [Specific signal]
   - What it means: [Interpretation]
   - What should happen: [Correct response]

### 3. Proper Fix Location / Workflow

**[Correct Approach]:**
- Step 1: [Verification]
- Step 2: [Action]
- Step 3: [Validation]
- Step 4: [Documentation]

**Fix Persistence Strategy:**
1. [How to make fix permanent]
2. [How to avoid reverting]
3. [How to propagate to all systems]

## Learning Mechanisms Implemented

### A. Documentation
**File**: [Path to file updated]
**Section**: [Section name]
**Content**: [Brief description of what was added]

### B. Process Changes
**Workflow**: [Workflow name]
**Changes**: [What changed in the process]
**Enforcement**: [How it's enforced - manual/automated]

### C. Automation (if applicable)
**Tool**: [Script or hook name]
**Function**: [What it does]
**Location**: [File path]

### D. Memory Storage
**MCP Memory**: [Yes/No]
**Tags**: [List of tags]
**Key**: [Memory key]

## Takeaway

**[One sentence key lesson]**

[Optional: 1-2 paragraphs elaborating on the lesson and its broader implications]

**New habit: [Specific behavior change]**
```

## Template 2: Summary Document (Executive)

**File**: `docs/learning/SUMMARY-YYYY-MM-DD.md`

```markdown
# Learning Summary: [Short Title]

**Date**: YYYY-MM-DD
**Error Type**: [Category of mistake]
**Severity**: [High/Medium/Low] - [Impact description]
**Status**: ✅ Fixed + Documented

---

## What Happened

### The Bug/Issue
[2-3 sentences describing the problem that was encountered]

### The Mistake
[2-3 sentences describing what was done wrong]

### Why This Is Critical
- [Point 1: Why it matters]
- [Point 2: Consequence if not caught]
- [Point 3: Similar to what other pattern]

---

## Root Cause: Mental Model Failure

### What I Did Wrong
1. **[Failure 1]**: [Description]
2. **[Failure 2]**: [Description]
3. **[Failure 3]**: [Description]

### What I Should Have Done
1. [Correct step 1]
2. [Correct step 2]
3. [Correct step 3]

---

## The Proper Fix

### 1. [Fix Step 1 Name]

**File**: [Path to file]

**Change**:
```[language]
[Show the code/config change]
```

**Committed**: [Repo name], commit [`hash`](link-if-available)

### 2. [Fix Step 2 Name]

[Repeat pattern for each fix step]

### 3. [Fix Step 3 Name]

[Verification or validation step]

---

## Learning Mechanisms Implemented

### 1. [Mechanism Name]
**File**: [Path]
- [What it does]
- [How it helps]

### 2. [Mechanism Name]
**File**: [Path]
- [What it does]
- [How it helps]

### 3. [Mechanism Name]
**File**: [Path]
- [What it does]
- [How it helps]

### 4. [Mechanism Name]
**File**: [Path]
- [What it does]
- [How it helps]

### 5. MCP Memory Storage
**Stored**: [Yes/No]
- Tags: [Comma-separated tags]
- Queryable for future reference

---

## New Safety Protocol

### Before [Action Type]:

**Step 1**: [Verification]
```bash
[Command to run]
```

**Step 2**: [Check condition]
```bash
[Command to run]
```

**Step 3**: [Decision point]
- If [condition]: [Action A]
- Else: [Action B]

**Step 4**: [Final validation]

### Exception Cases
[When the rule doesn't apply]

---

## Commits

### [Repo 1 Name]
```
[hash] [commit message]
```

### [Repo 2 Name]
```
[hash] [commit message]
```

---

## Files Created/Modified

### Created
- `[path]` ([line count] lines - [description])
- `[path]` ([line count] lines - [description])

### Modified
- `[path]` ([section modified])
- `[path]` ([section modified])

---

## Impact

### Immediate
✅ [Outcome 1]
✅ [Outcome 2]
✅ [Outcome 3]

### Long-Term
✅ [Systematic improvement 1]
✅ [Systematic improvement 2]
✅ [Systematic improvement 3]

---

## Takeaway

**[One sentence key lesson]**

This wasn't a [type] error—it was a **[root cause type]** error. [2-3 sentences explaining the deeper lesson and how the system now prevents this class of errors, not just this specific instance]

### New Habit
**[Specific behavior change in bold]**

If [trigger] → [new action]

---

## Next Steps

### [Affected System 1]
- ✅ [Completed item]
- ✅ [Completed item]
- ⏳ [Future improvement]

### [Affected System 2]
- ✅ [Completed item]
- ⏳ [Future improvement]

### Future Enhancements
- [Possible improvement 1]
- [Possible improvement 2]
- [Possible improvement 3]

---

## Conclusion

[2-3 sentences summarizing the value extracted from the mistake: how the learning mechanisms ensure this class of error won't recur, and how the system is now better than before the mistake happened]

**The system learned, and will not make this mistake again.**
```

## Template 3: MCP Memory Storage

**Format**:
```json
{
  "name": "lesson-YYYY-MM-DD-short-name",
  "content": {
    "date": "YYYY-MM-DD",
    "error": "Brief one-line description of what was done wrong",
    "root_cause": "Mental model failure or process gap identified",
    "lesson": "Key takeaway in one sentence",
    "safeguards": [
      "Safeguard 1 description",
      "Safeguard 2 description",
      "Safeguard 3 description"
    ],
    "severity": "High|Medium|Low",
    "files_affected": [
      "path/to/file1",
      "path/to/file2"
    ],
    "proper_workflow": "Brief step-by-step of correct approach",
    "red_flags": [
      "Red flag 1 that was missed",
      "Red flag 2 that was missed"
    ],
    "documentation": {
      "analysis": "docs/learning/incident-YYYY-MM-DD-short-name.md",
      "summary": "docs/learning/SUMMARY-YYYY-MM-DD.md"
    }
  },
  "tags": [
    "lesson-learned",
    "mistake-category",
    "affected-system",
    "severity-level"
  ]
}
```

**Tag Categories**:
- **Always**: `lesson-learned`
- **Category**: `file-editing`, `git-workflow`, `architecture-decision`, `security`, `dependencies`, `deployment`, `testing`, `documentation`
- **System**: `dotfiles`, `external-deps`, `infrastructure`, `ci-cd`, `configuration`, `tooling`
- **Severity**: `high-severity`, `medium-severity`, `low-severity`
- **Pattern**: `mental-model-failure`, `context-blindness`, `verification-skipped`, `instinct-over-analysis`

## Template 4: CLAUDE.md Safety Rule Addition

**Format**:
```markdown
## [Category Name] Safety Rules

**MANDATORY CHECK: [What must be verified]**

[Detailed explanation of the rule and why it exists]

**Warning Signs:**
- [Pattern 1] → [What it indicates]
- [Pattern 2] → [What it indicates]
- [Pattern 3] → [What it indicates]

**Decision Tree:**
1. [Condition to check]
   - If [result]: [Action A]
   - Else: [Action B]

2. [Next condition to check]
   - If [result]: [Action C]
   - Else: [Action D]

**Never assume [common wrong assumption].**

[Explanation of consequences if rule is violated]
```

## Template 5: Workflow State Log Entry

**Format**:
```markdown
- [YYYY-MM-DD] [CATEGORY IN CAPS]
  - [Brief description of what happened]
  - [Key action taken]
  - [Result/outcome]
  - [Reference to documentation if applicable]
  - [New protocol or rule established]
```

**Example**:
```markdown
- [2026-03-11] JUDGMENT ERROR ANALYSIS & LEARNING
  - Identified critical error: edited installed library instead of source
  - Created comprehensive analysis: docs/learning/judgment-error-analysis.md
  - Applied proper fix to source repo: ~/repos/secrets/secrets.sh
  - Committed fix to nuvemlabs/secrets repo (commit 2a32583)
  - Verified fix works in both bash and zsh
  - Updated CLAUDE.md with External Dependency Safety Rules
  - Stored lesson in MCP memory with tags
  - New protocol: Always verify file ownership with git ls-files before editing
```

## Usage Guidelines

### When to Use Each Template

| Template | When to Use | Audience | Length |
|----------|-------------|----------|--------|
| Analysis | Always (comprehensive record) | Future self, deep reference | 150-250 lines |
| Summary | Always (executive overview) | Quick reference, onboarding | 100-150 lines |
| MCP Memory | If MCP available | Machine-queryable | JSON |
| CLAUDE.md | High/medium severity | Active enforcement | 20-50 lines |
| Workflow Log | Always | Session tracking | 5-10 lines |

### Customization

These templates are starting points. Adapt based on:
- **Severity**: Higher severity = more detail in safeguards
- **Complexity**: More complex errors = more detailed analysis
- **Novelty**: New error types = more explanation
- **Impact**: Wider impact = more comprehensive documentation

### File Naming

**Pattern**: `[type]-YYYY-MM-DD[-short-name].md`

**Examples**:
- `incident-2026-03-11-external-dep-edit.md`
- `SUMMARY-2026-03-11.md`
- `analysis-2026-04-15-wrong-branch-deploy.md`
- `lesson-2026-05-20-security-leak.md`

**Rules**:
- Always include date (YYYY-MM-DD)
- Use lowercase with hyphens
- Short name should be 2-4 words
- Be specific but concise
