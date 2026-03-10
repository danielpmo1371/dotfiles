# Learning Documentation

This directory contains post-mortem analyses, lessons learned, and systematic improvements from mistakes and judgment errors.

## Purpose

When things go wrong, we don't just fix them—we **learn from them** and **prevent recurrence**. Each incident gets:

1. **Root cause analysis** (why did it happen?)
2. **Proper fix implementation** (what's the right way?)
3. **Learning mechanisms** (how do we prevent it?)
4. **Documentation** (how do we remember it?)

## Incidents

### 2026-03-11: External Dependency Edit Error

**What Happened**: Fixed a bug in installed library (`~/.local/lib/secrets/`) instead of source repo (`~/repos/secrets/`)

**Why It Matters**: Installed files are derived artifacts. Next install would overwrite the fix.

**Documents**:
- `judgment-error-analysis.md` (216 lines) - Comprehensive root cause analysis
- `LEARNING-SUMMARY-2026-03-11.md` (251 lines) - Executive summary and outcomes

**Outcome**:
- ✅ Bug fixed in source repository (nuvemlabs/secrets)
- ✅ Fix applied to installed version
- ✅ External dependency tracking system created (`DEPENDENCIES.md`)
- ✅ Safety protocols added to CLAUDE.md (project + global)
- ✅ Lesson stored in MCP persistent memory
- ✅ New mandatory pre-edit verification: `git ls-files --error-unmatch <path>`

**Key Lesson**: Never assume a file is authoritative just because it exists. Always verify code ownership before editing.

---

## Learning Process

Each incident follows this template:

### 1. Immediate Response
- Identify the error
- Understand the impact
- Apply proper fix

### 2. Analysis
- Why did the mistake happen? (mental model failure)
- What signals should have prevented it? (red flags)
- What was the proper workflow? (correct procedure)

### 3. Learning Mechanisms
- Documentation (analysis + summary)
- Safety rules (CLAUDE.md additions)
- Persistent memory (MCP storage)
- Process improvements (new protocols)
- Automation (hooks, checks, tools)

### 4. Verification
- Confirm fix works
- Test new protocols
- Document outcomes

---

## Files in This Directory

### Analyses
- `judgment-error-analysis.md` - Deep dive into root causes and failure modes

### Summaries
- `LEARNING-SUMMARY-YYYY-MM-DD.md` - Executive summary of incident and outcomes

### Supporting Docs
- Referenced in main `/docs/` or `/` (e.g., `DEPENDENCIES.md`)

---

## Creating New Incident Documentation

### Use the `/learn-from-mistake` Skill

When a mistake occurs, use the systematic learning skill for guided post-mortem analysis:

**Invocation**:
- Let Claude auto-detect when you say "I made a mistake" or "that was wrong"
- Or invoke manually (skill will auto-suggest when appropriate)

**What It Does**:
1. **Guides through 8-step process** (incident capture → root cause → red flags → proper workflow → documentation → safeguards → memory → verification)
2. **Creates comprehensive docs** (analysis + summary in `docs/learning/`)
3. **Determines appropriate safeguards** (Level 1-4 based on severity/frequency)
4. **Updates CLAUDE.md** (adds safety protocols if needed)
5. **Stores in MCP memory** (with queryable tags)
6. **Creates git commits** (all artifacts version controlled)

**Templates Available**:
- `config/claude/skills/learn-from-mistake/TEMPLATES.md` - Copy-paste templates
- `config/claude/skills/learn-from-mistake/REFERENCE.md` - Detailed guides
- `config/claude/skills/learn-from-mistake/EXAMPLES.md` - Real incidents

**Process** (brief):
1. Fix the mistake first (if not already done)
2. Invoke the skill
3. Follow the structured workflow
4. Review generated documentation
5. Commit to dotfiles repo

### Manual Process (Without Skill)

If you prefer to create documentation manually:

1. Copy templates from `config/claude/skills/learn-from-mistake/TEMPLATES.md`
2. Follow the 8-step process in the skill
3. Create analysis and summary documents
4. Update CLAUDE.md if appropriate
5. Store in MCP memory (if available)
6. Commit all artifacts

---

## How to Use This Documentation

### For Future Self
Read these when:
- About to make a quick fix without thinking
- Encountering similar patterns
- Training new team members
- Reviewing safety protocols

### For Claude Code
These incidents are:
- Stored in MCP memory (queryable)
- Referenced in CLAUDE.md (enforced)
- Used as examples in safety rules
- Accessible via `/learn-from-mistake` skill

### For Team
Use as case studies for:
- Decision-making under uncertainty
- Importance of verification steps
- Value of systematic improvements

---

## Metrics

| Date | Incident | Lines of Doc | Mechanisms Added | Memory Stored |
|------|----------|--------------|------------------|---------------|
| 2026-03-11 | External Dep Edit | 467 | 5 | ✅ |

**Total Learning Documentation**: 467+ lines

---

## Philosophy

> "We don't just fix bugs. We fix the process that allowed the bugs."

Every mistake is an opportunity to:
1. **Understand** why it happened
2. **Document** the proper approach
3. **Systematize** the prevention
4. **Remember** the lesson

This directory is proof that the system learns, adapts, and improves.
