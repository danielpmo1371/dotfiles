# Open-Source Dotfiles: Vision Analysis

> **Date**: 2026-03-04
> **Status**: ANALYSIS — Requires decisions before planning can begin
> **Author**: Vision Analyst Agent

---

## 1. Vision Statement

Transform a personal, bespoke dotfiles repository into a reusable, community-quality developer toolkit that:
- Provides an opinionated but customizable shell, editor, and AI-tooling setup
- Ships safe-by-default with zero private data in the public repo
- Supports a personal overlay via a separate private repository
- Maintains the existing custom installer system as its differentiator

The user wants this to be an "industry-wide standard" that "improves developers' lives" — meaning it must stand on its own for any developer to clone and use, not just as a personal backup.

---

## 2. Critical Urgency: Active Secret Exposure

### The repo is already public

```
$ gh repo view danielpmo1371/dotfiles --json visibility,isPrivate
{"isPrivate":false,"visibility":"PUBLIC"}
```

**Hardcoded PATs currently visible to the internet:**

| File | Line(s) | Secret Type |
|------|---------|-------------|
| `config/claude/claude.json` | 3253, 3255 | Azure DevOps PAT (full 84-char token) |
| `util-scripts/copy-mbie-pat.sh` | 1 | Different Azure DevOps PAT (full token) |

**These PATs must be revoked IMMEDIATELY — before any other work begins.** Even if git history is scrubbed, the tokens have been publicly accessible since they were committed. Any scrub only prevents future discovery; the damage window is already open.

Additionally, `config/claude/claude.json` contains:
- Employer org URL: `https://dev.azure.com/mbie-immigrationnz-prod` (line 3251)
- OAuth session IDs in `customApiKeyResponses` (lines 11-14)
- Email: `danielpmo@gmail.com` (line 3417)
- GitHub repo permissions for `danielpmo1371/dotfiles` (line 3313)

---

## 3. Requirements Decomposition

### R1: Create `config/environment-var/` with README, example file, and `.local` file

**Assessment**: Well-defined. Low complexity.

This creates a dedicated directory for environment variable management, separating the **template** (tracked) from the **values** (gitignored `.local` file). The pattern already exists in `config/mcp/` with `mcp-env.template` / `mcp-env.local`.

**Hidden complexity**: The relationship to `config/shell/env.sh` is unclear. Currently `env.sh` **is** the environment variable file — it's both template and values. Some entries (like `AZDO_ORG="mbie-immigrationnz-prod"`) are private values that should be in a `.local` file, while others (`EDITOR="nvim"`) are public defaults. This means `env.sh` needs to be split, not just supplemented.

**Conflicts**: None.

---

### R2: Move `router-backups/` into `config-backups/`

**Assessment**: Well-defined. Trivial.

Router backups (`broadband_router_backup-10Feb2026.conf`, `backup-ArcherA9v6-2026-02-10.bin`) are hardware-specific configuration files with no business in a public dotfiles repo.

**Hidden complexity**: Should `config-backups/` be gitignored entirely, or should it exist in the repo as an empty directory? The user likely wants it gitignored. Additionally, the binary `.bin` file is in git history — a history scrub is needed.

**Question**: Why not just delete them from the repo and store them elsewhere entirely? Moving them into `config-backups/` and gitignoring it still means they live in the working tree — and in git history.

---

### R3: Public/private fork model

**Assessment**: **Under-defined. Significant complexity.**

The user says "public repo is the main, private fork has personal overrides." This is the most architecturally significant decision and has several fundamental issues:

**GitHub fork semantics**: A fork of a public repo on GitHub is also public. The user must mean a separate private repository, not a GitHub fork. This needs explicit clarification.

**Sync mechanism undefined**: How do changes flow between repos?
- Does the private repo track the public as an upstream remote?
- Are personal overrides in separate files, or patches on top of public files?
- What happens when the public repo changes a file that the private repo also customizes?

**Existing patterns in the wild**:
| Tool | Approach |
|------|----------|
| chezmoi | Templates with `.tmpl` files, data files for personal values |
| yadm | Alt files and encrypted class-based overrides |
| Bare git repos | Two separate repos, manual sync |
| GNU Stow | Separate package directories per machine |

The user's custom installer doesn't have a templating layer, which is what all mature dotfile managers use to solve this problem.

