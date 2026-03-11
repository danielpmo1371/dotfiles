# Open-Source Dotfiles: Architecture Plan

> **Date**: 2026-03-04
> **Status**: RECOMMENDATION — Requires user approval before implementation
> **Author**: Arbitrage Planner (synthesis of Vision Analysis + Solutions Research)

---

## Executive Summary

This document synthesizes the Vision Analyst's risk assessment and the Researcher's industry analysis into a single, opinionated architecture recommendation. The goal: transform a sophisticated personal dotfiles system into a public-ready, community-quality developer toolkit while maintaining a private overlay for personal/employer-specific configurations.

**The recommended architecture is: Overlay Model with lightweight templating, gitleaks pre-commit protection, and gitignore-first security.**

This approach preserves the existing custom installer (the repo's competitive advantage), adds a minimal templating layer for env var substitution, and uses a separate private repo for personal overrides — all without adopting an external dotfile manager.

---

## 1. Resolved Decisions

### D1: PAT Revocation — IMMEDIATE ACTION REQUIRED

**Decision**: Revoke both exposed Azure DevOps PATs NOW, before any other work.

**Rationale**: The repo has been public. Even after history scrubbing, anyone who cloned or scraped already has the tokens. There is no "I'll get to it" — this is an active security incident. Every hour of delay increases the exposure window.

**Action**:
1. Go to Azure DevOps > User Settings > Personal Access Tokens
2. Revoke the PAT in `config/claude/claude.json` (lines 3253, 3255)
3. Revoke the PAT in `util-scripts/copy-mbie-pat.sh`
4. Generate new PATs with minimum necessary scope
5. Store new PATs in the OS keychain via `secret_set AZDO_PAT <new_token>`

### D2: claude.json — Split and Gitignore (Disagreeing with User)

**Decision**: Gitignore `claude.json`. Track settings separately via `config/claude/settings.json` (already exists and is tracked).

**Rationale**: The user wants `claude.json` tracked for convenience. I understand the desire — syncing Claude Code preferences across machines is valuable. But the file is a minefield:

- It's a **runtime-managed** file. Claude Code writes tips history, session counters, cached permission gates, OAuth tokens, and MCP server state into it during normal operation.
- It has already leaked PATs to the public internet.
- A pre-commit hook is the **wrong tool** for this. Hooks are bypassable (`--no-verify`), per-clone (not portable), and require the installer to run first. `.gitignore` is persistent, portable, and always active.

**Creative middle ground**: The settings the user actually wants to sync are:
- Editor preferences, verbose mode, theme
- Permission settings and tool allowlists
- Custom key bindings

These already live in `config/claude/settings.json`, which IS tracked and symlinked to `~/.claude/settings.json`. Claude Code reads both files. The fix is simple:

1. Ensure all desired preferences are in `settings.json` (tracked)
2. Add `claude.json` to `.gitignore`
3. The installer already symlinks `settings.json` — no changes needed

For `tmp/claude/sessions/` — these are already gitignored via the `tmp/` rule. No change needed. The user's concern is already addressed.

### D3: "Private Fork" — Separate Private Repository (Overlay)

**Decision**: Create `dotfiles-private` as a **separate private GitHub repository**, not a fork.

**Why not a GitHub fork**: Forks of public repos on GitHub inherit the public network. Private forks are not truly private (GitHub staff visibility, potential visibility if parent is deleted). This is not suitable for secrets.

**Why not a branch model**: The rebase tax is unsustainable. Every change to `main` requires rebasing the personal branch. One accidental push exposes everything.

**Why not submodules**: Submodule UX is notoriously painful (`--recurse-submodules`, detached HEAD state, CI complications). The overlay model achieves the same separation with simpler mechanics.

**Why overlay**: Zero merge conflicts. Files either exist in the overlay or they don't. The public repo works perfectly without the overlay. The private repo is just "extra files." The installer already has the infrastructure for conditional sourcing.

### D4: Threat Model — OSS Community Contribution

**Decision**: Design for the "others clone and use this" scenario.

**Rationale**: The user explicitly wants an "industry-wide standard" that "improves developers' lives." That's the OSS community contribution model. This means:
- Zero personal data in the public repo (not even default values)
- Full templating for personalization
- Clear documentation on how to customize
- Working installation without any private overlay

This is the most demanding model, but if we design for it, the other goals (portfolio piece, personal sync) come for free.

### D5: Dotfile Manager — Stay Custom (with templating addition)

**Decision**: Do NOT adopt chezmoi or yadm. Keep the custom installer. Add lightweight templating.

**Rationale**: The custom installer is this repo's **differentiating feature**:
- Dialog mode with profiles, dependency resolution, backup/restore
- Cross-platform package management (brew, apt, dnf, pacman)
- Modular component selection
- Change reports before installation

No existing dotfile manager provides all of this. Adopting chezmoi would mean throwing away significant, unique work to adopt another tool's opinions.

**What's missing**: A simple templating function. The installer currently assumes config files are ready-to-use symlink targets. For files that need env var substitution (like `servers.json` with private IPs), we need a lightweight template processor. This is a ~60 line bash function, not a new dependency.

### D6: History Scrubbing — Fresh Repo Approach

**Decision**: Create a clean repo from current state rather than surgical history scrubbing.

**Rationale**: The current history contains PATs, private IPs, employer org names, router backup binaries, and employer-specific pipeline IDs across many files and many commits. A surgical scrub with `git filter-repo` is risky — miss one file and the secret survives. A fresh repo:
- Guarantees zero historical secrets
- Is simpler to execute
- Avoids GitHub's commit object caching issues
- Doesn't break existing clones (because the current repo shouldn't have clones relying on it)

