# Root Cause Analysis: skill-forge Not Used During Skill Creation

**Date**: 2026-03-11
**Severity**: Medium-High
**Status**: Fixed (Priority 1 fixes applied)

## The Error

Created a complex 2001-line skill (`learn-from-mistake`) without using the specialized `skill-forge` skill for validation, despite it being available and designed specifically for this purpose.

**What was done wrong:**
- Manually created skill with 451-line main file + 3 reference files (TEMPLATES.md, REFERENCE.md, EXAMPLES.md)
- Used `context: fork` metadata without testing forked execution environment
- Made path assumptions (relative paths without repo context)
- Did manual review instead of using systematic validation tool
- Declared skill complete without discovering context ambiguity issues

**What happened as a result:**
- Context ambiguity: Forked agent wouldn't know to work in dotfiles repo
- Relative paths (`docs/learning/`, `CLAUDE.md`, `workflow_state.md`) had no anchor
- Hardcoded paths in EXAMPLES.md (`/Users/daniel/repos/dotfiles/...`)
- Required 61+ lines of Environment Context fixes after creation
- Generated 185-line skill-forge review document identifying issues

**Meta-irony:**
Creating a skill about "systematic learning from mistakes" without using systematic skill-creation process.

## Root Cause Analysis (Five Whys)

### 1. What happened?
Created learn-from-mistake skill (2001 lines) without invoking skill-forge skill for validation.

### 2. Why did I skip skill-forge?
**Mental model failure**: "I know skill patterns from existing skills, I can write this directly."

Assumed that:
- Manual review would catch structural issues
- Prior experience with skills was sufficient
- Validation pass checking triggers/structure was enough

### 3. Why did that model fail?
**Context blindness**: Failed to recognize that `context: fork` creates a fundamentally different execution environment.

The skill would run in an isolated sub-agent that:
- Doesn't inherit parent's working directory
- Doesn't know which repo/project context it's in
- Can't assume paths are relative to current location

This is a subtle architectural concern that:
- Isn't obvious during manual review
- Requires simulating forked agent's perspective
- Is exactly what skill-forge's validation would check

### 4. Why didn't I catch it during manual review?
**Process gap**: Did "validation pass" but only checked trigger patterns and structure.

Did NOT:
- Simulate forked agent's execution environment
- Test actual skill invocation with `context: fork`
- Consider what context information is available vs assumed
- Check for path assumption patterns

skill-forge would have:
- Specifically checked for context handling
- Flagged relative paths without anchors
- Questioned fork context setup
- Tested against best practices database

### 5. Why doesn't the system prevent this?
**Systematic gap**: No forcing function to use skill-forge when creating/editing skills.

skill-forge is:
- Optional tooling (recommendation, not requirement)
- Listed in available skills but not mandatory
- Not enforced by hooks or pre-commit checks
- Easy to skip when confident in manual process

### Core Mental Model Failure

**Expertise bias**: Overconfidence in manual skill creation due to:
- Prior successful skill creation
- Familiarity with skill structure and patterns
- Underestimating complexity of context isolation

**Meta-blindness**: Creating a skill about systematic learning while not using systematic skill-creation tools:
- Didn't apply own principles ("use specialized tools")
- Assumed expertise exempted me from process
- Missed opportunity to dogfood the learning approach

**Lesson**: Expertise can blind you to the need for systematic processes. The more confident you are, the more important it is to use validation tools.

## Red Flags That Were Missed

### 1. Skill Complexity Signal
**What was visible**: 2001 total lines across 4 files (SKILL + 3 references)

**Why it matters**: Complex multi-file skills are high-risk for:
- Structural issues
- Cross-reference problems
- Context assumptions
- Path handling errors

**What should have happened**: "This is complex enough to warrant skill-forge validation regardless of my confidence level"

### 2. Context: Fork Metadata
**What was visible**: `context: fork` in skill frontmatter

**Why it matters**: Forked agents run in isolated environments:
- No parent context inheritance
- Fresh working directory
- No repo awareness
- Must explicitly set up environment

**What should have happened**: "Context isolation requires explicit environment setup instructions - let skill-forge verify this"

### 3. Relative Path References
**What was visible**: Paths like `docs/learning/`, `CLAUDE.md`, `workflow_state.md` without anchors

**Why it matters**: Forked agent doesn't know:
- Which repo to use (dotfiles vs other)
- Where repo is located
- What CWD should be

**What should have happened**: "All paths need explicit repo detection or absolute anchors - this is a known pattern skill-forge checks"

### 4. Meta-Cognitive Blind Spot
**What was visible**: Creating skill about "systematic learning from mistakes"

**Why it matters**: The skill's PURPOSE is systematic process:
- 8-step structured workflow
- Emphasis on using proper tools
- "Don't skip verification steps"

**What should have happened**: "Practice what you preach - use skill-forge for systematic skill creation"

This is the most critical red flag - the very CONTENT of the skill should have triggered recognition that systematic processes exist for a reason.

### 5. Tool Availability
**What was visible**: skill-forge listed in available skills

