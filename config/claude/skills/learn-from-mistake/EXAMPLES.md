# Learn From Mistake - Real Examples

This document showcases real incidents from `docs/learning/` to demonstrate the learning process in action.

## Table of Contents

1. [Example 1: External Dependency Edit Error (2026-03-11)](#example-1-external-dependency-edit-error-2026-03-11)
2. [Template for Future Examples](#template-for-future-examples)

---

## Example 1: External Dependency Edit Error (2026-03-11)

**Severity**: High
**Category**: File editing, External dependencies
**Status**: Fixed + Documented

### Quick Summary

Edited installed library at `~/.local/lib/secrets/secrets.sh` instead of source at `~/repos/secrets/secrets.sh`. Fix would have been lost on next install. Demonstrates classic "fix it where I found it" mental model failure.

### Full Documentation

See the comprehensive analysis at:
- **Analysis**: `/Users/daniel/repos/dotfiles/docs/learning/judgment-error-analysis.md` (216 lines)
- **Summary**: `/Users/daniel/repos/dotfiles/docs/learning/LEARNING-SUMMARY-2026-03-11.md` (251 lines)

### The 8-Step Process Applied

#### Step 1: Incident Capture

```
Mistake: Edited ~/.local/lib/secrets/secrets.sh instead of ~/repos/secrets/secrets.sh
Impact: High - Fix would be lost on next install
Status: Fixed in source repo
Affected: nuvemlabs/secrets repo, dotfiles installer
Date: 2026-03-11
```

#### Step 2: Root Cause Analysis

**Mental Model Failure**: "Fix It Where I Found It"
- Encountered bug in installed location
- Instinct was to fix broken code immediately
- Didn't pause to ask: "Is this file authoritative or derived?"

**Missing Verification**: File Ownership Check
- Didn't run `git ls-files --error-unmatch <path>`
- Didn't trace installation path to source
- Ignored that `~/.local/lib/` is installation directory

**Context Blindness**:
- CLAUDE.md mentioned "nuvemlabs/secrets library"
- `installers/secrets.sh` showed source at `~/repos/secrets`
- Had all context needed but didn't connect dots

#### Step 3: Red Flags Analysis

**Signals That Were Missed**:

1. **File Path**: `~/.local/lib/secrets/`
   - This is canonical installation directory
   - Source lives in repos, not `~/.local/lib/`

2. **Git Check Would Fail**:
   ```bash
   cd ~/.local/lib/secrets
   git status  # fatal: not a git repository
   ```

3. **Documentation Context**:
   - CLAUDE.md line 51: "refactor: use nuvemlabs/secrets as external dependency"
   - `installers/secrets.sh`: clearly installs from `~/repos/secrets`

4. **Common Sense**:
   - Modifying installed code = next install loses fix
   - Analogy: Would you edit `node_modules/`? No.

#### Step 4: Proper Workflow

**Correct Approach**:

1. **Verify File Ownership**:
   ```bash
   git ls-files --error-unmatch ~/.local/lib/secrets/secrets.sh
   # If this fails, it's not in the current repo
   ```

2. **Find Source Repository**:
   - Check `installers/secrets.sh` → shows `~/repos/secrets`
   - Or check `DEPENDENCIES.md` (if exists)

3. **Edit Source**:
   ```bash
   cd ~/repos/secrets
   vim secrets.sh
   git commit -m "Fix: zsh compatibility"
   ```

4. **Reinstall to Apply**:
   ```bash
   cd ~/repos/dotfiles
   ./install.sh --secrets
   ```

5. **Verify Fix**:
   ```bash
   diff ~/repos/secrets/secrets.sh ~/.local/lib/secrets/secrets.sh
   # Should be identical
   ```

#### Step 5: Documentation Created

**Analysis Document** (216 lines):
`docs/learning/judgment-error-analysis.md`

Contents:
- The error (what/where)
- Root cause (mental model + verification + context)
- Red flags (4 specific signals)
- Proper workflow (5 steps)
- Proposed learning mechanisms
- Immediate action items (checklist)

**Summary Document** (251 lines):
`docs/learning/LEARNING-SUMMARY-2026-03-11.md`

Contents:
- What happened (bug + mistake + impact)
- Root cause (mental model failure)
- Proper fix (4-step process with commits)
- Learning mechanisms (5 mechanisms)
- New safety protocol (before-edit checklist)
- Commits (both repos)
- Files created/modified
- Impact (immediate + long-term)

#### Step 6: Safeguards Implemented

**Level 1: Documentation** (Added to CLAUDE.md)

Global `~/.claude/CLAUDE.md`:
```markdown
## File Editing Safety Protocol

**MANDATORY CHECK: Before editing ANY file, verify code ownership**

Run ONE of these checks:

```bash
# Method 1: Is it tracked in current git repo?
git ls-files --error-unmatch <file_path> 2>/dev/null
# If this fails, STOP and investigate

# Method 2: Is it a symlink pointing to the repo?
readlink -f <file_path>
# Target should point to repo directory
```

**Installation Directory Warning Signs:**
- `~/.local/lib/` → Installed libraries (find source repo)
- `~/.local/bin/` → Installed executables (find source repo)
- `~/.config/` → MAY be symlinked (verify first)
- `~/.cache/` → Generated files (never edit)
- `/usr/local/` → System packages (never edit)

**External Dependency Decision Tree:**
1. Found bug in `~/.local/lib/foo/` → Find source repo, fix there, re-install
2. Found bug in system package → Report upstream or fork
3. Found bug in dotfiles symlink → Edit source in `config/` (after readlink check)

**Never assume a file is authoritative just because it exists and has a bug.**

Editing installed code = next install loses the fix. Always fix at the source.
```

**Level 2: External Dependency Tracking**

Created `DEPENDENCIES.md`:
```markdown
# External Dependencies

## nuvemlabs/secrets

**Source**: https://github.com/nuvemlabs/secrets
**Local Clone**: ~/repos/secrets/
**Installed**: ~/.local/lib/secrets/
**Installer**: installers/secrets.sh

**To fix bugs**:
1. Edit ~/repos/secrets/secrets.sh
2. Commit to repo
3. Re-run: ./install.sh --secrets
```

**Level 3: Automation** (Considered but skipped)

Would have created PreToolUse hook for file ownership checks, but decided on documentation + process instead to avoid hook bloat.

#### Step 7: MCP Memory Storage

**Stored**:
```json
{
  "name": "lesson-2026-03-11-external-dep-edit",
  "content": {
    "date": "2026-03-11",
    "error": "Edited installed library instead of source",
    "root_cause": "Mental model failure: 'fix it where I found it' instinct",
    "lesson": "Always verify file ownership with git ls-files before editing",
    "safeguards": [
      "File Editing Safety Protocol in CLAUDE.md",
      "DEPENDENCIES.md tracking external deps",
      "Pre-edit verification checklist"
    ],
    "severity": "High",
    "files_affected": [
      "~/.local/lib/secrets/secrets.sh",
      "~/repos/secrets/secrets.sh"
    ],
    "proper_workflow": "git ls-files check → find source → edit source → reinstall"
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

#### Step 8: Verification & Closure

**Checklist**:
- ✅ Proper fix applied to `~/repos/secrets/secrets.sh`
- ✅ Analysis document created (216 lines)
- ✅ Summary document created (251 lines)
- ✅ CLAUDE.md updated (project + global)
- ✅ DEPENDENCIES.md created
- ✅ MCP memory stored
- ✅ workflow_state.md logged
- ✅ Git commits created

**Commits**:

`nuvemlabs/secrets`:
```
2a32583 Fix zsh compatibility in SECRETS_DIR detection
```

`dotfiles`:
```
924829a Add external dependency safety protocol and learning documentation
```

**Outcome**:
- Bug fixed at source (permanent)
- Fix applied to installed version
- Safety protocol prevents recurrence
- Lesson stored for future reference
- Documentation serves as template for future incidents

### Key Lessons from This Example

1. **Mental Models Matter**
   - The instinct to "fix it where I found it" is common
   - Must be overridden with verification habit
   - Mental model failures are the root of many errors

2. **Red Flags Are Everywhere**
   - File paths tell you what type of file it is
   - Documentation often has the answer
   - Multiple signals usually point to the same truth

3. **Verification Before Action**
   - `git ls-files` is a 2-second check
   - Would have prevented the entire mistake
   - Small verification >> large rework

4. **Systemic Learning**
   - Don't just fix the bug
   - Fix the process that allowed the bug
   - Create documentation AND enforcement

5. **Documentation Quality**
   - 467 lines total documentation
   - Multiple formats (analysis, summary, protocol)
   - Serves as template for future incidents
   - Knowledge persists and compounds

### Reusability

This incident documentation is now used as:

- **Template**: For future learning sessions
- **Example**: In this EXAMPLES.md file
- **Reference**: When similar patterns occur
- **Training**: For onboarding and education
- **Enforcement**: In CLAUDE.md safety rules

The time invested in thorough documentation pays dividends every time a similar pattern is encountered.

---

## Template for Future Examples

When adding new examples to this file, use this structure:

### Example N: [Short Title] (YYYY-MM-DD)

**Severity**: [High/Medium/Low]
**Category**: [Categories]
**Status**: [Fixed + Documented]

#### Quick Summary
[2-3 sentences describing the mistake and why it matters]

#### Full Documentation
See:
- **Analysis**: [Path to analysis doc] (N lines)
- **Summary**: [Path to summary doc] (N lines)

#### The 8-Step Process Applied

##### Step 1: Incident Capture
[Show the capture]

##### Step 2: Root Cause Analysis
[Show the root cause breakdown]

##### Step 3: Red Flags Analysis
[List the red flags]

##### Step 4: Proper Workflow
[Show the correct approach]

##### Step 5: Documentation Created
[List what was created]

##### Step 6: Safeguards Implemented
[Show the safeguards by level]

##### Step 7: MCP Memory Storage
[Show the storage format if applicable]

##### Step 8: Verification & Closure
[Checklist and commits]

#### Key Lessons from This Example
1. [Lesson 1]
2. [Lesson 2]
3. [Lesson 3]

#### Reusability
[How this documentation is being used]

---

## Index of All Incidents

As more incidents are documented, maintain this index:

| Date | Short Name | Severity | Category | Docs |
|------|------------|----------|----------|------|
| 2026-03-11 | external-dep-edit | High | File editing, External deps | [Analysis](../../../docs/learning/judgment-error-analysis.md), [Summary](../../../docs/learning/LEARNING-SUMMARY-2026-03-11.md) |

---

## Pattern Analysis

As incidents accumulate, analyze patterns:

### Most Common Mental Model Failures
1. "Fix it where I found it" (1 incident)
2. [Add as more occur]

### Most Common Red Flags
1. File path in `~/.local/lib/` (1 incident)
2. [Add as more occur]

### Most Effective Safeguards
1. Pre-action verification checklists (1 incident)
2. [Add as more occur]

### Evolution of Safety Protocols
- 2026-03-11: Added File Editing Safety Protocol
- [Add as more occur]

---

## Using These Examples

### For Learning
- Read through incidents before similar work
- Recognize patterns early
- Apply lessons proactively

### For Teaching
- Share with team members
- Use in onboarding
- Reference in code reviews

### For Prevention
- Check if current situation matches past incident
- Apply the documented proper workflow
- Don't repeat mistakes

### For Templates
- Copy structure for new incidents
- Maintain consistency
- Build knowledge base

---

## Contributing New Examples

When documenting a new incident:

1. Create analysis and summary in `docs/learning/`
2. Add entry to this file following the template
3. Update the index table
4. Update pattern analysis
5. Commit all together

Keep examples:
- Complete (all 8 steps)
- Specific (real details, not generic)
- Actionable (clear lessons)
- Reusable (template-friendly)
