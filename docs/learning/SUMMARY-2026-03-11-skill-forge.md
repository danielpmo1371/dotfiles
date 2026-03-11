# Learning Summary: skill-forge Not Used During Skill Creation

**Date**: 2026-03-11
**Incident**: Created learn-from-mistake skill without using skill-forge validation
**Severity**: Medium-High
**Status**: Fixed (Priority 1 context setup added)

---

## What Happened

Created a complex 2001-line skill (`learn-from-mistake`) without using the `skill-forge` skill for validation, despite it being:
- Available in the skills list
- Designed specifically for skill creation/validation
- Exactly the right tool for this purpose

The skill used `context: fork` (isolated sub-agent execution) but made path assumptions without establishing environment context. This caused:
- **Context ambiguity**: Forked agent wouldn't know to work in dotfiles repo
- **Relative paths without anchors**: `docs/learning/`, `CLAUDE.md`, `workflow_state.md`
- **Hardcoded paths**: `/Users/daniel/repos/dotfiles/...` in examples
- **Required fixes**: 61+ lines of Environment Context section + path clarifications

**Meta-irony**: Created a skill about systematic learning from mistakes without using systematic skill-creation process.

---

## Why It Happened

**Root Cause**: Expertise bias - overconfidence in manual skill creation led to skipping specialized validation tool.

**Chain of Causation**:
1. **Assumption**: "I know skill patterns, I can write this directly"
2. **Tool dismissal**: "Manual review will catch structural issues"
3. **Context blindness**: Didn't recognize `context: fork` requires explicit environment setup
4. **Process gap**: Validated structure/triggers but didn't test forked execution
5. **Meta-blindness**: Creating systematic learning skill while not using systematic skill-creation process

**Key Mental Model Failure**: Assumed expertise exempted me from using validation tools. The opposite is true - confidence is a red flag for needing extra validation.

---

## The Proper Fix

### What Was Done (Priority 1 Fixes)

1. **Environment Context Section** (61 lines)
   - Bash script for dotfiles repo auto-detection
   - Directory verification (docs/learning/, workflow_state.md)
   - Path conventions table (relative vs absolute)
   - Explicit instruction: Never hardcode username paths

2. **Path Clarifications Throughout**
   - Step 5: Added `$DOTFILES_REPO` anchor to all paths
   - Step 6: Distinguished project vs global CLAUDE.md
   - Integration Points: Full path examples
   - EXAMPLES.md: Removed hardcoded `/Users/daniel/...` paths
   - REFERENCE.md: Updated cross-reference diagram

3. **Re-validation**
   - Used skill-forge to review fixes
   - Result: 21 checks PASS, 1 warning (acceptable)
   - Context ambiguity: RESOLVED

### File Locations
- **Analysis**: `docs/learning/incident-2026-03-11-skill-forge-not-used.md`
- **Summary**: `docs/learning/SUMMARY-2026-03-11-skill-forge.md` (this file)
- **The Skill**: `config/claude/skills/learn-from-mistake/SKILL.md`
- **Review**: `skill-forge-review-learn-from-mistake.md` (temp file)

---

## Learning Mechanisms

### Protocol: Skill Creation Checklist (Level 2)

**Add to global `~/.claude/CLAUDE.md`:**

```markdown
## Skill Creation Protocol

Before creating or editing any skill:

1. [ ] Check if skill-forge is available (review skills list)
2. [ ] Assess complexity:
   - [ ] >500 lines? → MUST use skill-forge
   - [ ] Uses context:fork? → MUST use skill-forge
   - [ ] Multiple reference files? → SHOULD use skill-forge
   - [ ] Simple (<200 lines)? → RECOMMENDED (best practice)
3. [ ] Draft skill following existing patterns
4. [ ] Invoke skill-forge for validation
5. [ ] Review both automated checks AND manual review section
6. [ ] Apply Priority 1 (critical) fixes immediately
7. [ ] Re-validate if major changes made
8. [ ] Test in actual execution context (especially fork)
9. [ ] Update project CLAUDE.md with skill reference
10. [ ] Commit atomically with clear message

**CRITICAL**: Do not skip skill-forge due to confidence or familiarity.
Expertise bias is highest when you think you don't need validation.

**Red Flags That Trigger Mandatory skill-forge Use**:
- "I've done this before, I know the patterns" ← expertise bias
- "Manual review is enough" ← process dismissal
- "This is simple, no need for tools" ← underestimating complexity
- Using context:fork without explicit environment setup
- Creating skill about systematic process while skipping systematic creation
```