**Why it matters**: The tool exists specifically to:
- Validate skill structure
- Check context handling
- Verify best practices
- Prevent exactly these issues

**What should have happened**: "Check available skills list BEFORE starting creation work - if specialized tool exists, use it"

### 6. No Execution Testing
**What was visible**: Skill created and validated, but not tested in forked context

**Why it matters**: `context: fork` creates fundamentally different environment:
- Simulated execution would reveal path issues
- Would expose context ambiguity
- Would show missing environment setup

**What should have happened**: "Test skills with their actual execution context before declaring complete"

## The Proper Workflow

### For Creating Any Skill:

#### Phase 1: Preparation
1. **Check tool availability**:
   ```bash
   # Review available skills
   # Look for: skill-forge, skill development tools
   ```

2. **Assess complexity**:
   - Line count >500 lines? → MUST use skill-forge
   - Uses `context: fork`? → MUST use skill-forge
   - Multiple reference files? → SHOULD use skill-forge
   - Simple (<200 lines)? → RECOMMENDED to use skill-forge (best practice)

3. **Decision**: If skill-forge available and skill meets ANY complexity criteria → Plan to use it

#### Phase 2: Creation
1. **Draft skill** in `config/claude/skills/<name>/SKILL.md`
   - Write content following patterns
   - Add reference files if needed (TEMPLATES, REFERENCE, EXAMPLES)
   - Include metadata (name, description, context, allowed-tools)

2. **Self-review checklist** (before skill-forge):
   - [ ] Trigger patterns clear and specific?
   - [ ] Progressive disclosure (quick start → details → references)?
   - [ ] Line count under limits?
   - [ ] All paths explicit (no assumptions)?
   - [ ] Context setup documented (if fork)?

#### Phase 3: Validation with skill-forge
1. **Invoke skill-forge**:
   ```
   /skill-forge
   # or
   Skill tool with skill: "skill-forge"
   ```

2. **Review validation output**:
   - **Automated validation**: Check all PASS results
   - **Manual review**: Read strengths and issues sections
   - **Recommendations**: Note Priority 1 (critical), Priority 2 (important), Priority 3 (nice to have)

3. **Understand failures**:
   - Don't just fix mechanically
   - Understand WHY each issue matters
   - Learn the pattern to avoid in future

#### Phase 4: Fix and Re-validate
1. **Apply Priority 1 fixes**: Critical issues that block usage
2. **Apply Priority 2 fixes**: Important reliability improvements
3. **Re-run skill-forge**: If major changes made (>50 lines)
4. **Verify**: All critical issues resolved

#### Phase 5: Testing
1. **Test auto-discovery**: Does skill trigger on expected patterns?
2. **Test execution context**:
   - For `context: fork`: Test in isolated environment
   - For normal context: Test in current session
3. **Verify file operations**: Do paths resolve correctly?
4. **Check integrations**: Do references to other files/skills work?

#### Phase 6: Documentation and Commit
1. **Update CLAUDE.md**: Add skill to project documentation
2. **Update docs**: Reference in relevant guides
3. **Commit atomically**: Skill creation as separate, focused commit
4. **Test post-commit**: Verify skill still works after commit

### Decision Tree

```
Creating/Editing Skill?
│
├─ Is skill-forge available?
│  ├─ YES → Continue to complexity check
│  └─ NO → Use manual checklist + extra testing
│
├─ Complexity Check (if skill-forge available):
│  ├─ Skill >500 lines? → YES → MUST use skill-forge
│  ├─ Uses context:fork? → YES → MUST use skill-forge
│  ├─ Has reference files? → YES → SHOULD use skill-forge
│  ├─ Complex logic/integrations? → YES → SHOULD use skill-forge
│  └─ Simple skill (<200 lines, no fork)? → RECOMMENDED (best practice)
│
└─ Execution:
   1. Draft skill
   2. Invoke skill-forge
   3. Review validation
   4. Apply fixes
   5. Re-validate if major changes
   6. Test in actual context
   7. Document and commit
```

### Key Principles

1. **Use specialized tools**: If skill-forge exists, use it - that's why it exists
2. **Don't assume expertise exempts process**: The more confident you are, the more important validation becomes
3. **Test in actual context**: `context: fork` must be tested in forked environment
4. **Fix understanding, not just code**: Understand WHY each issue matters
5. **Practice what you preach**: If creating systematic process skill, use systematic skill-creation process

## What Was Done to Fix It

### Priority 1 Fixes (Critical - Applied Immediately)

1. **Added Environment Context Section** (61 lines)
   - Location: After "Quick Start" in SKILL.md
   - Bash script for dotfiles repo detection
   - Directory verification (docs/learning/, workflow_state.md)
   - Path conventions table explaining relative vs absolute
   - Clear instruction: NEVER use hardcoded username paths

2. **Updated Step 5 with Explicit Paths**
   - Before: `docs/learning/incident-*.md` (ambiguous)
   - After:
     - Relative: `docs/learning/incident-*.md` (in repo)
     - Absolute: `$DOTFILES_REPO/docs/learning/incident-*.md`
     - Example bash commands showing `cd "$DOTFILES_REPO"`

