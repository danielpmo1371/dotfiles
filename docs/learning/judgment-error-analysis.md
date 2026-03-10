# Judgment Error Analysis: Editing Installed Library Instead of Source

## Date: 2026-03-11

## The Error

Fixed a zsh compatibility bug in `/Users/daniel/.local/lib/secrets/secrets.sh` (installed library) instead of the source code at `/Users/daniel/repos/secrets/secrets.sh`.

### What Was Patched

```bash
# BEFORE (source repo):
SECRETS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"

# AFTER (installed version only):
if [ -n "$ZSH_VERSION" ]; then
    SECRETS_DIR="${${(%):-%x}:A:h}"
elif [ -n "$BASH_SOURCE" ]; then
    SECRETS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    # Fallback to a known location
    SECRETS_DIR="${HOME}/.local/lib/secrets"
fi
```

The fix is correct and necessary (the original line's nested parameter expansion syntax doesn't work properly in zsh). **The problem is WHERE it was applied.**

## Root Cause Analysis

### 1. Why This Mistake Happened

**Mental Model Failure: "Fix It Where I Found It"**
- I encountered the bug in the installed location (`~/.local/lib/secrets/`)
- My instinct was to fix the broken code immediately where it was found
- I didn't pause to ask: "Is this file authoritative or derived?"

**Missing Verification Step: "What Owns This Code?"**
- I didn't check if the file was tracked in the current git repo
- I didn't trace the installation path to find the source
- I didn't consider that `~/.local/lib/` is a common location for *installed* dependencies

**Context Blindness**
- The dotfiles repo CLAUDE.md mentions "nuvemlabs/secrets library" and shows it being installed
- The installer at `installers/secrets.sh` clearly shows it's cloned from `~/repos/secrets`
- I had all the context needed but didn't connect the dots

### 2. What Signals Should Have Triggered "Wait..."

**Red Flags That Should Have Stopped Me:**

1. **File Path Signal**: `~/.local/lib/secrets/`
   - This is a canonical *installation* directory
   - Source code lives in repos, not `~/.local/lib/`

2. **Git Check Would Have Failed**:
   ```bash
   cd ~/.local/lib/secrets
   git status  # Would show: fatal: not a git repository
   ```

3. **CLAUDE.md Context**:
   - Line 51: "refactor: use nuvemlabs/secrets as external dependency"
   - Installers/secrets.sh: clearly installs FROM `~/repos/secrets`

4. **Common Sense**:
   - Modifying installed code means: next install = lose the fix
   - If I found a bug in `node_modules/`, would I edit it there? No.

### 3. Proper Fix Location

**Source Repository:**
- Repo: `https://github.com/nuvemlabs/secrets.git`
- Local clone: `/Users/daniel/repos/secrets/`
- File to edit: `/Users/daniel/repos/secrets/secrets.sh`

**Fix Persistence Strategy:**
1. Edit source in `~/repos/secrets/secrets.sh`
2. Commit to local git
3. (Optional) Push to GitHub if ready for public release
4. Re-run `./install.sh --secrets` in dotfiles to update installed version

## Proposed Learning Mechanisms

### A. Add to CLAUDE.md (Project-Level Rules)

Add new section under "Development Standards":

```markdown
## External Dependency Safety Rules

**NEVER edit files outside this repository's git control**
- Before editing ANY file, verify it's tracked: `git ls-files <path>`
- Files in `~/.local/`, `~/.config/`, `~/.claude/` may be symlinks or copies
- If a bug is in an external dependency:
  1. Find the SOURCE repository (check installers/ scripts)
  2. Fix it in the source repo
  3. Re-run the installer to apply the fix

**Common External Dependencies in This Repo:**
- `nuvemlabs/secrets` → source at `~/repos/secrets/`
- System packages (brew, apt, etc.) → never edit installed files
- Symlinked configs → edit the source in `config/`, not `~/.config/`

**Exception:** Symlinked files are OK to edit (e.g., `~/.config/nvim/` → `dotfiles/config/nvim/`)
- Use `readlink -f <path>` to verify the target is in this repo
```

### B. Add to ~/.claude/CLAUDE.md (Global User Rules)

Add under "Good practices":

```markdown
## File Editing Safety Protocol

Before editing any file, verify ownership:

1. **Is it in the current git repo?**
   ```bash
   git ls-files --error-unmatch <file_path> 2>/dev/null
   ```
   If this fails, STOP and investigate.

2. **Is it a symlink pointing to the repo?**
   ```bash
   readlink -f <file_path>  # Should point to repo directory
   ```

3. **Is it in a known installation directory?**
   - `~/.local/lib/` → Installed libraries
   - `~/.local/bin/` → Installed executables
   - `~/.config/` → MAY be symlinked (verify)
   - `~/.cache/` → Generated, never edit

   If yes: Find the SOURCE and edit there.

4. **External dependency decision tree:**
   - Found bug in `~/.local/lib/foo/` → Find source repo
   - Found bug in system package → Report upstream or fork
   - Found bug in dotfiles symlink → Edit source in `config/`

**Never assume a file is authoritative just because it exists.**
```

### C. Pre-Edit Check Tool (Optional Future Enhancement)

Could add a git pre-commit hook or Claude skill:

```bash
#!/bin/bash
# Pre-edit verification
check_file_ownership() {
    local file="$1"

    # Check if file is in current git repo
    if ! git ls-files --error-unmatch "$file" 2>/dev/null; then
        # Check if it's a symlink to the repo
        local target=$(readlink -f "$file")
        local repo_root=$(git rev-parse --show-toplevel)

        if [[ "$target" != "$repo_root"* ]]; then
            echo "ERROR: File is not in git repo or symlinked to it"
            echo "  File: $file"
            echo "  Target: $target"
            echo "  Repo: $repo_root"
            echo ""
            echo "If this is an external dependency, find the source repo first."
            return 1
        fi
    fi
    return 0
}
```

### D. Memory/Context Tool (MCP Memory)

Store this lesson in persistent memory:

```
Key: external-dependency-edit-error
Value: {
  "date": "2026-03-11",
  "error": "Edited installed library instead of source",
  "lesson": "Always verify file ownership with git ls-files before editing",
  "checklist": [
    "Is file tracked in current repo?",
    "Is it a symlink to the repo?",
    "Is it in ~/.local/lib/ (installation dir)?",
    "If external dep: find source repo, fix there, re-install"
  ]
}
```

## Immediate Action Items

1. ✅ Analyze the error (this document)
2. ⏳ Apply fix to source repo (`~/repos/secrets/secrets.sh`)
3. ⏳ Commit to nuvemlabs/secrets repo
4. ⏳ Re-install to apply fix: `./install.sh --secrets`
5. ⏳ Verify fix works in both bash and zsh
6. ⏳ Update CLAUDE.md with new safety rules
7. ⏳ Store lesson in MCP memory

## Long-Term Improvements

- Consider adding `git ls-files` check to Edit tool wrapper
- Add pre-commit hook that warns about edits to non-repo files
- Create `/detect-external-deps` skill that scans for external dependencies
- Document all external deps in DEPENDENCIES.md

## Takeaway

**The fix was good. The location was wrong. The lesson is about verification before action.**

This wasn't a coding error—it was a process error. The code change itself is correct and necessary. The failure was in the decision-making process: rushing to fix the immediate problem without first establishing code ownership and authority.

**New habit: Every edit starts with: `git ls-files --error-unmatch <path>` or `readlink -f <path>`**