### Decision Rationale

**Chosen Level**: Process/Checklist (Level 2)
- **Frequency**: Medium (skill creation periodic but not rare)
- **Severity**: Medium-High (caused rework, but caught before user impact)
- **Approach**: Forcing function in global CLAUDE.md

**Not chosen**:
- Level 1 (docs only): Too passive, already have docs
- Level 3 (automation): Would require pre-commit hook, too invasive
- Level 4 (architecture): Design is sound, issue was process compliance

---

## Red Flags That Were Missed

1. **Skill Complexity**: 2001 lines across 4 files
   - Should have triggered: "Complex enough for skill-forge validation"

2. **Context: Fork Metadata**: Used isolated execution context
   - Should have triggered: "Fork requires explicit environment setup"

3. **Relative Paths**: `docs/learning/`, `CLAUDE.md` without anchors
   - Should have triggered: "Paths need repo context for forked agents"

4. **Meta-Cognitive Signal**: Creating systematic learning skill
   - Should have triggered: "Practice what you preach - use systematic creation"

5. **Tool Availability**: skill-forge listed in available skills
   - Should have triggered: "Check skills list BEFORE starting work"

6. **No Execution Test**: Created but didn't test in forked context
   - Should have triggered: "Test with actual execution context before declaring complete"

**Most Critical**: Creating content ABOUT systematic learning while NOT using systematic skill-creation process. This is the clearest signal of expertise bias.

---

## Proper Workflow (Summary)

### For Any Skill Creation:

1. **Check Tools**: Is skill-forge available? (review skills list)
2. **Assess**: Does skill meet complexity thresholds? (>500 lines, fork, references)
3. **Draft**: Create skill following existing patterns
4. **Validate**: Invoke skill-forge (NOT optional if thresholds met)
5. **Review**: Read BOTH automated AND manual review sections
6. **Fix**: Apply Priority 1 (critical) recommendations immediately
7. **Re-validate**: If major changes made
8. **Test**: In actual execution context (especially fork)
9. **Document**: Update CLAUDE.md
10. **Commit**: Atomic commit with clear message

### Decision Tree:

```
Creating Skill? → Check skill-forge availability
├─ Available + (>500 lines OR fork OR references) → MUST use skill-forge
├─ Available + simple skill → RECOMMENDED (best practice)
└─ Not available → Manual checklist + extra testing

NEVER skip due to confidence or familiarity.
Confidence = red flag for extra validation, not less.
```

---

## Key Takeaway

**Expertise can blind you to the need for systematic processes.**

When you feel confident enough to skip validation tools, that's EXACTLY when you need them most. Confidence is a signal for MORE scrutiny, not less.

**The Pattern**:
1. Gain expertise in area (skill creation)
2. Develop confidence from past success
3. Dismiss systematic tools as unnecessary
4. Make subtle mistakes that manual review misses
5. Discover issues later, requiring rework

**The Fix**:
- Use specialized validation tools ESPECIALLY when confident
- Treat confidence as red flag, not green light
- Practice what you preach (systematic process for systematic work)
- Check tools list BEFORE starting creation work
- Test in actual execution context before declaring complete

**Protocol**: Added skill creation checklist to global CLAUDE.md as forcing function to prevent recurrence.

---

## Git Commits

1. **Skill Creation**: `411eb6f` - "feat: add learn-from-mistake systematic learning skill"
2. **Context Fixes**: (pending) - "fix: add environment context to learn-from-mistake skill"
3. **Learning Docs**: (pending) - "docs: learning from skill-forge-not-used incident"
4. **Protocol Update**: (pending) - "docs: add skill creation protocol to CLAUDE.md"

---

## Related Documentation

- **Full Analysis**: `docs/learning/incident-2026-03-11-skill-forge-not-used.md`
- **skill-forge Review**: `skill-forge-review-learn-from-mistake.md` (shows what was caught)
- **The Skill (Fixed)**: `config/claude/skills/learn-from-mistake/SKILL.md`
- **Previous Similar Incident**: `docs/learning/judgment-error-analysis.md` (external dep edit, also expertise bias)
- **Learning System**: `docs/learning/README.md` (index of all incidents)

---

## Success Metrics

Track in future workflow:

- [ ] No more skills deployed with context ambiguity
- [ ] skill-forge used for all future skill creation (log in workflow_state.md)
- [ ] Checklist in CLAUDE.md referenced before creation work
- [ ] Meta-awareness: Recognize when not using systematic process for systematic work
- [ ] Reduced rework cycles (fix issues before deployment, not after)