**Trade-off**: We lose git history. For a personal dotfiles repo, this is acceptable. The important history is "what works now," not "what changed in 2024."

**Process**: Clean up all files first → commit to current repo → verify with gitleaks → create new repo from clean state → archive old repo as private.

---

## 2. Architecture Recommendation

### The Overlay Model with Lightweight Templating

```
dotfiles/                          (PUBLIC - GitHub)
  install.sh                       Main entry point
  lib/
    install-common.sh              Existing symlink/backup utilities
    install-packages.sh            Existing package management
    template.sh                    NEW: lightweight template processor
  config/
    shell/
      env.sh                       Public defaults only (EDITOR=nvim, etc.)
      env.local.template           Template for private env vars
      aliases.sh                   Public aliases only
      secrets.sh                   Keychain integration (unchanged)
    mcp/
      servers.json.template        Template with ${MCP_BROWSER_HOST} etc.
      mcp-env.template             Existing API key template
    claude/
      settings.json                Tracked Claude Code settings
      CLAUDE.md                    Tracked global instructions
      commands/                    Tracked slash commands
      skills/                      Tracked skills
      agents/                      Tracked agent definitions
    bash/
      bashrc                       Clean, public bashrc
    zsh/
      zshrc                        Clean, public zshrc
    tmux/                          Already clean
    nvim/                           Already clean
    ghostty/                       Already clean
  azcli-scripts/
    ado-task                       Parameterized with $AZDO_ORG
  util-scripts/                    Public utility scripts only
  tests/                           Existing test infrastructure
  docs/                            User documentation
  .gitignore                       Updated with security rules
  .gitleaks.toml                   Secret scanning configuration
  .pre-commit-config.yaml          gitleaks hook
  LICENSE                          MIT
  README.md                        Community-quality documentation

dotfiles-private/                  (PRIVATE - GitHub)
  config/
    shell/
      env.local                    AZDO_ORG, private values
      aliases.local                Employer-specific aliases
    mcp/
      mcp-env.local                API keys
      servers-private.json         Private MCP server entries
    bash/
      bash_aliases.local           Legacy employer aliases
  util-scripts/
    copy-mbie-pat.sh               Employer-specific scripts
  config-backups/
    router-backups/                Router config backups
  install-private.sh               Private overlay installer
```

### How the Overlay Works

The public installer detects and applies the private overlay:

