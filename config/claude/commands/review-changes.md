---
allowed-tools: Bash(git:*), Read(*), Glob(*), Grep(*)
description: Agent team for pre-commit review of dotfiles changes
---

## Agent Team: Pre-Commit Review

Create an agent team to review pending dotfiles changes from multiple angles before committing.

The dotfiles repo is at: $CWD

### Context

- Current changes: !`git diff --stat HEAD`
- Changed files: !`git status --short`

### Team Structure

Spawn 3 teammates. Each reviews the same changes through a different lens. No dependencies between them.

**Teammate 1 - "cross-platform"**: Cross-Platform Compatibility Review
- Review all changed installer scripts for portability issues
- Check for hardcoded paths that assume Linux or macOS only
- Verify package manager detection works for: brew, apt, dnf, pacman, choco
- Check for bash-specific syntax that might break in zsh or vice versa
- Verify `uname` and platform detection guards are correct
- Flag any commands that don't exist on all target platforms
- Check that `lib/install-packages.sh` handles all changed packages
- Report: list of portability issues with severity (blocker/warning/info)

**Teammate 2 - "security"**: Security Review
- Check for exposed secrets, API keys, tokens, or passwords in any changed files
- Verify file permissions set by installers (no world-readable sensitive files)
- Check for command injection risks in installer scripts (unquoted variables, eval usage)
- Verify symlink targets don't escape the dotfiles directory
- Check that .gitignore covers sensitive files (.env, .credentials, .accessTokens)
- Review any curl/wget commands for HTTPS usage and integrity checks
- Report: list of security findings with severity (critical/high/medium/low)

**Teammate 3 - "symlink-validator"**: Symlink & Config Integrity Review
- For every `create_symlink`, `link_home_files`, `link_config_dirs`, `link_target_files` call in changed files:
  - Verify the source file/directory actually exists in the repo
  - Verify the target path is reasonable and won't conflict
- Check for duplicate symlink targets (two sources pointing to same target)
- Verify backup logic works (create_backup_dir, backup_item)
- Check that install order in install.sh respects actual dependencies
- Verify any new config files follow existing naming conventions
- Report: list of integrity issues with details

### Completion

After all teammates finish:
1. Synthesize findings from all 3 reviewers into a unified report
2. Categorize as: blockers (must fix), warnings (should fix), info (nice to know)
3. If no blockers, recommend proceeding with the commit
4. If blockers exist, list specific fixes needed before committing
