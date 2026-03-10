# Learning System Integration Plan

## Executive Summary

**Goal**: Transform the judgment error analysis from 2026-03-11 into reusable dotfiles assets that both **prevent** mistakes before they happen and **guide learning** after they occur.

**Strategy**: Combination approach (Prevention + Learning + Reference)

**Assets to Create**:
1. PreToolUse Hook: `file-ownership-guard.sh` (prevention)
2. Skill: `learn-from-mistake` (learning)
3. Keep: `docs/learning/` (reference library)

---

## Background: What Was Done

The previous agent did exceptional work:

### Analysis (216 lines)
- Root cause: "Fix it where I found it" mental model failure
- Red flags: `~/.local/lib/` path, missing git check, context blindness
- Proper workflow: Find source → Fix source → Reinstall

### Documentation (251 lines)
- Executive summary with outcomes
- Comprehensive safety protocols
- New mandatory verification steps
- Commits in both repos (secrets + dotfiles)

### Safety Protocols Added
- Project CLAUDE.md: External Dependency Safety Rules
- Global CLAUDE.md: File Editing Safety Protocol
- MCP Memory: Lesson with queryable tags
- DEPENDENCIES.md: External dep tracking

**Total**: 467+ lines of structured learning documentation

---

## Problem Statement

**Current State**: Excellent documentation exists, but it's passive
- Relies on Claude reading and remembering CLAUDE.md rules
- No enforcement mechanism to catch mistakes in real-time
- Learning process is documented but not systematized

**Desired State**: Active prevention + guided learning
- Automatically catch file ownership errors before edits happen
- Provide structured workflow when mistakes do occur
- Make learning process discoverable and reusable

---

## Option Analysis

### Option 1: Skill Only
❌ **Rejected** - No prevention, only reactive

### Option 2: Command Only
❌ **Rejected** - Requires manual invocation, easy to forget

### Option 3: Agent Only
❌ **Rejected** - Heavyweight for what should be a quick check/guide

### Option 4: Hook Only
⚠️ **Partial** - Prevents mistakes but doesn't help with learning process

### Option 5: Combination (RECOMMENDED)
✅ **Selected** - Defense in depth + systematic learning

**Rationale**:
- Hook provides first line of defense (catches 90% of cases)
- Skill provides structured learning when mistakes still happen
- Existing docs serve as knowledge base and reference
- Layered approach mirrors the original safety rules

---

## Architecture Design

```
Prevention Layer (Before mistake):
  └─ file-ownership-guard.sh (PreToolUse hook)
     ├─ Intercepts Edit/Write calls
     ├─ Validates git ownership
     ├─ Checks for symlinks
     └─ Blocks or warns

Learning Layer (After mistake):
  └─ learn-from-mistake (Skill)
     ├─ Triggered by user ("I made a mistake")
     ├─ Guides structured analysis
     ├─ Creates documentation
     ├─ Updates safeguards
     └─ Stores in memory

Reference Layer (Knowledge base):
  └─ docs/learning/ (existing)
     ├─ Previous incidents
     ├─ Analysis templates
     └─ Protocols library
```

---

## Implementation Details

### 1. Prevention Hook: file-ownership-guard.sh

**Location**: `config/claude/hooks/file-ownership-guard.sh`

**Purpose**: Intercept Edit/Write operations and validate file ownership BEFORE the edit happens

**Logic Flow**:
```bash
1. Read tool_name and tool_input from stdin
2. If not Edit or Write → exit 0 (allow)
3. Extract file_path from tool_input
4. Run git ls-files check:
   - If tracked in repo → exit 0 (allow)
5. Run readlink check:
   - If symlink target is in repo → exit 0 (allow)
6. Check for installation directory patterns:
   - ~/.local/lib/ → BLOCK
   - ~/.local/bin/ → BLOCK
   - /usr/local/ → BLOCK
   - ~/.cache/ → BLOCK
7. Check for external dep patterns:
   - ~/.config/ → WARN (may be symlink, verify first)
8. Exit 2 with helpful message:
   - "File not in repo: <path>"
   - "Appears to be installed dependency at: <location>"
   - "Find source with: Check installers/ or DEPENDENCIES.md"
   - "Or verify symlink: readlink -f <path>"
```

**Error Message Format**:
```
BLOCKED by file-ownership-guard hook:
  File: /Users/daniel/.local/lib/secrets/secrets.sh
  Reason: Not tracked in current git repo
  Location: Appears to be installed dependency

This file is likely managed by an installer and edits will be lost.

Next steps:
  1. Find source: Check installers/ or DEPENDENCIES.md
  2. Edit source repo instead
  3. Re-run installer to apply changes

If this IS correct (e.g., symlink), verify with:
  readlink -f /Users/daniel/.local/lib/secrets/secrets.sh
```