```bash
# In lib/install-common.sh or a new lib/overlay.sh
DOTFILES_PRIVATE="${DOTFILES_PRIVATE:-$HOME/.dotfiles-private}"

apply_overlay() {
    if [[ -d "$DOTFILES_PRIVATE" ]]; then
        log_info "Private overlay detected at $DOTFILES_PRIVATE"
        # Source private env vars
        [[ -f "$DOTFILES_PRIVATE/config/shell/env.local" ]] && \
            source "$DOTFILES_PRIVATE/config/shell/env.local"
        # Process templates with private values
        process_templates
    else
        log_info "No private overlay found. Using defaults."
        log_info "See docs/customization.md for personalization."
    fi
}
```

Shell configs source local files conditionally:

```bash
# At the end of config/shell/env.sh
[[ -f "${DOTFILES_PRIVATE}/config/shell/env.local" ]] && \
    source "${DOTFILES_PRIVATE}/config/shell/env.local"
```

```bash
# At the end of config/shell/aliases.sh
[[ -f "${DOTFILES_PRIVATE}/config/shell/aliases.local" ]] && \
    source "${DOTFILES_PRIVATE}/config/shell/aliases.local"
```

### Template Processing

A new `lib/template.sh` provides simple variable substitution:

```bash
# Process a .template file into its target
# Usage: process_template "source.json.template" "target.json"
process_template() {
    local template="$1"
    local output="$2"

    if [[ ! -f "$template" ]]; then
        log_warn "Template not found: $template"
        return 1
    fi

    # Use envsubst for variable replacement
    # Only substitute explicitly listed variables (safe — won't expand $PATH etc.)
    local vars
    vars=$(grep -oE '\$\{[A-Z_]+\}' "$template" | sort -u | tr '\n' ',' | sed 's/,$//')

    if command -v envsubst &>/dev/null; then
        envsubst "$vars" < "$template" > "$output"
    else
        # Fallback: simple sed-based substitution
        cp "$template" "$output"
        while IFS= read -r var; do
            local name="${var#\$\{}"
            name="${name%\}}"
            local value="${!name:-}"
            sed -i.bak "s|\${${name}}|${value}|g" "$output"
        done <<< "$(grep -oE '\$\{[A-Z_]+\}' "$template" | sort -u)"
        rm -f "${output}.bak"
    fi

    log_success "Generated: $output"
}
```

### What Gets Templated

Only files that contain machine-specific values that can't be sourced at runtime:

| Template File | Output File | Variables |
|---|---|---|
| `config/mcp/servers.json.template` | `~/.claude.json` (merged) | `${MCP_BROWSER_HOST}`, `${AZDO_ORG}` |
| `config/shell/env.local.template` | `~/.dotfiles-private/config/shell/env.local` | Reference only (user fills in values) |

Shell files (`env.sh`, `aliases.sh`) do NOT need templating — they use runtime `source` of `.local` files, which is simpler and more flexible.

---

## 3. The claude.json Problem — Detailed Solution

### Current State

`config/claude/claude.json` is a ~3400 line file containing:
- **Lines 1-100**: User preferences (tips, theme, editor mode) — WANT to track
- **Lines 100-3200**: Cached permission gates, project permissions — NICE to track
- **Lines 3200-3400**: PATs, OAuth tokens, MCP server configs with secrets — MUST NOT track

### Solution: Three-Layer Approach

**Layer 1: `config/claude/settings.json` (tracked, already exists)**
This file already contains the settings the user wants to persist:
- Permission configurations
- Tool allowlists
- Environment variables for Claude Code
- Teammate mode settings

The installer already symlinks this to `~/.claude/settings.json`. Claude Code reads it.

**Layer 2: `config/claude/settings.local.json` (gitignored, per-machine)**
For machine-specific settings that don't belong in the public repo:
- Custom API endpoints
- Machine-specific MCP server overrides
- Per-machine permission overrides

Add to `.gitignore`: `config/claude/settings.local.json`
Add to installer: merge `settings.local.json` into deployed settings if it exists.

