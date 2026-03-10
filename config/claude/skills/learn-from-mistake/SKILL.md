---
name: learn-from-mistake
description: Guides structured post-mortem analysis after making a judgment error or mistake. Creates documentation in docs/learning/, updates safeguards in CLAUDE.md, and stores lessons in persistent memory. Use when you realize a mistake was made, when user says "I made a mistake", "that was wrong", "I shouldn't have done that", or after fixing something the wrong way.
allowed-tools: Read, Grep, Glob, Bash, Write, Edit, ToolSearch
context: fork
---

# Learn From Mistake - Systematic Learning Skill

## Purpose

Transform mistakes into systematic improvements through structured post-mortem analysis. This skill guides you through:

1. Understanding what happened and why
2. Analyzing root causes and mental model failures
3. Documenting the proper approach
4. Creating appropriate safeguards
5. Storing lessons in persistent memory

## Quick Start

When a mistake is identified:

1. **If not fixed yet**: Fix it properly first, then come back here
2. **Invoke this skill**: Let Claude auto-detect or use manually
3. **Follow the 8-step process**: Structured workflow below
4. **Review outputs**: Analysis + summary docs in `docs/learning/`
5. **Commit**: Save to git for future reference

## When to Use

**Trigger Scenarios**:
- You edited the wrong file (e.g., installed vs source)
- You made an incorrect assumption that led to bugs
- You skipped a verification step and it caused issues
- You broke something by acting too quickly
- You realize "I should have checked X first"
- User says "I made a mistake" or "that was wrong"

**Not For**:
- Simple typos or syntax errors (just fix them)
- Expected failures during development (normal iteration)
- External system issues (not your mistake)

## 8-Step Process

### Step 1: Incident Capture (5 min)

**Goal**: Document what happened at a high level

**Questions**:
- What was the mistake?
- What was the impact/severity? (High/Medium/Low)
- Has it been fixed yet? (If no, fix first before continuing)
- What files/systems were affected?
- When did it happen? (date/time)

**Output**: Brief summary (2-3 sentences)

**Template**:
```
Mistake: [One sentence description]
Impact: [High/Medium/Low] - [Why it matters]
Status: [Fixed/Not Fixed]
Affected: [List of files/systems]
Date: YYYY-MM-DD
```

### Step 2: Root Cause Analysis (10 min)

**Goal**: Understand WHY the mistake happened (not just what)

**Method**: Use "Five Whys" technique

1. **What happened?** (immediate action)
2. **Why did you do that?** (mental model)
3. **Why did that model fail?** (context/assumptions)
4. **Why didn't you catch it?** (missing verification)
5. **Why doesn't the system prevent this?** (systematic gap)

**Focus Areas**:
- **Mental Model Failures**: What did you assume that was wrong?
- **Context Blindness**: What information was available but ignored?
- **Process Gaps**: What verification step was skipped?
- **Instinct vs Analysis**: Did you rush without thinking?

**Example** (from 2026-03-11 incident):
```
1. What: Edited installed library instead of source
2. Why: "Fix it where I found it" instinct
3. Why fail: Didn't verify file ownership first
4. Why not catch: Skipped git ls-files check
5. Why no prevention: No automated verification in workflow
```

**Output**: 3-5 paragraphs explaining the chain of causation

### Step 3: Red Flags Analysis (5 min)

**Goal**: Identify warning signs that were present but missed

**Questions**:
- What signals should have triggered "wait, let me think about this"?
- What patterns matched known anti-patterns?
- What checks did you skip?
- What assumptions did you make without verification?

**Common Red Flags**:
- File path in `~/.local/`, `~/.cache/`, `/usr/local/`
- Editing file not tracked in current git repo
- Making changes to system packages or external deps
- Skipping documentation lookup
- Acting on first solution without considering alternatives
- Rushing due to time pressure or impatience

**Output**: Bulleted list of specific red flags

**Template**:
```markdown
### Red Flags That Should Have Stopped Me:

1. **[Signal Type]**: [What was visible]
   - Why it matters: [What it indicates]
   - What should have happened: [Correct response]

2. **[Signal Type]**: [What was visible]
   - Why it matters: [What it indicates]
   - What should have happened: [Correct response]
```

### Step 4: Proper Workflow Documentation (10 min)

**Goal**: Document the CORRECT way to handle this situation

**Questions**:
- What is the right sequence of steps?
- What verification is needed at each step?
- What are the edge cases to consider?
- What's the decision tree for different scenarios?

**Structure**:
1. Initial state / problem identification
2. Verification steps (BEFORE taking action)
3. Action steps (WITH safeguards)
4. Validation steps (AFTER completion)
5. Edge cases and exceptions

**Output**: Step-by-step procedure

