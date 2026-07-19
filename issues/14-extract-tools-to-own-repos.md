# Extract standalone tools into their own repos

Some things in here stopped being config and became products. They should live
in their own repos: own tests, own versioning, installable without cloning all
of dotfiles.

**Blocked on:** `todo.md` "remove non-public data from repo". Candidates 3 and 4
carry employer identifiers (`mbie-immigrationnz-prod`, `travellerdirectives`,
`INZ_*`, pipeline id `802`) that leak on publish. Tier 1 does not and can go first.

## Tier 1 — low coupling, generally useful

1. **skill-forge + claude-agent-forge** (~2700 LOC)
   `config/claude/skills/{skill-forge,claude-agent-forge}/`
   Grep for `dotfiles` across both dirs: zero hits. `scripts/validate-skill.sh`
   already takes a skill dir as its only arg. Needs: `plugin.json` wrapper,
   tests for the validator.

2. **destructive-ops-guard** (193 LOC, one file)
   `config/claude/hooks/destructive-ops-guard.sh`
   stdin + `jq`, fails closed if `jq` missing. No AZDO/employer specifics.
   Most portable single file in the repo. Pairs naturally with (3).

3. **AZDO pipeline safety system** (~2700 LOC incl. 713 of tests)
   `config/claude/{scripts,hooks}/pipeline-*.sh`, `scripts/fetch-azdo-pipeline-logs.sh`,
   `tests/test-pipeline-{validator,hooks}.sh`, `installers/claude-azdo-pipeline-hooks.sh`,
   `skills/pipeline-ops/`, `agents/pipeline-runner.md`, `commands/pipe-deploy.md`
   Best-engineered thing here. `registry_committed_or_die()` (pipeline-validator.sh:53-70)
   fails closed when the registry drifts from its git-committed state — that idea
   is publishable on its own. Two black-box harnesses using throwaway `$HOME`s.
   Blockers: `pipeline-guard.sh:20-21` hardcodes `TERRAFORM_PIPELINE_ID=802` and
   `apply_travellerdirectives`; `pipeline-registry.sh:44,69` reference `td-api`;
   `pipeline-runner.md` is full of employer specifics. Must become registry-driven
   config. Installer sources `lib/install-common.sh` (~40 lines to inline).

## Tier 2 — already most of the way there

4. **sdlc-framework plugin** (4560 LOC)
   `config/claude/plugins/sdlc-framework/`
   Has package.json, plugin.json, README, DEVELOPER.md, 125 mocha cases.
   One line blocks it: `scripts/setup.sh:33` hardcodes
   `${HOME}/repos/dotfiles/config/claude/plugins`. The 9 `config/claude/agents/sdlc-*.md`
   symlinks dissolve once it is a real plugin repo. Employer repo lists in the
   specialist agents need parameterising.

5. **tmux-claude-picker** (121 LOC)
   `util-scripts/tmux-claude-picker.sh`
   Self-contained, resolves own path, hand-rolled vi modal mode via fzf
   `transform` bindings. The other tmux-*.sh stay — help/tips popups are pure
   content about this config's own keybinds.

## Checked and explicitly NOT candidates

- `config/claude/hooks/{memory,utilities}/` (~10500 LOC JS) — **vendored, not ours**.
  `installers/memory-hooks.sh:16` downloads all 21 files from
  `doobidoo/mcp-memory-service`. Only `hooks/config.json` is local.
- `tuis/teams-tui/` — vendored clone of `nospor/teams-tui` with its own nested
  `.git`. Should be a submodule or dropped, not extracted.
- `config/shell/secrets.sh` — already extracted to `nuvemlabs/secrets`.
- `q` wrapper (`config/shell/aliases.sh:96-130`, 35 lines) — a gist, not a repo.
- `config/nvim/lua/plugins/` — all LazyVim spec tables, zero original code.
- `install.sh` + `lib/` — `docs/plans/open-source-architecture-plan.md` §D5 already
  decided the installer is the repo's differentiating feature and stays. Only
  `lib/backup.sh` and `lib/install-packages.sh` are cleanly separable.

## Unrelated bug found while surveying

`config/claude/hooks/logging/lib-session-dir.sh:13` writes runtime session state
into `~/repos/dotfiles/tmp/claude/sessions` — a hook writing live data into the
dotfiles working tree. Duplicated at `util-scripts/tmux-claude-summaries.sh:20`.
Fix: one `CLAUDE_SESSIONS_DIR` defaulting to
`${XDG_STATE_HOME:-$HOME/.local/state}/claude/sessions`.

## Order

1. remove non-public data (todo.md) — unblocks everything, and is a live exposure
2. Tier 1 items 1 and 2 — no dependency on step 1
3. parameterise employer constants, then item 3
4. item 4, item 5