**Layer 3: `~/.claude.json` (never tracked, never symlinked)**
Claude Code's runtime state file. Let Claude Code own this completely.
- Tips history, session counters
- OAuth tokens, cached credentials
- Runtime permission gates

**Result**: The user gets settings persistence (Layer 1), machine-specific customization (Layer 2), and Claude Code gets its runtime file (Layer 3). No secrets in the repo. No noisy diffs from runtime writes.

---

## 4. Day-to-Day Workflow

### Making a Change to a Public Config

```
1. Edit the file in ~/repos/dotfiles/config/...
2. Test it (source the file, restart the tool, etc.)
3. git add <file> && git commit -m "description"
4. gitleaks pre-commit hook runs automatically — blocks if secrets detected
5. git push
```

**Friction**: None. Identical to current workflow plus automatic secret scanning.

### Making a Change to a Private Config

```
1. Edit the file in ~/repos/dotfiles-private/config/...
2. Test it (source the file, restart the tool, etc.)
3. cd ~/repos/dotfiles-private
4. git add <file> && git commit -m "description"
5. git push (to private repo)
```

**Friction**: Low. Must remember which repo to commit to. The directory structure mirrors the public repo, so it's intuitive. Shell aliases help:

```bash
alias dotpub='cd ~/repos/dotfiles'
alias dotpriv='cd ~/repos/dotfiles-private'
```

### Setting Up a New Machine

```
1. git clone https://github.com/user/dotfiles.git ~/repos/dotfiles
2. cd ~/repos/dotfiles
3. ./install.sh                    # Interactive dialog mode
4. # Optional: clone private overlay
   git clone git@github.com:user/dotfiles-private.git ~/repos/dotfiles-private
5. ./install.sh --all              # Re-run to apply private overlay
6. # Set secrets via OS keychain
   secret_set AZDO_PAT "your-pat-here"
   secret_set GITHUB_TOKEN "your-token-here"
```

**Without private overlay**: Everything works. Public defaults apply. No errors, no missing files.
**With private overlay**: Employer aliases, private MCP servers, custom env vars are layered on top.

**Time**: Under 5 minutes for base install. Under 10 with private overlay and secrets.

### Adding a New Tool/Config

```
1. Create config in config/<tool>/
2. Create installer in installers/<tool>.sh
3. Add dispatch case in install.sh
4. Test: ./install.sh --<tool>
5. Commit to public repo
6. If any private values needed:
   a. Use ${VAR} placeholder in template, or
   b. Add .local sourcing at end of config file
   c. Add corresponding file to dotfiles-private
```

### How Secrets Flow

```
OS Keychain (macOS Keychain / Linux libsecret)
    ↓ secret() function (lib/secrets.sh)
    ↓
config/shell/secrets.sh
    ↓ exports AZDO_PAT, etc. as env vars
    ↓
Running shell session
    ↓ env vars available to all child processes
    ↓
MCP servers, Azure CLI, etc.
    (read from $AZDO_PAT, $GITHUB_TOKEN, etc.)
```

This flow already exists and works well. No changes needed.

---

## 5. Migration Plan

### Phase 0: Emergency (Day 1 — Do Today)

**Goal**: Stop the bleeding.

| # | Action | Time |
|---|--------|------|
| 0.1 | Revoke both Azure DevOps PATs | 5 min |
| 0.2 | Generate new PATs with minimum scope | 10 min |
| 0.3 | Store new PATs in OS keychain: `secret_set AZDO_PAT "..."` | 2 min |
| 0.4 | Verify secrets.sh still exports correctly | 2 min |
| 0.5 | Add `config/claude/claude.json` to `.gitignore` | 1 min |
| 0.6 | Add `router-backups/` to `.gitignore` | 1 min |

**Validation**: `gitleaks detect --source . --no-git` returns zero findings on current working tree.

### Phase 1: Cleanup (Days 2-3)

**Goal**: Remove all private data from tracked files. Parameterize mixed files.