**Features**:
- Clear, actionable error messages
- Helps user find the source
- Explains WHY it's blocked (not just "no")
- Provides escape hatch for false positives

**Logging**:
- All decisions logged to `~/.claude/logs/file-ownership-guard.log`
- Includes timestamp, file path, decision, reason

### 2. Learning Skill: learn-from-mistake

**Location**: `config/claude/skills/learn-from-mistake/SKILL.md`

**Metadata**:
```yaml
---
name: learn-from-mistake
description: Guides structured post-mortem analysis after making a judgment error or mistake. Creates documentation, updates safeguards, and stores lessons in persistent memory. Use when you realize a mistake was made or when user says "I made a mistake", "that was wrong", "I shouldn't have done that".
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
context: fork
---
```

**Workflow Structure**:

```markdown
# Learn From Mistake - Systematic Learning Skill

## Quick Start

When a mistake is identified, this skill guides you through:
1. Understanding what happened
2. Analyzing root causes
3. Documenting the proper approach
4. Creating/updating safeguards
5. Storing the lesson for future reference

## Process

### Step 1: Incident Capture (5 min)
- What was the mistake?
- What was the impact/severity?
- Has it been fixed yet? (If no, fix first)
- What files/systems were affected?

### Step 2: Root Cause Analysis (10 min)
Use the "Five Whys" method:
- Why did this happen? (immediate cause)
- Why did that happen? (mental model)
- Why did that happen? (context/signals)
- What should have prevented it? (missing step)
- How do we ensure it won't recur? (systematic fix)

**Template**: See docs/learning/judgment-error-analysis.md

### Step 3: Red Flags Analysis (5 min)
- What signals were present but missed?
- What warning signs should have triggered "wait..."?
- What checks were skipped?
- What assumptions were made?

### Step 4: Proper Workflow Documentation (10 min)
- What is the CORRECT way to handle this?
- What steps should always be followed?
- What verification is needed?
- What's the decision tree for edge cases?

### Step 5: Create Learning Documentation (15 min)
Create two files in docs/learning/:

**Analysis Document** (comprehensive):
- Full root cause analysis
- Mental model failures
- Red flags and warning signs
- Proper workflow
- Decision trees
- Future improvements

**Summary Document** (executive):
- What/Why/Impact
- Proper fix applied
- Learning mechanisms implemented
- Commits made
- Key takeaway

Use existing docs/learning/ files as templates.

### Step 6: Update Safeguards (10 min)
Determine what level of safeguard is needed:

**Level 1: Documentation**
- Add to CLAUDE.md (project or global)
- Add to DEPENDENCIES.md or other reference
- Passive reminder

**Level 2: Process**
- Add to checklist or workflow
- Add to pre-commit hooks
- Active but manual

**Level 3: Automation**
- Create PreToolUse hook
- Create validation script
- Enforced automatically

**Level 4: Architecture**
- Change directory structure
- Add new abstractions
- Prevent at design level

Choose the right level based on:
- Severity of mistake (high = automation)
- Frequency of pattern (common = automation)
- Ease of detection (easy = automation)

### Step 7: Store in Persistent Memory (5 min)
Store lesson in MCP memory:

```bash
# Use memory MCP to store structured lesson
{
  "key": "lesson-YYYY-MM-DD-short-name",
  "value": {
    "date": "YYYY-MM-DD",
    "error": "Brief description",
    "lesson": "Key takeaway",
    "safeguards": ["List", "of", "mechanisms"],
    "tags": ["lesson-learned", "category", "system"]
  },
  "tags": ["lesson-learned", "mistake-category", "affected-system"]
}
```

### Step 8: Verify and Close (5 min)
- Confirm proper fix is applied
- Verify safeguards are in place
- Test new protocols work
- Update workflow_state.md log
- Create git commits

## Output Format

Create structured documentation following this template:

### docs/learning/incident-YYYY-MM-DD-short-name.md
```markdown
# Root Cause Analysis: [Mistake Description]

Date: YYYY-MM-DD

## The Error
[What was done wrong]

## Root Cause Analysis
### Why This Happened
[Mental model failures]

### Red Flags Missed
[Warning signs that were ignored]

### Proper Workflow
[Correct approach]

## Learning Mechanisms Implemented
[List of safeguards created]

## Takeaway
[Key lesson in one sentence]
```

### docs/learning/SUMMARY-YYYY-MM-DD.md
```markdown
# Learning Summary: [Short Title]