3. **Distinguished Project vs Global CLAUDE.md**
   - Step 6 now explicitly lists:
     - Project: `$DOTFILES_REPO/CLAUDE.md` (in repo root)
     - Global: `~/.claude/CLAUDE.md` (outside repo)
   - Clear guidance on when to use each

4. **Updated Integration Points**
   - Added full path examples for all integration points
   - Clarified which files are in repo vs outside
   - Used `$DOTFILES_REPO` anchor consistently

5. **Fixed EXAMPLES.md Hardcoded Paths**
   - Before: `/Users/daniel/repos/dotfiles/docs/learning/judgment-error-analysis.md`
   - After: `docs/learning/judgment-error-analysis.md` (relative, with context)

6. **Fixed REFERENCE.md Cross-Reference Diagram**
   - Updated directory tree to show `$DOTFILES_REPO/` anchor
   - Made clear all paths are relative to repo root

**Total changes**: 61+ lines added, multiple path references clarified

### Re-validation Result
- Automated validation: 21 checks PASS
- Manual review: 1 warning (512 lines, acceptable for critical fix)
- Context ambiguity: RESOLVED

## Learning Mechanisms Implemented

### Level 1: Documentation (DONE)
- **Project CLAUDE.md**: Already updated with learning system reference
- **This analysis**: Added to `docs/learning/incident-2026-03-11-skill-forge-not-used.md`
- **Executive summary**: Being created in `docs/learning/SUMMARY-2026-03-11-skill-forge.md`

### Level 2: Process (PLAN TO ADD)
Create checklist in global `~/.claude/CLAUDE.md`:

```markdown
## Skill Creation Protocol

Before creating or editing any skill:

1. [ ] Check if skill-forge is available (review skills list)
2. [ ] Assess complexity (>500 lines, context:fork, reference files)
3. [ ] If complexity threshold met → MUST use skill-forge
4. [ ] Draft skill following patterns
5. [ ] Invoke skill-forge for validation
6. [ ] Apply Priority 1 (critical) fixes
7. [ ] Re-validate if major changes
8. [ ] Test in actual execution context (especially fork)
9. [ ] Document in CLAUDE.md
10. [ ] Commit atomically

**CRITICAL**: Do not skip skill-forge due to confidence or familiarity. Expertise bias is highest when you think you don't need validation.
```

### Level 3: Automation (NOT NEEDED)
- No pre-commit hook needed (would be too invasive)
- skill-forge already exists as validation tool
- Issue was not using existing tool, not lack of tooling

### Level 4: Architecture (NOT NEEDED)
- Current architecture is sound
- skill-forge provides adequate validation
- Issue was process compliance, not design flaw

**Chosen Level: Level 2 (Process/Checklist)**
- Severity: Medium-High (caused rework, but caught before user impact)
- Frequency: Medium (skill creation is periodic but not rare)
- Decision: Add checklist to global CLAUDE.md as forcing function

## Key Takeaway

**Expertise can blind you to the need for systematic processes.**

When creating content ABOUT systematic learning (the learn-from-mistake skill), I failed to use systematic skill-creation process (skill-forge). This is textbook expertise bias:

1. **Overconfidence**: "I've created skills before, I know the patterns"
2. **Tool dismissal**: "Manual review will catch issues"
3. **Meta-blindness**: Not recognizing the irony of skipping systematic process while creating systematic process content

**The fix**: Use specialized validation tools ESPECIALLY when you feel confident you don't need them. Confidence is a red flag, not a green light.

**Protocol going forward**:
- Check for specialized tools BEFORE starting creation work
- Use skill-forge for ANY skill creation/editing (regardless of complexity)
- Practice what you preach (if creating systematic process, use systematic process)
- Confidence = trigger for extra validation, not less

## Related Documentation

- **Executive Summary**: `docs/learning/SUMMARY-2026-03-11-skill-forge.md`
- **skill-forge Review**: `skill-forge-review-learn-from-mistake.md` (temporary, in repo root)
- **The Skill**: `config/claude/skills/learn-from-mistake/SKILL.md`
- **Context Fixes**: Commits showing Environment Context additions
- **Previous Incident**: `docs/learning/judgment-error-analysis.md` (similar expertise bias pattern)

## Git Commits

1. **Skill Creation**: commit 411eb6f - "feat: add learn-from-mistake systematic learning skill"
2. **Context Fixes**: (pending) - "fix: add environment context to learn-from-mistake skill"
3. **This Analysis**: (pending) - "docs: learning from skill-forge-not-used incident"

## Success Metrics

- [ ] Environment Context section prevents path confusion
- [ ] Future skill creation uses skill-forge (track in workflow_state.md)
- [ ] No more skills deployed with context ambiguity issues
- [ ] Checklist in CLAUDE.md is referenced before skill creation
- [ ] Meta-awareness: recognize when NOT using systematic process for systematic work