| # | Action | Details |
|---|--------|---------|
| 1.1 | Clean `config/shell/env.sh` | Remove `AZDO_ORG="mbie-immigrationnz-prod"` (line 37). Keep `export AZDO_ORG` without value — let it come from env.local |
| 1.2 | Clean `config/shell/aliases.sh` | Remove lines 85-86 (`azsetmbdev`, `azsetmbsit`). Add `.local` sourcing at end |
| 1.3 | Clean `config/bash/bash_aliases` | Remove lines 13, 17 (org name, pipeline ID). Or better: delete this file if superseded by `config/shell/aliases.sh` |
| 1.4 | Create `config/mcp/servers.json.template` | Replace `10.0.0.102` with `${MCP_BROWSER_HOST}`, `mbie-immigrationnz-prod` with `${AZDO_ORG}` |
| 1.5 | Clean `config/mcp/README.md` | Replace `10.0.0.102` references with `<your-host-ip>` |
| 1.6 | Clean `config/mcp/mcp-env.template` | Replace `192.168.1.107` with `<your-memory-server-ip>` |
| 1.7 | Parameterize `azcli-scripts/ado-task` | Replace hardcoded `DEFAULT_ORG` with `${AZDO_ORG:-}` |
| 1.8 | Delete `util-scripts/copy-mbie-pat.sh` | Move to dotfiles-private first |
| 1.9 | Clean `bootstrap.sh` | Replace `danielpmo1371` with a configurable variable or remove if not needed |
| 1.10 | Update `index.html` | Replace username-specific references |
| 1.11 | Clean `config/nushell/aliases.nu` | Remove lines 69-70 (INZ_TDS_DEV, INZ_TDS_SIT) |

**Validation**: `grep -rn "mbie\|immigrationnz\|INZ_TDS\|10\.0\.0\.\|192\.168\.\|danielpmo" config/ azcli-scripts/ util-scripts/ --include="*.sh" --include="*.json" --include="*.md" --include="*.nu"` returns zero results.

### Phase 2: Architecture (Days 4-7)

**Goal**: Implement the overlay model, templating, and security tooling.

| # | Action | Details |
|---|--------|---------|
| 2.1 | Create `lib/template.sh` | Lightweight envsubst wrapper (~60 lines) |
| 2.2 | Create `lib/overlay.sh` | Private overlay detection and application |
| 2.3 | Update `config/shell/env.sh` | Add conditional sourcing of `env.local` at end |
| 2.4 | Update `config/shell/aliases.sh` | Add conditional sourcing of `aliases.local` at end |
| 2.5 | Update `installers/mcp.sh` | Process `servers.json.template` → generate `servers.json` before merge |
| 2.6 | Create `dotfiles-private` repo | Private repo with overlay structure |
| 2.7 | Move private files to overlay | `env.local`, `aliases.local`, `copy-mbie-pat.sh`, router backups |
| 2.8 | Install gitleaks | `brew install gitleaks` |
| 2.9 | Create `.gitleaks.toml` | Custom rules, allowlists for templates |
| 2.10 | Create `.pre-commit-config.yaml` | gitleaks hook configuration |
| 2.11 | Update `.gitignore` | Add `*.local`, `*.local.json`, `config/claude/claude.json`, `config-backups/` |
| 2.12 | Create `config/shell/env.local.template` | Example private env vars for users to copy |

### Phase 3: Fresh Repo (Day 8)

**Goal**: Clean start with zero historical secrets.

| # | Action | Details |
|---|--------|---------|
| 3.1 | Final gitleaks audit | `gitleaks detect --source . --report-format json` on entire current repo |
| 3.2 | Run `detect-secrets scan` | Cross-reference with gitleaks findings |
| 3.3 | Fix any remaining findings | |
| 3.4 | Create new GitHub repo | `dotfiles` (public) — or rename current and create fresh |
| 3.5 | Copy clean working tree | All files from current repo (minus `.git/`) into new repo |
| 3.6 | Initial commit | Clean state, verified by gitleaks |
| 3.7 | Archive old repo | Make original private, rename to `dotfiles-archived` |
| 3.8 | Update clones | Update `~/repos/dotfiles` remote to point to new repo |

### Phase 4: Polish (Days 9-14)

**Goal**: Community-ready documentation and CI.

