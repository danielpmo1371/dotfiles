# Workflow State: Open-Source Dotfiles Public Repo Build

## State
- **Status**: CONSTRUCT
- **Phase**: Build public repo from scratch
- **Public Repo**: `/Users/daniel/repos/dotfiles-public` → `nuvemlabs/dotfiles`
- **Private Repo**: Current repo stays at `danielpmo1371/dotfiles` (cleaned later)

## Decisions (Approved)
- D1: PATs — revoke AFTER new solution is ready (user decision)
- D2: claude.json — gitignore it, use settings.json for tracked settings
- D3: bash_aliases — referenced in installer/tests, keep but clean (WSL/employer content out)
- D4: GitHub — `nuvemlabs` public, `danielpmo1371` private
- D5: Architecture — Overlay model, lightweight templating, gitleaks
- D6: History — Fresh repo (no surgical scrub)
- D7: Migration — Build public first, test, then clean private. Never break current setup

## Plan

### Phase 1: Build Public Repo (Current Phase)
1. Create repo at /Users/daniel/repos/dotfiles-public with git init
2. Create full directory structure
3. Copy all clean files (no changes needed)
4. Launch 3 parallel agents:
   - config-builder: clean all config/ files
   - scripts-builder: clean scripts, installers, entry points
   - infra-docs: create new infrastructure (template.sh, overlay.sh, gitleaks, docs)
5. Review and verify with gitleaks

### Phase 2: Test
6. Run Docker e2e test on public repo (Ubuntu)
7. Verify install.sh works standalone without private overlay

### Phase 3: Private Repo Cleanup (Future)
8. Branch current repo, strip to overlay-only structure
9. Test overlay integration
10. Merge, scrub history, revoke PATs

## File Categorization

### Clean (copy as-is): 140+ files
- config/nvim/* (entire directory)
- config/ghostty/* (entire directory)
- config/tmux/tmux.conf
- config/git/ignore
- config/shell/git.sh, path.sh, tmux.sh, mcp.sh
- config/claude/settings.json, commands/*, skills/*, agents/*, hooks/*, scripts/*
- lib/install-common.sh, install-packages.sh, secrets.sh, dialog-ui.sh, backup.sh
- installers/* (all)
- tests/* (all)
- images/*
- config/nushell/config.nu, env.nu, scripts/*, README.md, QUICK_START.md

### Dirty (need sanitization): ~15 files
- config/shell/env.sh — remove AZDO_ORG value
- config/shell/aliases.sh — remove employer aliases (lines 85-86)
- config/shell/secrets.sh — review PAT export variable names
- config/bash/bash_aliases — strip to useful generic aliases only
- config/zsh/zshrc — check for keychain PAT retrieval
- config/nushell/aliases.nu — remove employer aliases (lines 69-70)
- config/mcp/servers.json — create template version
- config/mcp/README.md — replace private IPs
- config/mcp/mcp-env.template — replace private IPs
- config/claude/hooks/config.json — replace memory-mcp hostname
- azcli-scripts/ado-task — parameterize DEFAULT_ORG
- bootstrap.sh — replace danielpmo1371 with nuvemlabs
- index.html — replace username references
- README.md — rewrite for public
- util-scripts/copy-bootstraph-line.sh — update username

### Exclude (don't copy):
- config/claude/claude.json (gitignored)
- util-scripts/copy-mbie-pat.sh (private only)
- router-backups/* (private only)
- docs/plans/* (planning docs)
- config/claude/settings.json.bak (backup file)
- .bashrc (root level — legacy)
- brew-gadgets.md, term-gadgets.md, todo.md, todos.md, wishlist.md (personal notes)
- issues/* (personal issue tracking)

### New files to create:
- lib/template.sh — lightweight envsubst wrapper
- lib/overlay.sh — private overlay detection
- .gitignore — comprehensive
- .gitleaks.toml — secret scanning config
- LICENSE — MIT
- config/shell/env.local.template — example private env vars
- docs/customization.md — how to personalize

## Private Data Patterns (for agents to scan/avoid)
- `mbie-immigrationnz-prod` or `mbie` (employer)
- `INZ_TDS_DEV`, `INZ_TDS_SIT` (Azure subscriptions)
- `10.0.0.102` (private IP)
- `192.168.1.107` (private IP)
- `memory-mcp:8000` (private hostname)
- `danielpmo1371` (private GitHub username) — replace with `nuvemlabs`
- `danielpmo@gmail.com` (email)
- Any PAT/token values
- `/c/repos/`, `/mnt/c/Users/daniel.paiva/` (WSL paths)

## Log
- [2026-03-04] Audit complete: identified all private data across 215 tracked files
- [2026-03-04] Planning phase complete: 3 documents in docs/plans/
- [2026-03-04] User approved: from-scratch build, overlay model, gitignore claude.json
- [2026-03-04] Starting Phase 1: Build public repo
- [2026-03-04] Phase 1 COMPLETE: 222 files in dotfiles-public
  - 195 clean files copied
  - 15 config files sanitized (config-builder agent)
  - 10 scripts/entry points sanitized (scripts-builder agent, found bonus fixes in azcli-scripts)
  - 7 new infrastructure files created (infra-docs agent)
  - Full private data scan: ZERO matches
  - Excluded files verified absent (PAT scripts, claude.json, router backups)
- NEXT: Phase 2 — Test public repo (Docker e2e, install.sh validation)
- [2026-03-11] JUDGMENT ERROR ANALYSIS & LEARNING
  - Identified critical error: edited installed library instead of source
  - Created comprehensive analysis: docs/judgment-error-analysis.md
  - Applied proper fix to source repo: ~/repos/secrets/secrets.sh
  - Committed fix to nuvemlabs/secrets repo (commit 2a32583)
  - Reinstalled library to apply fix: ./install.sh --secrets
  - Verified fix works in both bash and zsh
  - Updated CLAUDE.md (project + global) with External Dependency Safety Rules
  - Stored lesson in MCP memory with tags
  - New protocol: Always verify file ownership with git ls-files before editing
