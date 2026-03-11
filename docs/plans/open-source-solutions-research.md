# Open-Sourcing Dotfiles: Solutions Research

> Research conducted March 2026. Covers dotfile manager landscape, public/private separation patterns, secret prevention, history scrubbing, templating, repository models, and industry standards.

---

## Table of Contents

1. [Dotfile Manager Landscape](#1-dotfile-manager-landscape)
2. [Public/Private Patterns in Practice](#2-publicprivate-patterns-in-practice)
3. [Secret Prevention in Git](#3-secret-prevention-in-git)
4. [Git History Scrubbing](#4-git-history-scrubbing)
5. [Environment Variable Templating Approaches](#5-environment-variable-templating-approaches)
6. [The Fork Model vs Alternatives](#6-the-fork-model-vs-alternatives)
7. [Industry Standard Assessment](#7-industry-standard-assessment)
8. [Recommendation Summary](#8-recommendation-summary)

---

## 1. Dotfile Manager Landscape

### chezmoi (18k+ stars)

**Approach**: Manages dotfiles in a "source state" directory (`~/.local/share/chezmoi/`), applies them to the home directory as the "target state". Uses Go templates for machine-specific customization.

**Secrets Handling**:
- Native integration with 20+ password managers (1Password, Bitwarden, macOS Keychain, GNOME Keyring, pass, gopass, KeePassXC, AWS Secrets Manager, Azure Key Vault, etc.)
- Whole-file encryption via `age` or `gpg`
- Template functions pull secrets at apply time: `{{ onepasswordRead "..." }}`
- Private files (not committed) via `.chezmoiignore`

**Templates**: Go `text/template` syntax with [sprig](https://masterminds.github.io/sprig/) extensions. Access to `chezmoi.hostname`, `chezmoi.os`, `chezmoi.arch`, plus custom variables in `chezmoi.toml`. Full conditionals, loops, and functions.

**Pros**:
- Single binary, no dependencies
- Most feature-complete tool available
- Excellent cross-platform support (Linux, macOS, Windows)
- Dry-run (`chezmoi diff`) before applying
- Run-once and run-on-change scripts
- Active development, large community

**Cons**:
- Learning curve for Go template syntax
- Password manager integration can be UX-painful (re-auth on every sync per [Kasberg 2026](https://www.mikekasberg.com/blog/2026/01/31/dotfiles-secrets-in-chezmoi.html))
- Requires migrating existing dotfiles into chezmoi's source state
- Opinionated directory structure

**Integration with existing installer**: **Moderate difficulty**. chezmoi would replace the symlink strategy entirely. The modular installer system would need significant rework. Could coexist if chezmoi handles only templated files while the existing installer handles packages and system setup.

### yadm (5k+ stars)

**Approach**: Thin wrapper around a bare Git repo. Your home directory IS the repo. No symlinks needed; files live where they belong.

**Secrets Handling**:
- Encrypt file list in `~/.config/yadm/encrypt` (glob patterns)
- Encrypts to `~/.local/share/yadm/archive` using GPG, OpenSSL, or transcrypt
- `yadm encrypt` / `yadm decrypt` commands
- No password manager integration (manual)

**Templates**: Supports Jinja2-like templates via yadm's built-in processor (since v3). Alt files for OS-specific variants: `file##os.Darwin`, `file##os.Linux`, `file##hostname.mybox`.

**Pros**:
- Minimal learning curve (it's just git)
- No symlinks; files stay in-place
- Alt file system is elegant for OS differences
- Encryption is straightforward
- Bootstrap script support

**Cons**:
- Bare repo approach can feel risky (your $HOME is a git repo)
- Encryption is all-or-nothing per file (can't template secrets into otherwise-public files)
- No password manager integration
- Templating was historically external-dependency-heavy (j2cli, envtpl); now built-in but less powerful than chezmoi

**Integration with existing installer**: **Easy**. yadm could manage the dotfile deployment while the existing installer handles packages. The symlink strategy would be replaced by yadm's bare repo approach, but installers/*.sh scripts stay mostly unchanged.

### GNU Stow (widely used, no single repo)

**Approach**: Symlink farm manager. Organizes files into "packages" (directories). Running `stow package-name` creates symlinks from the package dir to the target directory.

**Secrets Handling**: **None**. Stow is purely a symlink manager. Secrets must be handled entirely separately (gitignored files, separate repo, etc.).

**Templates**: **None**. No templating capability whatsoever. Files are deployed exactly as they exist in the repo.

**Pros**:
- Dead simple mental model
- Reversible (`stow -D` removes symlinks)
- Widely available in package managers
- No lock-in; trivial to migrate away

**Cons**:
- No templating, no secrets, no encryption
- No cross-platform adaptation (no alt files)
- Doesn't handle machine-specific variations
- Conflicts require manual resolution

**Integration with existing installer**: **Trivial but limited**. The existing `link_home_files()` / `link_config_dirs()` functions already do what Stow does. Stow would be a lateral move providing no new capabilities. Not useful for the public/private split problem.

### dotbot (7.5k stars)

**Approach**: YAML-based declarative config (`install.conf.yaml`) describing links, shell commands, and cleanups. Bootstrap via `./install` script.

**Secrets Handling**: **Minimal**. No built-in encryption or secret management. Can run shell commands, so secrets could be fetched via custom scripts. Plugin ecosystem exists but is thin.

**Templates**: **None built-in**. Plugins exist (e.g., dotbot-template) but are community-maintained and not widely adopted.

**Pros**:
- Clean, declarative YAML configuration
- Plugin architecture (dotbot-brew, dotbot-apt, dotbot-template, dotbot-stow)
- Good for bootstrapping (single `./install` command)
- Template for structuring dotfiles repo

**Cons**:
- Python dependency
- Limited feature set compared to chezmoi/yadm
- Plugin ecosystem is fragmented and variably maintained
- No built-in handling of public/private split

**Integration with existing installer**: **Easy but low value**. Dotbot's link/shell model could replace parts of the installer, but wouldn't add meaningful capability for the public/private problem. The existing installer is already more capable.

### home-manager (Nix) (9.4k stars)

**Approach**: Declarative, reproducible home directory management using the Nix language. Entire system configuration expressed as Nix expressions. Atomic, rollback-capable deployments.

**Secrets Handling**:
- **sops-nix**: Encrypts secrets with age/GPG, decrypts at activation. Home-manager module available. Per-file access control. Secrets stored encrypted in the Nix store.
- **agenix**: SSH-key-based encryption, home-manager module available. Simpler than sops-nix but less flexible.
- Both allow secrets to be checked into the repo encrypted

**Templates**: The entire Nix language IS the template system. Conditionals, functions, imports, overlays. Most powerful but also most complex.

**Pros**:
- Maximum reproducibility and rollback capability
- sops-nix/agenix are production-grade secrets solutions
- Atomic deployments (no partial states)
- Handles packages AND configs in one system

**Cons**:
- **Massive learning curve** (Nix language, flakes, etc.)
- Nix must be installed on every target machine
- Not practical for sharing with non-Nix users
- Slow evaluation times
- Would require complete rewrite of existing system

**Integration with existing installer**: **Not practical**. Would require a ground-up rewrite. The Nix ecosystem is its own world. Only viable if the user wants to go all-in on Nix, which would eliminate the cross-platform shell-script installer entirely.

### Comparison Summary

| Feature | chezmoi | yadm | Stow | dotbot | home-manager |
|---|---|---|---|---|---|
| Secrets/Encryption | Native (20+ PW managers) | GPG/OpenSSL | None | None | sops-nix/agenix |
| Templates | Go templates (powerful) | Built-in (moderate) | None | Plugins (weak) | Nix lang (most powerful) |
| Cross-platform | Linux/macOS/Windows | Linux/macOS/Windows | Linux/macOS | Linux/macOS | Linux/macOS |
| Symlinks | No (copies) | No (bare repo) | Yes | Yes | No (Nix store) |
| Learning curve | Moderate | Low | Very Low | Low | Very High |
| Integration effort | Moderate | Easy | Trivial | Easy | Complete rewrite |
| Private file support | Built-in | Encryption only | Manual | Manual | Built-in |

---

## 2. Public/Private Patterns in Practice

### Pattern A: gitignore + Local Files (Most Common)

**How it works**: Public repo contains references to local files that are gitignored. For example:
- `~/.gitconfig` includes `~/.gitconfig_local` (gitignored)
- `~/.zshrc` sources `~/.zsh_secrets` (gitignored)
- `.env.local` files alongside `.env.template` files

**Real-world examples**: This is the dominant pattern. [Lobsters discussion](https://lobste.rs/s/nbdkuf/if_you_have_public_dotfiles_repo_do_you) shows most developers use this approach. The existing dotfiles repo already uses this pattern with `config/mcp/mcp-env.local` (gitignored) alongside `mcp-env.template`.

**Pros**: Simple, no tooling required, works with any dotfile manager
**Cons**: Easy to forget the `.local` file on new machines, no automation for populating secrets, relies on discipline

### Pattern B: Encrypted Files in Repo

**How it works**: Sensitive files are encrypted and committed to the repo. Decrypted at install time.
- **git-crypt**: Transparent encryption via git filters. Specify files in `.gitattributes`. Encrypted at rest, decrypted on checkout if you have the key.
- **age**: Modern encryption tool. Used by chezmoi and sops-nix. SSH key reuse possible.
- **SOPS (Mozilla)**: Encrypts only values in YAML/JSON, leaving keys readable. Great for config files where structure matters.

**Real-world examples**: chezmoi users commonly encrypt `.ssh/config`, API key files, etc. Infrastructure repos use SOPS+age extensively.

**Pros**: Single repo, secrets travel with the code, auditable
**Cons**: Key distribution problem, encrypted diffs are useless, requires tooling

### Pattern C: Dual Repository (Public + Private Submodule)

**How it works**: Public dotfiles repo contains a git submodule pointing to a private repo. Private repo holds sensitive configs. Conditional logic detects if submodule is initialized.

**Real-world examples**: [Simone De Nadai's approach](https://www.simonedenadai.com/blog/dotfiles-repository-with-submodule/). Some use `.dotfiles-work` and `.dotfiles-personal` as submodules.

**Pros**: Clean separation, private repo stays private, public repo works without private
**Cons**: Submodule complexity (init, update, sync), CI/CD needs SSH keys, two repos to maintain

### Pattern D: Password Manager at Runtime

**How it works**: Configs are templates. At apply time, secrets are fetched from a password manager (1Password CLI, Bitwarden CLI, macOS Keychain, etc.) and injected.

**Real-world examples**: chezmoi's primary pattern. The existing dotfiles repo already does this with `lib/secrets.sh` using macOS Keychain and Linux libsecret.

**Pros**: Secrets never touch disk in plaintext (in theory), single source of truth
**Cons**: Requires password manager on every machine, auth friction (unlock vault), offline access issues

### Pattern E: Separate Sync for Secrets

**How it works**: Sensitive files synced via a separate mechanism (cloud storage, private git repo, rsync, Syncthing) and referenced from dotfiles.

**Real-world examples**: Lobsters commenters mention using Dropbox/iCloud for `~/.ssh`, syncing `.local` files separately.

**Pros**: Complete separation of concerns, no encryption complexity
**Cons**: Two sync mechanisms to manage, easy to get out of sync, manual setup on new machines

### What the Community Actually Does (2025-2026)

Based on [Lobsters](https://lobste.rs/s/nbdkuf/if_you_have_public_dotfiles_repo_do_you), [HN](https://news.ycombinator.com/item?id=34296396), and [dotfiles.github.io](https://dotfiles.github.io/):

1. **Most popular**: gitignore + local files (Pattern A) — simplest, lowest friction
2. **Growing**: chezmoi with password manager integration (Pattern D) — for multi-machine users
3. **DevOps-oriented**: SOPS + age encryption (Pattern B) — for infrastructure people
4. **Enterprise**: Dual repo with submodule (Pattern C) — when work/personal separation is critical
5. **Nix users**: sops-nix/agenix — but only within the Nix ecosystem

---

## 3. Secret Prevention in Git

### gitleaks

**How it works**: Regex-based scanner with 150+ built-in rules for common secret patterns. Scans git history or staged changes.

**Pre-commit reliability**: Very reliable. Fast execution (Go binary). Can run as pre-commit hook or GitHub Action.

**False positive rate**: Moderate. Entropy-based detection can flag non-secrets. Mitigated by:
- `gitleaks:allow` inline comment to mark false positives
- `.gitleaks.toml` config to customize rules and allowlists
- Path-based exclusions

**Best for**: Individual developers and small teams. Single binary, no dependencies.

**Source**: [gitleaks GitHub](https://github.com/gitleaks/gitleaks)

### detect-secrets (Yelp)

**How it works**: Uses a "baseline" approach. Creates `.secrets.baseline` file with hashes of known secrets. Pre-commit hook blocks only NEW secrets, not existing ones.

**The baseline concept**: `detect-secrets scan > .secrets.baseline` creates the initial state. The hook then only flags changes that introduce secrets not in the baseline. This is elegant for repos with existing secrets — you can adopt it without remediating everything first.

**Detection strategies**: 27 built-in detectors across three categories:
1. Regex-based (AWS keys, GitHub tokens, etc.)
2. Entropy detection (Base64, Hex high-entropy strings)
3. Keyword detection (variable names like `password =`, `api_key =`)

**False positive rate**: Lower than gitleaks due to the baseline approach. You audit once, then only new findings need review.

**Best for**: Teams with existing repos that have historical secrets. The baseline lets you adopt incrementally.

**Source**: [Yelp/detect-secrets](https://github.com/Yelp/detect-secrets)

### trufflehog

**How it works**: Scans git history, filesystems, and cloud services. Key differentiator: **verifies** detected secrets by testing them against the actual service (e.g., tries to auth with a found AWS key).

**Pre-commit hook**: Supported, but heavier than gitleaks. The verification step adds latency.

**False positive rate**: Lowest of the three (when verification is enabled), but verification means:
- Network calls during commit (slow)
- Privacy implications (your secret is being "tested")
- Only works for services with verification support

**Best for**: CI/CD pipelines and periodic audits rather than pre-commit hooks. The verification feature is its killer feature for finding actually-exploitable leaks.

**Source**: [trufflehog GitHub](https://github.com/trufflesecurity/trufflehog)

### Custom git hooks

**What they catch**: Simple pattern matching (regex for `ghp_`, `sk-`, base64 patterns, high entropy strings). Can also check for specific filenames (`.env`, `.pem`, `id_rsa`).

**What they miss**: Obfuscated secrets, secrets in binary files, secrets that don't match known patterns, rotated/custom secret formats.

**Best combined with**: `.gitattributes` filter drivers for transparent encryption, `.gitignore` for known-sensitive paths.

### Recommendation for This Repo

**Primary**: gitleaks as pre-commit hook. Fast, single binary, good rule set.
**Secondary**: detect-secrets baseline for the initial audit before open-sourcing.
**CI**: gitleaks GitHub Action on PRs.

Implementation:
```bash
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.x.x
    hooks:
      - id: gitleaks
```

Plus a custom `.gitleaks.toml` with:
- Allowlist for template files (`mcp-env.template`, etc.)
- Path exclusions for test fixtures
- Custom rules for patterns specific to this repo (Azure DevOps PATs, MCP URLs)

---

## 4. Git History Scrubbing

### git filter-repo (Recommended, 2025+)

**Status**: Officially recommended replacement for `git filter-branch`. Maintained by Elijah Newren. 8k+ stars.

**Capabilities**:
- Remove files by path: `git filter-repo --path config/mcp/mcp-env.local --invert-paths`
- Replace text patterns: `git filter-repo --replace-text expressions.txt` where the file contains `regex:ghp_[A-Za-z0-9]{36}==>REDACTED`
- Remove by blob content, file size, author, etc.
- Preserves history structure (merge commits, branches)

**Gotchas**:
1. **Must be a fresh clone** — refuses to run on repos with uncommitted changes or existing remotes (safety measure)
2. **Force push required** — all commit hashes change, requiring `git push --force`
3. **Collaborator impact** — existing clones become incompatible. Best to give everyone a new repo URL
4. **GitHub cache** — GitHub may cache old objects. Contact GitHub support for large repos, or delete and recreate the repo
5. **Tags rewritten** — existing tag references become invalid. Users must delete and re-fetch tags
6. **Protected branches** — may block force push. Temporarily disable protection
7. **PRs/Issues** — references to old commit SHAs become broken

**Source**: [git-filter-repo GitHub](https://github.com/newren/git-filter-repo)

### BFG Repo-Cleaner

**Status**: Mature, stable, but less actively maintained than git filter-repo. Written in Scala (requires JVM).

**Capabilities**:
- Remove files by name: `bfg --delete-files id_rsa`
- Replace text: `bfg --replace-text passwords.txt`
- Remove large files: `bfg --strip-blobs-bigger-than 10M`
- 10-720x faster than git filter-branch

**Limitations**: Cannot do complex rewrites (path-based conditions, etc.). Less flexible than git filter-repo.

**Source**: [BFG Repo-Cleaner](https://rtyley.github.io/bfg-repo-cleaner/)

### Recommended Approach for This Repo

1. **Audit first**: Run `gitleaks detect --source . --report-format json` to find all historical secrets
2. **Create expressions file** for git filter-repo with regex patterns for:
   - PAT tokens (Azure DevOps, GitHub)
   - Private IPs (10.x.x.x, 192.168.x.x patterns in committed files)
   - API keys
   - Employer-specific identifiers
3. **Fresh clone** → run `git filter-repo --replace-text expressions.txt`
4. **Verify** the cleaned history with another gitleaks scan
5. **Push to a new repo** (cleanest approach — avoids GitHub cache issues)

### Critical Decision Point

If history scrubbing seems too risky or complex, the alternative is:
- **Start fresh**: Create a new repo with a squashed initial commit from the current state (after removing secrets)
- **Pros**: Clean slate, no risk of missed secrets in history
- **Cons**: Lose all git history, lose commit attribution

---

## 5. Environment Variable Templating Approaches

### envsubst

**How it works**: Replaces `${VAR}` / `$VAR` in stdin with environment variable values. Part of GNU gettext.

**Limitations**:
- No conditionals, loops, or logic
- No default values (`${VAR:-default}` is bash syntax, not envsubst)
- No escaping mechanism (can't have a literal `$VAR` in output)
- Replaces ALL environment variables (use `--variables` to restrict)

**Best for**: Simple token replacement in CI/CD. Not suitable for complex dotfile templates.

**Example**:
```bash
envsubst < config/mcp/servers.json.template > config/mcp/servers.json
```

### chezmoi Templates (Go text/template + sprig)

**Power**: Full conditionals, loops, functions, pipelines. Access to machine data, custom variables, password manager values.

**Complexity**: Go template syntax is initially unfamiliar but well-documented. The `{{ if }}` / `{{ else }}` / `{{ end }}` pattern handles most needs.

**Example**:
```
{{ if eq .chezmoi.os "darwin" -}}
export HOMEBREW_PREFIX="/opt/homebrew"
{{ else -}}
export HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
{{ end -}}
```

**Verdict**: Best balance of power and usability for dotfiles. The learning curve is real but manageable.

### m4 macros

**Status**: Nobody uses this for dotfiles in practice. Powerful but arcane syntax. Not recommended.

### sed/awk substitution at install time

**How it works**: `sed -e "s/@@HOSTNAME@@/$(hostname)/g" template.conf > output.conf`

**Limitations**:
- Fragile: delimiter conflicts, special characters in values
- No conditionals or logic
- Easy to introduce bugs with complex patterns
- Hard to maintain as templates grow

**Best for**: One-off simple substitutions in install scripts. The existing repo already uses this pattern implicitly.

### Custom template engine (when justified)

**When it's justified**: When you need:
- Shell-native execution (no external dependencies)
- Integration with existing installer system
- Simple variable replacement plus conditionals
- No desire to adopt a full dotfile manager

**Implementation**: A 50-100 line bash function that reads `{{VAR}}` placeholders, supports `{{#if CONDITION}}...{{/if}}`, and pulls values from environment or a config file.

**Verdict**: This is what the existing repo should consider if not adopting chezmoi. A lightweight template function in `lib/` that handles the 80% case (variable substitution + OS conditionals) without adding external dependencies.

### Recommendation

| Approach | When to use |
|---|---|
| envsubst | CI/CD token replacement only |
| chezmoi templates | If adopting chezmoi as dotfile manager |
| sed substitution | Existing one-off uses are fine |
| Custom lightweight | If staying with custom installer and need templating for public/private split |

---

## 6. The Fork Model vs Alternatives

### Fork Model (Public upstream + private fork)

**How it works**: Public repo is the "upstream". User forks it, adds personal commits (secrets, work aliases) to their fork. Periodically pulls upstream changes.

**GitHub behavior**: Forks share the same network. Private forks of public repos are not truly private on GitHub (GitHub staff can see them, and if the public repo is deleted, forks may become public). **This is a significant security concern for secrets.**

**Maintenance burden**: Merge conflicts on every upstream update if personal changes touch the same files. Rebasing works but is error-prone. Gets worse over time.

**Failure modes**:
- Accidentally pushing personal commits to upstream
- Merge conflict fatigue leading to abandoned sync
- GitHub fork visibility concerns

**Verdict**: **Not recommended** for dotfiles with secrets. The merge conflict burden is high and the GitHub fork security model is problematic.

### Overlay Model (Two repos, private overlays public)

**How it works**: Public repo contains the base configuration. A second, private repo contains overrides that are layered on top at install time. The install script checks for the overlay repo and applies its files after the base.

**Implementation**:
```bash
# In installer
if [ -d "$HOME/.dotfiles-private" ]; then
    # Apply private overrides (same directory structure)
    cp -r "$HOME/.dotfiles-private/config/" "$HOME/.config/"
fi
```

**chezmoi variant**: chezmoi's "external" sources can pull from multiple repos. The source state can include files from private repos.

**Real-world examples**: This is essentially how chezmoi works with its source state plus externals.

**Maintenance burden**: Low to moderate. Files either exist in private overlay or they don't. No merge conflicts. Public repo must be designed to gracefully handle missing private files.

**Failure modes**:
- Forgetting to update both repos
- Public repo breaking when private overlay is missing (if not designed carefully)

**Verdict**: **Good option** if the existing installer system is preserved. The install script already has the infrastructure (`source` calls, conditional paths).

### Branch Model (main = public, personal = private branch)

**How it works**: `main` branch is public/clean. A `personal` branch adds private configs on top. Regularly rebase `personal` onto `main`.

**Maintenance burden**: Constant rebasing. Every change to `main` requires rebasing `personal`. Gets painful with many divergent files.

**Failure modes**:
- Accidentally pushing `personal` to the public remote
- Rebase conflicts accumulate
- Hard to review what's "personal" vs "public" over time

**Verdict**: **Not recommended**. The rebasing tax is significant and the risk of accidentally exposing the personal branch is real.

### Submodule Model (Private config as git submodule)

**How it works**: Public repo has a git submodule pointing to a private repo. Private repo contains sensitive files. Public repo works without the submodule (graceful degradation).

**Implementation**:
```bash
# Public repo
git submodule add git@github.com:user/dotfiles-private.git private/

# In scripts, check for submodule
if [ -d "$DOTFILES_ROOT/private/config" ]; then
    source "$DOTFILES_ROOT/private/config/secrets.sh"
fi
```

**Maintenance burden**: Moderate. Submodules require `git submodule init && git submodule update`. CI/CD needs SSH key access to private repo. Forgetting `--recurse-submodules` on clone is common.

**Failure modes**:
- Submodule pointing to wrong commit
- CI failing without private repo access
- Contributors confused by submodule workflow

**Verdict**: **Viable but has UX friction**. Works well if the private repo is small and rarely changes.

### Encryption Model (Single repo with encrypted files)

**How it works**: Single repo. Sensitive files encrypted at rest. Three approaches:

**git-crypt**:
- Transparent encryption via `.gitattributes` filters
- Files encrypted on push, decrypted on checkout (if you have the key)
- Uses GPG or symmetric key
- Cannot revoke access (limitation)
- Best when most repo is public with a few encrypted files

**SOPS + age**:
- Encrypts only VALUES in YAML/JSON (keys stay readable)
- `age` keys are simpler than GPG (can reuse SSH keys)
- Not transparent (need to run sops to edit)
- Best for structured config files

**age (via chezmoi)**:
- chezmoi can encrypt individual files with age
- Decrypted at `chezmoi apply` time
- Simple key management (age keygen)

**Maintenance burden**: Low once set up. Key distribution is the main challenge.

**Failure modes**:
- Losing the encryption key (no recovery)
- Accidentally committing unencrypted version
- Encrypted diffs are not reviewable

**Verdict**: **Good for structured secrets** (API keys in JSON, SSH configs). Less good for large binary secrets or frequently-edited files.

### Model Comparison Matrix

| Model | Merge Conflicts | Security Risk | Setup Complexity | Maintenance | Contributor-Friendly |
|---|---|---|---|---|---|
| Fork | High | Medium (GitHub visibility) | Low | High (rebasing) | Low |
| Overlay | None | Low | Medium | Low | High |
| Branch | High | High (accidental push) | Low | High (rebasing) | Low |
| Submodule | None | Low | Medium | Medium | Medium |
| Encryption | None | Low (key management) | Medium | Low | Medium |

---

## 7. Industry Standard Assessment

### What a Best-in-Class Open Source Dotfiles Repo Looks Like (2025-2026)

Based on analysis of top-starred dotfiles repos ([awesome-dotfiles](https://github.com/webpro/awesome-dotfiles), [dotfiles.github.io](https://dotfiles.github.io/)):

#### Must-Haves

1. **One-line install**: `curl -fsSL https://example.com/install.sh | bash` or `git clone && ./install.sh`
2. **Modular components**: Choose what to install (shells, editors, tools, etc.)
3. **Cross-platform**: At minimum macOS + Ubuntu. Bonus: other distros, WSL
4. **Idempotent**: Running installer twice produces the same result
5. **Backup existing configs**: Don't destroy user's existing files
6. **Clear README**: Screenshots/terminal recordings, feature list, prerequisites
7. **No secrets in history**: Clean git history, pre-commit hooks preventing leaks
8. **Template for personalization**: Clear mechanism for users to customize

#### Nice-to-Haves

9. **CI testing**: GitHub Actions testing install on multiple platforms
10. **Uninstaller/restore**: Way to undo changes
11. **Secret management docs**: Clear guide on how to add personal secrets
12. **Contributing guide**: How to submit PRs, what's in scope
13. **License**: MIT or similar permissive license
14. **Changelog/releases**: Tagged versions for stability

#### README Structure (Based on 1000+ Star Repos)

```markdown
# dotfiles

Brief description + screenshot/gif

## Features
- Bullet list of key features

## Quick Start
- One-liner install command
- What happens when you run it

## What's Included
- Table or tree of components

## Customization
- How to personalize (local files, templates, etc.)

## Screenshots
- Terminal with theme applied
- Editor setup

## Requirements
- OS, dependencies

## Detailed Installation
- Step by step for each component

## Architecture
- How the repo is organized
- How symlinks/templates work

## FAQ
- Common issues

## Credits / Inspiration
- Links to dotfiles that inspired this
```

### What Developers Actually Want (from community surveys and discussions)

1. **Inspiration/Discovery**: Browsing for config snippets and tool recommendations
2. **Copy-paste-ability**: Individual configs should work standalone
3. **Documentation of choices**: WHY this shell config, not just WHAT
4. **Opinionated but overridable**: Strong defaults with escape hatches
5. **Fast installation**: Under 5 minutes for basic setup

### Minimum Viable Structure for Community Adoption

```
dotfiles/
  README.md           # Clear, visual, inviting
  install.sh          # Single entry point
  LICENSE             # MIT
  .gitleaks.toml      # Secret scanning config
  config/             # All configs, organized by tool
    shell/            # Shared shell config
    zsh/              # Zsh-specific
    bash/             # Bash-specific
    nvim/             # Editor
    tmux/             # Multiplexer
    git/              # Git config (templated)
  installers/         # Per-component installers
  lib/                # Shared functions
  docs/               # Detailed documentation
  tests/              # CI-testable verification
  .github/
    workflows/        # CI on Ubuntu + macOS
```

---

## 8. Recommendation Summary

### For This Specific Repo

Given the existing architecture (custom modular installer, symlink-based, cross-platform, already uses OS keychain for secrets), the recommended approach is:

#### Tier 1: Essential (Do Before Open-Sourcing)

1. **Audit and scrub git history** using `git filter-repo` or start a fresh repo
2. **Install gitleaks** as pre-commit hook + GitHub Action
3. **Move private data to local files**: Ensure all private IPs, employer-specific configs, PATs are in gitignored `.local` files with `.template` counterparts
4. **Add `.template` files** for everything that needs personalization (MCP servers, git user config, employer aliases)

#### Tier 2: Recommended (Significantly improves usability)

5. **Add lightweight templating** to the installer (`lib/template.sh`) for generating config from templates + local values on first install
6. **Adopt the Overlay Model**: Support an optional `~/.dotfiles-private/` directory that layers on top of the public repo
7. **Add comprehensive README** following the structure above
8. **Add CI testing** (the Docker-based tests already exist — expose them via GitHub Actions)

#### Tier 3: Optional (Nice to have)

9. **Consider chezmoi migration** for the template/secrets layer only (not the package installer)
10. **Add age encryption** for any files that MUST be in the repo but contain sensitive data
11. **Add contributing guide** and issue templates

### What NOT to Do

- Don't adopt Nix/home-manager (too radical a change, excludes most users)
- Don't use the fork model (merge conflict nightmare)
- Don't use the branch model (accidental exposure risk)
- Don't use git-crypt (GPG complexity, no access revocation)
- Don't over-engineer templating (envsubst or a simple custom solution beats a full template engine for this use case)

---

## Sources

### Dotfile Managers
- [chezmoi documentation](https://www.chezmoi.io/)
- [chezmoi comparison table](https://www.chezmoi.io/comparison-table/)
- [chezmoi secrets without password headaches (Kasberg, 2026)](https://www.mikekasberg.com/blog/2026/01/31/dotfiles-secrets-in-chezmoi.html)
- [yadm documentation](https://yadm.io/)
- [yadm encryption docs](https://yadm.io/docs/encryption)
- [yadm GitHub](https://github.com/yadm-dev/yadm)
- [GNU Stow for dotfiles (Penkin, 2025)](https://www.penkin.me/development/tools/productivity/configuration/2025/10/20/my-dotfiles-setup-with-gnu-stow.html)
- [dotbot GitHub](https://github.com/anishathalye/dotfiles_template)
- [home-manager](https://github.com/nix-community/home-manager)
- [sops-nix](https://github.com/Mic92/sops-nix)
- [agenix](https://github.com/ryantm/agenix)
- [sops-nix secrets management (Stapelberg, 2025)](https://michael.stapelberg.ch/posts/2025-08-24-secret-management-with-sops-nix/)

### Community Patterns
- [awesome-dotfiles](https://github.com/webpro/awesome-dotfiles)
- [dotfiles.github.io](https://dotfiles.github.io/)
- [Lobsters: Public dotfiles discussion](https://lobste.rs/s/nbdkuf/if_you_have_public_dotfiles_repo_do_you)
- [Dotfile Management Tools Battle (BigGo, 2024)](https://biggo.com/news/202412191324_dotfile-management-tools-comparison)
- [Exploring Tools for Managing Dotfiles (GBergatto)](https://gbergatto.github.io/posts/tools-managing-dotfiles/)
- [Dotfiles submodule approach (De Nadai)](https://www.simonedenadai.com/blog/dotfiles-repository-with-submodule)

### Secret Prevention
- [gitleaks GitHub](https://github.com/gitleaks/gitleaks)
- [TruffleHog vs Gitleaks comparison (Jit)](https://www.jit.io/resources/appsec-tools/trufflehog-vs-gitleaks-a-detailed-comparison-of-secret-scanning-tools)
- [detect-secrets (Yelp)](https://github.com/Yelp/detect-secrets)
- [detect-secrets 2026 overview](https://appsecsanta.com/detect-secrets)
- [TruffleHog GitHub](https://github.com/trufflesecurity/trufflehog)
- [Best Secret Scanning Tools 2025 (Aikido)](https://www.aikido.dev/blog/top-secret-scanning-tools)

### History Scrubbing
- [git-filter-repo GitHub](https://github.com/newren/git-filter-repo)
- [BFG Repo-Cleaner](https://rtyley.github.io/bfg-repo-cleaner/)
- [Remove secrets from git history (Warp)](https://www.warp.dev/terminus/remove-secret-git-history)
- [git filter-repo guide (git-tower)](https://www.git-tower.com/learn/git/faq/git-filter-repo)
- [Cleaning git history safely (Dev.to)](https://dev.to/balogh08/cleaning-your-git-history-safely-removing-sensitive-data-10i5)

### Encryption Tools
- [git-crypt GitHub](https://github.com/AGWA/git-crypt)
- [age GitHub](https://github.com/FiloSottile/age)
- [SOPS with age guide](https://devops.datenkollektiv.de/using-sops-with-age-and-git-like-a-pro.html)
- [Secrets as Code (Medium/Globant)](https://medium.com/globant/secrets-as-code-a-developers-journey-from-exposure-to-encryption-4bb2c378a27c)

### Templating
- [envsubst automation guide (Karandeep Singh)](https://karandeepsingh.ca/posts/leveraging-envsubst-in-bash-scripts-for-automation/)
- [chezmoi templating docs](https://www.chezmoi.io/user-guide/templating/)
- [chezmoi templates deep dive (PBS)](https://pbs.bartificer.net/pbs124)