| # | Action | Details |
|---|--------|---------|
| 4.1 | Write comprehensive README | Features, screenshots, quick start, architecture |
| 4.2 | Add MIT LICENSE | |
| 4.3 | Create `docs/customization.md` | How to use private overlay, set secrets, add tools |
| 4.4 | Create `docs/architecture.md` | How the installer works, symlink strategy, overlay model |
| 4.5 | Add GitHub Actions CI | Run Docker tests on Ubuntu + Fedora on push |
| 4.6 | Add gitleaks GitHub Action | Scan PRs for secrets |
| 4.7 | Create CONTRIBUTING.md | If accepting contributions |
| 4.8 | Tag v1.0.0 | First public release |

---

## 6. Trade-off Summary

### What We Gain

| Gain | Impact |
|------|--------|
| Zero secrets in public repo | Eliminates the active security incident |
| Community-usable dotfiles | Any developer can clone and use without modification |
| Private overlay separation | Personal configs never risk leaking to public |
| gitleaks pre-commit scanning | Automated secret detection on every commit |
| Template system for JSON configs | Private IPs, org names substituted at install time |
| Clean git history | No historical secrets to worry about |
| Preserved custom installer | The repo's most unique feature stays intact |
| Structured documentation | Makes the repo actually discoverable and usable |

### What We Give Up

| Loss | Mitigation |
|------|------------|
| Git history | Archive old repo as private; history was mostly iteration, not valuable |
| `claude.json` tracking | Use `settings.json` for the settings that matter; runtime state isn't worth tracking |
| Single-repo simplicity | Two repos is more complex, but the overlay model minimizes friction |
| Direct symlink for MCP config | Template processing adds one step, but only at install time |
| Employer aliases in main repo | Move to `aliases.local` in private overlay; sourced transparently |
| `--no-verify` protection for pre-commit hooks | `.gitignore` provides the real protection; hooks are a bonus layer |

### Risk Matrix

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Forget to commit to correct repo | Medium | Low | Clear directory naming, shell aliases |
| Template variable missing at install time | Low | Low | Template processor warns on unset vars, defaults to empty |
| New contributor bypasses gitleaks | Low | Medium | `.gitignore` is the primary protection; hooks are defense-in-depth |
| `dotfiles-private` diverges from public structure | Medium | Low | Mirror directory structure; overlay is additive only |
| User accidentally adds secret to public file | Low | Medium | gitleaks blocks the commit; `.gitignore` protects known-sensitive paths |

---

## 7. Open Questions for User

These are the **only** questions that must be answered before implementation can begin. Everything else has been resolved above.

### Q1: Have the Azure DevOps PATs been revoked?

This is a yes/no blocking question. If not, Phase 0 must happen before anything else. The PATs in `config/claude/claude.json` and `util-scripts/copy-mbie-pat.sh` have been publicly visible.

### Q2: Do you accept gitignoring claude.json?

I'm recommending against your stated preference. The reasoning is in Section 3 above. `settings.json` already tracks the settings you care about. If you feel strongly about tracking `claude.json`, we can implement a git clean/smudge filter that strips secrets on commit — but this adds complexity and still has edge cases. My strong recommendation is gitignore.

### Q3: Is `config/bash/bash_aliases` still actively used?

This file appears to be a legacy from a WSL/Windows environment (references to `/c/repos/`, `/mnt/c/`). It duplicates many aliases from `config/shell/aliases.sh` and contains employer-specific content. If it's superseded by the shared aliases, I recommend deleting it entirely rather than cleaning it.

### Q4: What's the desired GitHub username/org for the new repo?

Currently `danielpmo1371`. Files like `bootstrap.sh`, `index.html`, `README.md`, and `copy-bootstraph-line.sh` reference this. Should this stay, or is there a preferred username/org for the public repo?

---

## Appendix A: Files Requiring Action (Complete Inventory)

### Delete from public repo (move to private or remove)