**Template**:
```markdown
### Proper Workflow for [Scenario]:

#### Before Acting:
1. [Verification step 1]
2. [Verification step 2]
3. [Decision point]

#### Action Steps:
1. [Step with safeguard]
2. [Step with safeguard]
3. [Step with safeguard]

#### After Completion:
1. [Validation check 1]
2. [Validation check 2]

#### Edge Cases:
- If [condition]: [Alternative approach]
- If [condition]: [Alternative approach]
```

### Step 5: Create Learning Documentation (15 min)

**Goal**: Create permanent documentation in `docs/learning/`

Create two files:

#### A. Analysis Document (Comprehensive)

**File**: `docs/learning/incident-YYYY-MM-DD-short-name.md`

**Contents**:
- The error (what was done wrong)
- Root cause analysis (from Step 2)
- Red flags missed (from Step 3)
- Proper workflow (from Step 4)
- Learning mechanisms implemented (from Step 6)
- Takeaway (one key lesson)

**Template**: See `docs/learning/judgment-error-analysis.md`

**Length**: 150-250 lines (comprehensive but focused)

#### B. Summary Document (Executive)

**File**: `docs/learning/SUMMARY-YYYY-MM-DD.md`

**Contents**:
- What/Why/Impact (3-5 sentences)
- The proper fix (what was done correctly)
- Learning mechanisms (checklist)
- New protocols (step-by-step)
- Commits (links to git commits)
- Key takeaway

**Template**: See `docs/learning/LEARNING-SUMMARY-2026-03-11.md`

**Length**: 100-150 lines (executive summary)

**Naming Convention**:
- Use incident date: `YYYY-MM-DD`
- Use short name: `external-dep-edit`, `wrong-file-edit`, etc.
- Be specific but concise

### Step 6: Determine and Implement Safeguards (10 min)

**Goal**: Create appropriate safeguards to prevent recurrence

**Safeguard Levels** (choose based on severity and frequency):

#### Level 1: Documentation (Passive)
**When**: Low frequency, low severity, or highly contextual
**What**: Add to CLAUDE.md, README, or reference docs
**Example**: "Always check X before doing Y"

#### Level 2: Process/Checklist (Semi-Active)
**When**: Medium frequency, medium severity
**What**: Add to workflow steps, create decision trees
**Example**: Checklists in skills, verification scripts

#### Level 3: Automation/Validation (Active)
**When**: High frequency or high severity
**What**: Pre-commit hooks, validation scripts, CI checks
**Example**: `git ls-files` check before edits

#### Level 4: Architecture (Preventive)
**When**: Critical errors with widespread impact
**What**: Change system design to make error impossible
**Example**: Separate source and install directories

**Decision Matrix**:
```
High Frequency + High Severity = Level 3 or 4
High Frequency + Low Severity = Level 2 or 3
Low Frequency + High Severity = Level 2 or 3
Low Frequency + Low Severity = Level 1
```

**Implementation**:

For Level 1 (Documentation):
- Add to project `CLAUDE.md` OR global `~/.claude/CLAUDE.md`
- Add to `docs/learning/README.md`
- Create/update reference docs

For Level 2 (Process):
- Add to skill instructions
- Create decision trees
- Update workflow_state.md templates

For Level 3 (Automation):
- Create validation scripts in `util-scripts/`
- Add to pre-commit hooks (if appropriate)
- Create testing scripts

For Level 4 (Architecture):
- Document architectural change
- Implement across codebase
- Update all related systems

**Output**: Determine level and implement safeguard

### Step 7: Store in Persistent Memory (5 min)

**Goal**: Make lesson queryable for future reference

**Use**: MCP memory server (if available)

**Load Memory Tool**:
```
Use ToolSearch to load: "select:mcp__memory__store_memory"
```

**Store Format**:
```json
{
  "name": "lesson-YYYY-MM-DD-short-name",
  "content": {
    "date": "YYYY-MM-DD",
    "error": "Brief description of mistake",
    "root_cause": "Mental model failure or process gap",
    "lesson": "Key takeaway in one sentence",
    "safeguards": ["List", "of", "mechanisms", "created"],
    "severity": "High|Medium|Low",
    "files_affected": ["file1", "file2"],
    "proper_workflow": "Brief description of correct approach"
  },
  "tags": ["lesson-learned", "mistake-category", "affected-system"]
}
```

**Tags to Use**:
- `lesson-learned` (always)
- Category: `file-editing`, `git-workflow`, `architecture`, `security`, etc.
- System: `dotfiles`, `external-deps`, `infrastructure`, etc.
- Severity: `high-severity`, `medium-severity`, `low-severity`

**Output**: Confirmation of storage

### Step 8: Verify and Close (5 min)

**Goal**: Ensure everything is complete and committed