Date: YYYY-MM-DD
Severity: [High/Medium/Low]
Status: ✅ Fixed + Documented

## What Happened
[Brief description]

## Why It Matters
[Impact and consequences]

## The Fix
[What was done correctly]

## Learning Mechanisms
[List of safeguards with checkboxes]

## New Protocols
[Checklists and procedures]

## Commits
[List of commits in affected repos]
```

## Examples

See existing documentation in docs/learning/:
- judgment-error-analysis.md (comprehensive analysis template)
- LEARNING-SUMMARY-2026-03-11.md (executive summary template)

## Tips

**Do:**
- Be thorough in analysis
- Focus on mental models, not just facts
- Create actionable safeguards
- Use existing incidents as templates
- Store in persistent memory

**Don't:**
- Skip root cause analysis
- Blame individuals (focus on process)
- Create only documentation (add automation)
- Forget to test the safeguards
- Leave workflow_state.md without update

## Advanced: Creating Hooks

If the mistake warrants automation (Level 3 safeguard), create a PreToolUse hook:

**Template**: See config/claude/hooks/file-ownership-guard.sh

**Structure**:
```bash
#!/usr/bin/env bash
# Hook name and purpose
# Exit 0 = allow, exit 2 = block

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')
TOOL_INPUT=$(echo "$INPUT" | jq -c '.tool_input')

# Check logic here
if [[ condition ]]; then
  echo "BLOCKED: reason" >&2
  exit 2
fi

exit 0
```

**Add to config/claude/hooks/config.json**:
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "path": "file-ownership-guard.sh",
        "tools": ["Edit", "Write"]
      }
    ]
  }
}
```

## Integration

This skill works with:
- File ownership guard hook (prevention)
- MCP memory (storage)
- docs/learning/ (reference)
- CLAUDE.md (enforcement)
- workflow_state.md (tracking)
```

**Supporting Files**:
- `config/claude/skills/learn-from-mistake/REFERENCE.md` - Detailed guides
- `config/claude/skills/learn-from-mistake/TEMPLATES.md` - Doc templates
- `config/claude/skills/learn-from-mistake/EXAMPLES.md` - Real incidents

### 3. Hook Configuration Updates

**File**: `config/claude/hooks/config.json`

**Changes**:
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "path": "logging/user-request-logger.sh"
      },
      {
        "path": "pipeline-guard.sh",
        "tools": ["mcp__azure-devops__pipelines_run_pipeline"]
      },
      {
        "path": "file-ownership-guard.sh",
        "tools": ["Edit", "Write"]
      }
    ],
    "PreUserResponse": [
      {
        "path": "logging/response-summarizer.sh"
      }
    ]
  },
  "mcpServers": {
    "memory": {
      "endpoint": "http://memory-mcp:8000"
    }
  }
}
```

### 4. Documentation Updates

**CLAUDE.md** (project):
Add reference to new assets under "File Editing Safety Protocol":
```markdown
**Automated Protection**: The file-ownership-guard hook enforces these rules automatically.
If blocked, see error message for guidance on finding the source repository.

**Learning System**: Use /learn-from-mistake skill after any judgment error to create
structured documentation and systematic safeguards.
```

**docs/learning/README.md**:
Add usage section:
```markdown
## Creating New Incident Documentation

Use the `/learn-from-mistake` skill for guided post-mortem analysis:

1. Fix the mistake first (if not already done)
2. Invoke: `/learn-from-mistake` or let Claude auto-detect
3. Follow the structured workflow
4. Review generated documentation
5. Commit to dotfiles repo
```

---

## Benefits

### Prevention (Hook)
✅ Catches 90% of file ownership errors before they happen
✅ Clear, actionable error messages
✅ No reliance on memory or reading docs
✅ Works for all Claude Code instances
✅ Minimal performance impact

### Learning (Skill)
✅ Systematic post-mortem process
✅ Consistent documentation format
✅ Multiple safeguard levels (docs → automation)
✅ Discoverable (Claude auto-suggests when appropriate)
✅ Reusable across all mistake types

### Reference (Existing Docs)
✅ Knowledge base of past incidents
✅ Templates for new incidents
✅ Protocol library
✅ Learning over time

---

## Testing Strategy