---

### R4: Workflow — normally only change public repo, change private only for personal info

**Assessment**: Well-defined intent, but the **boundary between public and private is fuzzy**.

**Files that are clearly public**: aliases.sh (most of them), git.sh, tmux.conf, nvim config
**Files that are clearly private**: PATs, email, org names
**Files that are mixed (the hard case)**:
- `config/shell/env.sh` — has both `EDITOR=nvim` (public) and `AZDO_ORG=mbie-immigrationnz-prod` (private)
- `config/mcp/servers.json` — has both generic servers (puppeteer, fetch) and private ones (browser-network at `10.0.0.102`, azure-devops with org name)
- `config/shell/aliases.sh` — has both universal aliases (`ls`, `gs`) and employer-specific ones (`azsetmbdev`, `azsetmbsit`)
- `config/claude/claude.json` — Claude Code's runtime state file containing both settings and secrets/session data

**Hidden complexity**: The "only change private for personal info" workflow requires discipline. Without tooling enforcement, it's easy to accidentally add a private value to the public repo. The current repository demonstrates this — the user already committed PATs to the public repo.

---

### R5: Do NOT gitignore `config/claude/claude.json` or `tmp/claude/sessions/` — use pre-commit hook instead

**Assessment**: **High risk. Deserves pushback.**

Current state:
- `tmp/` is already in `.gitignore` — sessions are already protected
- `config/claude/claude.json` is NOT gitignored and contains active PATs

The user's reasoning: they want these files tracked for convenience (settings persistence across machines). The pre-commit hook is meant as a safety net.

**Why this is dangerous:**

1. **`--no-verify` bypasses all hooks.** A single `git commit --no-verify` (or a CI system, or a GUI client that skips hooks) exposes everything.
2. **Hook installation is per-clone.** New contributors or new machines won't have the hook until they run the installer. The window between clone and hook installation is unprotected.
3. **`claude.json` is a runtime-managed file.** Claude Code writes to it during operation (tips history, session counts, cached gates). It's not designed to be user-curated — tracking it in git means constant noisy diffs.
4. **The file mixes settings and secrets.** Lines 1-100 are preferences; lines 3240-3260 contain literal PATs. There's no API to separate them.
5. **`tmp/claude/sessions/` contains work context.** The session files reference employer project names (`app-apim`, `avscanner-api`, `td-api`), Azure DevOps URLs, and work item IDs. These are already gitignored by the `tmp/` rule and should stay that way.

**Recommendation**: This requirement conflicts with security goals. A `.gitignore` is a **persistent, portable, always-active** protection. A pre-commit hook is an **opt-in, per-clone, bypassable** protection. For files containing secrets, gitignore is the correct tool.

For `claude.json` specifically: extract the settings you want to track (editor mode, verbose flag, etc.) into a separate checked-in file, and let Claude Code manage the runtime state file independently. Alternatively, use the existing `config/claude/settings.json` for tracked settings and gitignore `claude.json` entirely.

---

### R6: Move `util-scripts/copy-mbie-pat.sh` to private dotfiles

**Assessment**: Well-defined. Trivial to move. **But also needs history scrub** — the file contains a literal PAT and is in git history on a public repo.

---

### R7: Scrub git history after cleanup

**Assessment**: Well-defined. Moderate complexity.

Tools: `git filter-repo` (already present — `.git/filter-repo/` directory exists) or BFG Repo-Cleaner.