**Checklist**:
- [ ] Proper fix is applied (if applicable)
- [ ] Analysis document created in `docs/learning/`
- [ ] Summary document created in `docs/learning/`
- [ ] Safeguards implemented (at appropriate level)
- [ ] CLAUDE.md updated (if applicable)
- [ ] Memory stored (if MCP available)
- [ ] `workflow_state.md` log updated
- [ ] Git commits created

**Git Commits**:
Create atomic commits for:
1. The proper fix (if in this repo)
2. Documentation (analysis + summary)
3. Safeguards (CLAUDE.md updates, new scripts, etc.)

**Commit Message Format**:
```
docs: learning from [mistake-name] incident

- Add root cause analysis
- Add executive summary
- Update CLAUDE.md with [safeguard type]
- Store lesson in persistent memory

Incident: YYYY-MM-DD
Severity: [High/Medium/Low]
```

**Final Output**: Summary of what was created and where

## Example Workflow

**Scenario**: User says "I edited the installed library instead of the source"

### Step 1: Capture
```
Mistake: Edited ~/.local/lib/secrets/secrets.sh instead of ~/repos/secrets/secrets.sh
Impact: High - Fix would be lost on next install
Status: Fixed in source repo
Affected: nuvemlabs/secrets repo, dotfiles installer
Date: 2026-03-11
```

### Step 2: Root Cause
"Mental model failure: 'Fix it where I found it' instinct. Didn't verify file ownership with git ls-files. Ignored context clue that ~/.local/lib/ is an installation directory."

### Step 3: Red Flags
- Path was `~/.local/lib/` (installation directory)
- `git ls-files` would have failed
- CLAUDE.md mentioned "nuvemlabs/secrets as external dependency"
- Installer shows source at `~/repos/secrets`

### Step 4: Proper Workflow
1. Run `git ls-files --error-unmatch <path>`
2. If fails, check if symlink: `readlink -f <path>`
3. If neither, check `installers/` or `DEPENDENCIES.md` for source
4. Edit source, commit, reinstall

### Step 5: Create Docs
- `docs/learning/incident-2026-03-11-external-dep-edit.md`
- `docs/learning/SUMMARY-2026-03-11.md`

### Step 6: Safeguards
Level 1: Add to CLAUDE.md "File Editing Safety Protocol"
Level 2: Create `DEPENDENCIES.md` tracking external deps
Level 3: (Skipped - would be pre-edit hook)

### Step 7: Memory
Stored with tags: `lesson-learned`, `file-editing`, `external-deps`, `high-severity`

### Step 8: Verify
All commits made, workflow_state.md updated, lesson complete.

## Tips

### Do:
- Be thorough in root cause analysis (dig deep)
- Focus on mental models, not just facts
- Create actionable safeguards
- Use existing incidents in `docs/learning/` as templates
- Store in persistent memory for future reference
- Make documentation scannable (headers, bullets, code blocks)

### Don't:
- Skip root cause analysis (it's the most important part)
- Blame individuals (focus on process and systems)
- Create only documentation without implementation
- Forget to test the safeguards
- Leave `workflow_state.md` without logging the incident
- Create overly long documents (keep focused)

### Writing Style:
- Use active voice ("I did X" not "X was done")
- Be specific ("~/.local/lib/" not "installation directory")
- Include code examples and file paths
- Use markdown formatting (headers, lists, code blocks)
- Cross-reference related docs

## Integration Points

This skill integrates with:

- **`docs/learning/`**: Knowledge base and templates
- **CLAUDE.md**: Safety protocols and rules
- **workflow_state.md**: Incident logging
- **MCP Memory**: Persistent lesson storage
- **DEPENDENCIES.md**: External dependency tracking
- **Git**: Version control for all learning artifacts

## Success Criteria

A successful learning session produces:

1. **Clear Understanding**: Root cause is identified and documented
2. **Complete Documentation**: Both analysis and summary exist
3. **Appropriate Safeguards**: Right level for severity/frequency
4. **Persistent Storage**: Lesson stored in MCP memory
5. **Git History**: Commits created for all artifacts
6. **Verification**: Safeguards tested and working

## Reference

For detailed information, see:

- **[TEMPLATES.md](TEMPLATES.md)**: Document templates and formats
- **[REFERENCE.md](REFERENCE.md)**: Detailed guides for each step
- **[EXAMPLES.md](EXAMPLES.md)**: Real incidents from docs/learning/
- **`docs/learning/`**: Historical incidents and analysis

## Notes

- This skill uses `context: fork` to run in isolated sub-agent
- Uses `ToolSearch` to load MCP memory tool when needed
- Creates files in `docs/learning/` (not temporary)
- Updates permanent files like CLAUDE.md
- All outputs are version controlled with git