| File | Reason | Destination |
|------|--------|-------------|
| `util-scripts/copy-mbie-pat.sh` | Contains literal PAT | dotfiles-private |
| `router-backups/*` | Personal hardware configs | dotfiles-private/config-backups/ |
| `config/claude/claude.json` | Runtime state + secrets | gitignore (machine-local) |

### Clean (remove private data, keep in public repo)

| File | What to Remove |
|------|---------------|
| `config/shell/env.sh:37` | `AZDO_ORG="mbie-immigrationnz-prod"` → `export AZDO_ORG` (no value) |
| `config/shell/aliases.sh:85-86` | `azsetmbdev`, `azsetmbsit` aliases → private overlay |
| `config/bash/bash_aliases:13,17` | Org name, pipeline ID → delete file if legacy |
| `config/nushell/aliases.nu:69-70` | `INZ_TDS_DEV`, `INZ_TDS_SIT` → private overlay |
| `config/mcp/README.md` | `10.0.0.102` (3x) → `<your-host-ip>` |
| `config/mcp/mcp-env.template:20` | `192.168.1.107` → `<your-memory-server-ip>` |
| `azcli-scripts/ado-task:7` | Hardcoded `DEFAULT_ORG` → `${AZDO_ORG:-}` |
| `bootstrap.sh:4,8` | `danielpmo1371` → configurable or keep if desired |
| `index.html` | Username references (4x) → update |
| `util-scripts/copy-bootstraph-line.sh` | Username → update |

### Template (convert to .template + generated output)

| Template | Generated Output | Variables |
|----------|-----------------|-----------|
| `config/mcp/servers.json.template` | Runtime `servers.json` (gitignored) | `${MCP_BROWSER_HOST}`, `${AZDO_ORG}` |

### Add conditional .local sourcing

| File | Add at End |
|------|-----------|
| `config/shell/env.sh` | `source "${DOTFILES_PRIVATE}/config/shell/env.local" 2>/dev/null` |
| `config/shell/aliases.sh` | `source "${DOTFILES_PRIVATE}/config/shell/aliases.local" 2>/dev/null` |

### New files to create

| File | Purpose |
|------|---------|
| `lib/template.sh` | Lightweight envsubst wrapper |
| `lib/overlay.sh` | Private overlay detection/application |
| `.gitleaks.toml` | Secret scanning configuration |
| `.pre-commit-config.yaml` | Pre-commit hook configuration |
| `config/shell/env.local.template` | Example private env var file |
| `LICENSE` | MIT license |
| `README.md` | Community-quality documentation |
| `docs/customization.md` | How to personalize |

### Already protected (no changes needed)

| File | Protection |
|------|-----------|
| `config/mcp/mcp-env.local` | Gitignored via `config/mcp/.gitignore` |
| `tmp/claude/sessions/*` | Gitignored via `tmp/` rule |
| `config/configstore/` | Gitignored |
| `config/nushell/history.*` | Gitignored |

---

## Appendix B: Why Not chezmoi?

This deserves explicit discussion since it's the researcher's "if you want the best tool" recommendation.

**Reasons to adopt chezmoi**:
- Battle-tested templating with Go templates
- Native password manager integration (20+ managers)
- Built-in encryption with age
- Active community, excellent docs
- Solves the public/private split natively

**Reasons to stay custom**:
- The installer's dialog mode, profiles, dependency resolution, and backup/restore are unique features chezmoi doesn't provide
- Migrating to chezmoi means rewriting every installer script
- The repo's value proposition becomes "yet another chezmoi-based dotfiles" instead of "an innovative installer system"
- chezmoi imposes its own directory structure (source state vs target state) — the current flat structure is simpler to understand
- Go template syntax has a real learning curve for contributors
- chezmoi would replace the symlink strategy entirely — every config file relationship changes

**The practical reality**: The only thing chezmoi provides that we truly need is variable substitution in JSON files. A 60-line `lib/template.sh` gives us that. If the templating needs grow significantly (machine-specific conditionals, encrypted files, etc.), chezmoi can be reconsidered later. But for now, the custom approach is both sufficient and strategically correct.

---

*This plan is ready for user review and approval. Implementation should proceed in phase order, with Phase 0 executed immediately.*