**Hidden complexity**:
- Force-push required, which breaks any existing clones/forks
- Must be coordinated with PAT revocation (scrub history AND revoke tokens)
- Session files in `tmp/claude/sessions/` — are they in git history? (They're gitignored now, but were they ever committed?)
- `router-backups/` binary files in history need scrubbing too

**Prerequisite sequence**:
1. Revoke ALL exposed PATs immediately
2. Make all file-level changes (move, delete, template)
3. Run git filter-repo to remove secrets from history
4. Force-push the clean history
5. Rotate any remaining credentials

---

### R8: Replace private IPs with env var placeholders, install scripts substitute them

**Assessment**: Well-defined. Moderate complexity.

Private IPs found:
| IP | File | Context |
|----|------|---------|
| `10.0.0.102` | `config/mcp/servers.json:8` | Browser MCP SSE endpoint |
| `10.0.0.102` | `config/mcp/README.md` (3 occurrences) | Documentation |
| `10.0.0.102` | `config/claude/claude.json:3275` | MCP server config |
| `192.168.1.107` | `config/mcp/mcp-env.template:20` | Memory MCP server |

**Pattern needed**: Replace literal IPs with env var references (e.g., `$MCP_BROWSER_HOST`) and have the installer or shell sourcing substitute them.

**Complication**: JSON files (`servers.json`, `claude.json`) don't support environment variable expansion natively. The installer would need to use `envsubst` or `sed` to process templates into final config files. This means the checked-in file becomes a template, not a direct symlink target — which changes the current symlink-based architecture.

---

### R9: "Industry-wide standard" dotfiles

**Assessment**: Aspirational. Significant gap between current state and goal.

Current strengths:
- Sophisticated installer with dialog mode, profiles, dependency resolution, backup/restore
- Cross-platform support (macOS, Linux, multiple package managers)
- Modular shell config (env, path, aliases, git, tmux shared across bash/zsh)
- Good tooling choices (LazyVim, p10k, fzf, ripgrep, bat, etc.)
- Claude Code integration (innovative, not commonly seen in dotfile repos)

Current gaps for "industry standard":
- No documentation beyond CLAUDE.md (which is an AI instruction file, not user docs)
- No LICENSE file
- README.md is minimal and not publicly accessible (mode 600)
- No CONTRIBUTING.md
- No templating system for personal values
- Employer-specific configuration baked into "generic" files
- No tests validating cross-platform behavior (Docker tests exist but are Claude-specific)
- `index.html` landing page references a specific GitHub username

---

## 4. Tensions & Contradictions

### T1: "Track claude.json in git" vs "it contains PATs and personal data"

**Severity: HIGH**

A pre-commit hook is a safety net, not a security boundary. The file has already leaked PATs to the public internet. The hook approach:
- Doesn't protect against `--no-verify`
- Doesn't protect new clones before installer runs
- Doesn't protect GUI git clients that may skip hooks
- Doesn't protect CI/CD systems
- Creates a false sense of security

**Resolution path**: Split `claude.json` into tracked settings and gitignored runtime state. Or accept that `claude.json` is a machine-local file that doesn't belong in version control.

### T2: "Public/private fork" vs GitHub fork mechanics

**Severity: MEDIUM**

GitHub forks of public repos are always public. The user needs a separate private repository with the public repo as an upstream remote. This is a "dual-repo" pattern, not a "fork" pattern.

**Unresolved**: What's the merge strategy? Cherry-pick from public to private? Rebase private on public? This directly affects day-to-day workflow friction.

### T3: "Industry standard" vs custom installer system

**Severity: LOW-MEDIUM**

Most widely-adopted dotfiles use established managers (chezmoi, stow, yadm) or are minimal (bare git + symlinks). The custom installer is impressive but creates a "build vs buy" tension:

- **Pro custom**: Full control, dialog mode, dependency resolution, backup/restore — features most dotfile managers lack
- **Con custom**: Every contributor must learn a bespoke system. No community support. Bugs are solo-maintained. Templating must be built from scratch.

**Resolution path**: Not necessarily a blocker. Some of the most-starred dotfiles repos (mathiasbynens, holman) use custom systems. The installer could be the selling point if well-documented.

### T4: "Only change public repo" vs mixed public/private files

**Severity: HIGH**

Several files contain both public and private content:

```
config/shell/env.sh      → EDITOR=nvim (public) + AZDO_ORG=mbie (private)
config/shell/aliases.sh  → ls='lsd' (public) + azsetmbdev (private)
config/mcp/servers.json  → puppeteer (public) + browser-network@10.0.0.102 (private)
```

If these files live in the public repo, the private values must be removed. If they live in the private repo, the public values aren't available to other users. The file must either be:
1. Split into public base + private overlay (merge at install time)
2. Templated with placeholders (substitute at install time)
3. Restructured so private entries are in separate files sourced conditionally

Each approach has different maintenance costs.

### T5: Employer-specific tooling vs generic developer utility

**Severity: MEDIUM**

The `azcli-scripts/` directory contains employer-specific tooling:
- `ado-task` — hardcodes `https://dev.azure.com/mbie-immigrationnz-prod` as DEFAULT_ORG
- `find-peps.sh` — Azure Private Endpoints query
- `azqprop.sh`, `azq-name.sh` — Azure resource queries

These are **useful generic tools** if parameterized, but currently hardcode the employer org. The `ado-task` script in particular is a well-built ADO CLI tool that other developers could benefit from — if the default org were configurable.

---

## 5. Hard Questions

### Q1: PAT revocation urgency

**The repo has been public with PATs since at least commit `213aca1` ("added azure_devops_ext_pat to secrets").** Have these PATs been rotated since? If not, they must be revoked NOW, before any other work.

**Action required**: Check Azure DevOps PAT status and revoke immediately.

### Q2: What is the actual threat model?

- **Personal convenience** (sync dotfiles across own machines) → gitignore secrets, no complex overlay needed
- **OSS community contribution** (others clone and use this) → full templating, documentation, zero personal data
- **Portfolio/resume piece** (show off engineering) → clean code, good docs, but personal data removal less critical

The answer determines how much effort goes into templating vs just removing private data.

### Q3: How many machines does this target?

If it's 1-2 personal machines, the private overlay can be simple (git clone both repos, installer merges). If it's many machines or containers (the Proxmox/LXC environment suggests this), the install/configure cycle must be fast and non-interactive.

### Q4: Is the user willing to adopt a dotfile manager?

Adopting chezmoi would solve:
- Templating (`{{ .email }}` in config files)
- Machine-specific configs (data files per host)
- Secret management (age encryption, 1Password integration)
- Public/private split (built-in external repo support)

But it would mean rewriting the installer system. The custom installer has significant investment and unique features (dialog mode, backup/restore, profile selection). This is a big "buy vs build" decision.

### Q5: What's the maintenance budget?

Keeping public and private repos in sync is ongoing work. Every new config change requires deciding: public or private? Every merge from public to private could conflict. The user should estimate: how much time per week are they willing to spend on dotfiles maintenance?

### Q6: What about the `azcli-scripts/` directory?

These scripts are employer-specific but generically useful. Options:
1. Parameterize and keep in public repo (replace hardcoded org with env vars)
2. Move entirely to private repo
3. Extract into a separate repository (standalone Azure DevOps CLI tools)

### Q7: What about `config/bash/bash_aliases`?

This file has legacy employer-specific content (line 13: Azure DevOps configure with `mbie-immigrationnz-prod`, line 17: pipeline run with `INZ_TDS_DEV`). Is this file still sourced, or has it been superseded by `config/shell/aliases.sh`?

---

## 6. Convenience Assessment

Rating: 1 = seamless, 5 = significant daily friction

| Decision | Friction | Notes |
|----------|----------|-------|
| **Env var substitution at install** | 2/5 | One-time cost at setup. But requires re-running installer when values change. Must handle JSON files specially (no native env var expansion). |
| **Pre-commit hooks for sensitive files** | 3/5 | Must remember to run installer on new clones. False sense of security. Blocks normal workflow when accidentally staging protected files. |
| **Public/private repo syncing** | 4/5 | Every config change requires deciding which repo. Merges from public→private may conflict. Two repos to maintain. Must remember to commit to correct repo. |
| **Template → local file pattern** | 2/5 | Established pattern (`.env.example` → `.env`). Familiar to most developers. Small friction: must create local file on first setup. |
| **Split files (public base + private overlay)** | 3/5 | More files to manage. Source order matters. Debugging config issues means checking two files instead of one. |
| **Gitignore + tracked settings** | 1/5 | Simple, always works. No hook dependency. But means `claude.json` isn't synced across machines. |

---

## 7. Risk Assessment

### Risk 1: Incomplete history scrub

**Probability**: Medium
**Impact**: HIGH (PATs remain discoverable)

If `git filter-repo` misses a file or path, secrets stay in history. Mitigation: use `gitleaks` to scan post-scrub. Consider starting with a fresh repository (squash all history) if comprehensive scrub is too complex.

### Risk 2: PAT not yet revoked

**Probability**: Unknown (depends on user action)
**Impact**: CRITICAL (unauthorized Azure DevOps access)

Two distinct PATs are exposed. Even after history scrub, anyone who cloned or scraped the repo already has them.

### Risk 3: Public/private sync drift

**Probability**: High over time
**Impact**: Medium (broken personal setup)

Without tooling enforcement, the private repo will gradually diverge from public. Configs may break after public updates. Personal values may accidentally leak into public commits.

### Risk 4: Installer doesn't handle templates

**Probability**: Certain (current state)
**Impact**: Medium (blocks env var substitution goal)

The current symlink-based architecture assumes config files are ready-to-use. Template processing (`envsubst`, `sed`) requires a new code path in the installer and changes the mental model from "symlink" to "generate + install."

### Risk 5: New contributor leaks secrets

**Probability**: Medium (if project gains contributors)
**Impact**: HIGH

Without gitignore protection (user prefers hooks), a new contributor who doesn't run the installer first could `git add -A` and push secrets. The hook-based approach has a gap between clone and installer execution.

### Risk 6: `claude.json` schema changes

**Probability**: HIGH (Claude Code updates frequently)
**Impact**: Low-Medium

If `claude.json` is tracked, Claude Code updates may change its structure, causing merge conflicts between machines or between the tracked version and Claude's runtime writes.

---

## 8. Recommended Decision Sequence

Before any implementation planning can begin, these decisions must be made:

```
1. IMMEDIATE: Revoke both exposed Azure DevOps PATs
2. DECIDE: Gitignore claude.json (recommended) vs pre-commit hook (user request)
3. DECIDE: Separate private repo vs dual-branch vs chezmoi
4. DECIDE: Template files (envsubst) vs split files (base + overlay)
5. DECIDE: azcli-scripts — parameterize, move to private, or separate repo
6. DECIDE: Fresh repo (squash history) vs git filter-repo (surgical scrub)
7. THEN: Plan the implementation
```

---

## 9. Inventory: Files Requiring Action

### Must be removed/scrubbed from public repo

| File | Issue | Action |
|------|-------|--------|
| `config/claude/claude.json` | PATs, email, org name, OAuth IDs | Gitignore or template |
| `util-scripts/copy-mbie-pat.sh` | Literal PAT | Delete + history scrub |
| `router-backups/*` | Personal hardware configs | Delete + history scrub |

### Must be parameterized/split

| File | Private Content | Action |
|------|----------------|--------|
| `config/shell/env.sh:37` | `AZDO_ORG="mbie-immigrationnz-prod"` | Move to `.local` or env var |
| `config/shell/aliases.sh:85-86` | `INZ_TDS_DEV`, `INZ_TDS_SIT` | Move to private overlay |
| `config/mcp/servers.json:8,13` | Private IP, org name | Template with env vars |
| `config/mcp/README.md` | Private IP `10.0.0.102` (3x) | Replace with placeholder |
| `config/bash/bash_aliases:13,17` | Org name, pipeline ID | Remove or move to private |
| `config/nushell/aliases.nu:69-70` | `INZ_TDS_DEV`, `INZ_TDS_SIT` | Move to private overlay |
| `azcli-scripts/ado-task:7` | Hardcoded DEFAULT_ORG | Parameterize with env var |
| `bootstrap.sh:4,8` | Username `danielpmo1371` | Parameterize or decide on final username |
| `README.md` | Username references | Update to final username |
| `index.html` | Username references (4 occurrences) | Update to final username |
| `util-scripts/copy-bootstraph-line.sh` | Username | Update |

### Already protected (verify)

| File | Status |
|------|--------|
| `tmp/claude/sessions/*` | Gitignored via `tmp/` rule — CONFIRMED |
| `config/mcp/mcp-env.local` | Gitignored via `config/mcp/.gitignore` — CONFIRMED |
| `config/configstore/` | Gitignored — CONFIRMED |

---

## 10. Summary

The dotfiles repo has strong bones: a sophisticated installer, good tool choices, modular shell config, and innovative Claude Code integration. However, it was built as a personal backup and has accumulated private data that makes it unsuitable for public consumption in its current state.

The **most urgent** action is revoking the two exposed Azure DevOps PATs — this is a security incident, not a planning item.

The **hardest architectural decision** is the public/private split mechanism. This choice cascades into installer changes, file organization, and daily workflow. It should be decided before any code is written.

The **user's request to avoid gitignoring `claude.json`** is the most contentious requirement. It directly conflicts with the security goal and relies on a bypassable mechanism. This deserves an honest conversation about risk acceptance.