### Hook Testing
```bash
# Test 1: Block edit to installed file
echo '{"tool_name":"Edit","tool_input":{"file_path":"/Users/daniel/.local/lib/secrets/secrets.sh"}}' | \
  config/claude/hooks/file-ownership-guard.sh
# Expected: exit 2, helpful error message

# Test 2: Allow edit to tracked file
echo '{"tool_name":"Edit","tool_input":{"file_path":"/Users/daniel/repos/dotfiles/README.md"}}' | \
  config/claude/hooks/file-ownership-guard.sh
# Expected: exit 0

# Test 3: Allow edit to symlinked file
echo '{"tool_name":"Edit","tool_input":{"file_path":"/Users/daniel/.config/nvim/init.lua"}}' | \
  config/claude/hooks/file-ownership-guard.sh
# Expected: exit 0 (if symlinked to repo)

# Test 4: Warn about ~/.config/ non-symlink
echo '{"tool_name":"Edit","tool_input":{"file_path":"/Users/daniel/.config/unknown/file.txt"}}' | \
  config/claude/hooks/file-ownership-guard.sh
# Expected: exit 2 with verification message
```

### Skill Testing
1. Simulate mistake scenario
2. Invoke skill manually: `/learn-from-mistake`
3. Follow workflow
4. Verify documentation created
5. Check CLAUDE.md updated
6. Confirm memory stored

---

## Implementation Phases

### Phase 1: Prevention Hook ⏱️ 2 hours
1. Write file-ownership-guard.sh
2. Add to config.json
3. Test all scenarios
4. Verify logging works

### Phase 2: Learning Skill ⏱️ 3 hours
1. Write SKILL.md
2. Create REFERENCE.md (detailed guides)
3. Create TEMPLATES.md (doc templates)
4. Create EXAMPLES.md (copy existing incident)
5. Test skill invocation

### Phase 3: Integration ⏱️ 1 hour
1. Update CLAUDE.md references
2. Update docs/learning/README.md
3. Test end-to-end workflow
4. Verify discoverability

### Phase 4: Verification ⏱️ 1 hour
1. Run test suite
2. Simulate false positive scenarios
3. Test skill on new mistake type
4. Ensure no regressions

**Total Estimated Time**: 7 hours

---

## Success Metrics

### Prevention Hook
- [ ] Blocks edits to ~/.local/lib/ files
- [ ] Blocks edits to ~/.local/bin/ files
- [ ] Blocks edits to /usr/local/ files
- [ ] Allows edits to tracked files
- [ ] Allows edits to symlinked files
- [ ] Provides clear error messages
- [ ] Logs all decisions

### Learning Skill
- [ ] Auto-suggested when mistake detected
- [ ] Guides through full workflow
- [ ] Creates analysis document
- [ ] Creates summary document
- [ ] Updates CLAUDE.md appropriately
- [ ] Stores in MCP memory
- [ ] Commits to git

### Integration
- [ ] Hook referenced in CLAUDE.md
- [ ] Skill referenced in docs/learning/README.md
- [ ] Works with existing docs/learning/ structure
- [ ] No conflicts with other hooks
- [ ] Discoverable via skill search

---

## Future Enhancements

### Short-term
- Add more installation path patterns (Homebrew, system packages)
- Create pre-commit hook for git ownership verification
- Add metrics dashboard for mistake frequency

### Long-term
- Machine learning on mistake patterns
- Auto-generate safeguards from analysis
- Cross-repo learning (share lessons across projects)
- Integration with team playbooks

---

## Risks and Mitigations

### Risk: False Positives (Hook Blocks Valid Edit)
**Mitigation**:
- Clear error message with verification instructions
- Log all blocks for review
- Escape hatch via readlink check

### Risk: Skill Not Discovered When Needed
**Mitigation**:
- Comprehensive description with trigger keywords
- Referenced in CLAUDE.md
- User can manually invoke if needed

### Risk: Hook Performance Impact
**Mitigation**:
- Minimal logic (git check + path pattern)
- Fast execution (<100ms)
- Only runs on Edit/Write (not frequent)

### Risk: Documentation Drift
**Mitigation**:
- Templates in skill directory
- Examples from real incidents
- Version controlled with dotfiles

---

## Conclusion

This combination approach provides **defense in depth**:

1. **Before**: Hook catches mistakes automatically
2. **After**: Skill guides structured learning
3. **Always**: Docs serve as knowledge base

By integrating both prevention and learning, we create a system that:
- Reduces mistake frequency (hook)
- Improves when mistakes occur (skill)
- Accumulates knowledge over time (docs)

This mirrors the original safety protocols added to CLAUDE.md but makes them **active** instead of passive.

---

## Approval Requested

Please review this plan and approve to proceed with implementation.

**Questions for User**:
1. Does the combination approach (hook + skill + docs) make sense?
2. Any concerns about the hook blocking edits?
3. Should the skill be auto-discovered or manual-only?
4. Any additional file paths to include/exclude in hook?

Once approved, I'll proceed with Phase 1 (Prevention Hook).
