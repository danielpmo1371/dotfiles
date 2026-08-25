# Audit and remove non-public data from repo

Expands the one-liner in `todo.md` ("remove non-public data from repo") into a
scoped issue. This is the hard blocker for issue 14 (extract-tools-to-own-repos)
and for sharing/open-sourcing the dotfiles at all — surfaced while assessing
"would I be proud to share this."

Not a delete-and-commit job: anything found here has been sitting in git
history since it was first added, so removal needs a history rewrite
(`git filter-repo` or equivalent), not just deleting the file in a new commit.

## Found so far

1. **`router-backups/`** — git-tracked, not mentioned anywhere in issue 14's
   audit:
   - `backup-ArcherA9v6-2026-02-10.bin`
   - `broadband_router_backup-10Feb2026.conf`
   Home router config/firmware backups routinely embed WiFi PSK, PPPoE/ISP
   credentials, or admin password hashes. Needs a byte-level check of both
   files, not just a keyword grep (a quick `grep -iE 'psk|password|wpa'` on
   the `.conf` came back empty, which doesn't rule out binary-encoded or
   differently-labelled secrets). Should not be in the repo at all, redacted
   or not — back it up outside git if it's still needed.

2. **`secrets/secrets-list-macos`** — tracked. Confirm it only lists secret
   *names*, not values, before deciding whether it can stay.

3. **Employer-identifying filenames/strings** beyond what issue 14 already
   caught in the pipeline scripts (`mbie-immigrationnz-prod`,
   `travellerdirectives`, `INZ_*`, pipeline id `802`):
   - `util-scripts/copy-mbie-pat.sh` — token value is already redacted
     (`AZDO_PAT_REMOVED_SEE_KEYCHAIN`), but the filename itself names the
     employer (MBIE, a NZ government ministry).
   - `config/claude/skills/archer-verification/` — named after a specific
     client project.
   - `config/claude/skills/fetch-azdo-logs/` and
     `config/claude/agents/fetch-azdo-logs.md` — check for client specifics
     inline, not just in the name.

## Progress

Working-tree org/project identifier cleanup is done (four follow-up commits
on PR #4). This does NOT include the git-history rewrite from the Plan
section below — everything here is a current-tree fix; the strings still
exist in past commits until that history rewrite happens.

**Keychain values now required** for previously-working functionality to
keep working (all via `secret_set KEY "value"`):
`AZDO_ORG` (org slug), `AZDO_ORG_URL` (full URL), `AZDO_PROJECT`,
`PIPELINE_GUARD_TERRAFORM_ID`, `PIPELINE_GUARD_TERRAFORM_APPLY_STAGE`
(`AZDO_PAT` already existed). Until set, `pipeline-guard.sh` fails closed —
**every** pipeline trigger is blocked, not just terraform ones — by design;
see the comment block at the top of that file.

**`config/mcp/servers.json`'s positional org arg**: `installers/mcp.sh`'s
`resolve_secrets()` now also rewrites `secret:KEY` inside `args` arrays
(`resolve_arg_secrets()`), not just `env` blocks, and `servers.json` uses
`"secret:AZDO_ORG"` in place of the literal org name. **Caveat, stated in
code comments**: unlike `env`, it is *not verified* that Claude Code expands
`${VAR}` inside `args` at spawn time the same way. If it doesn't, the
azure-devops MCP server gets the literal string `${AZDO_ORG}` and fails
loudly at connect time — the deliberately safe failure mode, since writing
the raw secret into `args` on disk would defeat the whole point of the
indirection. Needs a live test against a real Claude Code + keychain setup
to confirm either way.

**The AZDO pipeline safety system**
(`config/claude/hooks/pipeline-guard.sh`, `scripts/pipeline-validator.sh`)
no longer hardcodes pipeline id `802` / stage `apply_travellerdirectives`:
- `pipeline-guard.sh`'s Check 4 (terraform apply-stage enforcement) now
  reads `PIPELINE_GUARD_TERRAFORM_ID`/`PIPELINE_GUARD_TERRAFORM_APPLY_STAGE`
  from the environment and **fails closed** (blocks ALL pipeline triggers,
  not just terraform ones) when either is unset. This check deliberately
  stays independent of `pipeline-registry.json` — it's the only protection
  active when the AI isn't inside a registered project directory, so it
  can't depend on a registry being found.
- `pipeline-validator.sh`'s Rule 4 fallback (no registry match for a
  terraform `pipelineId`) no longer emits a hardcoded guess-list of stage
  names to skip (`apply_travellerdirectives`, `apply_flightchecker`,
  `apply_advancedpassengerprocessing`, ...). It now **refuses to approve**
  (`TERRAFORM_NOT_REGISTERED`) instead. This is a genuine safety
  improvement, not just deidentification: a guessed stage-name list is
  wrong by construction for any org whose terraform layout differs, so an
  actual apply/destroy stage with a different name could have slipped
  through unskipped. Refusing to guess can't make that mistake.
- Both test suites (`tests/test-pipeline-hooks.sh`,
  `tests/test-pipeline-validator.sh`) updated to match — 33/33 passing on
  each, including new cases for the fail-closed-when-unconfigured path.
- Doc/example references (`pipeline-runner.md`, `pipe-deploy.md`,
  `REGISTRY.md`, the `sdlc-framework` plugin's example repo names) swapped
  to generic placeholders.

`docs/plans/*.md`, `docs/learning/*.md`, `workflow_state.md`: org/project
name and the terraform-destroy incident's `Pipeline 802`/`td-iac` references
genericized. Historical filename citations of the now-deleted
`util-scripts/copy-mbie-pat.sh` were left as literal text (documenting what
a past commit deleted, not a live identifier).

**Second pass — a different category than org/project (private-network
infra + personal PII), found on re-review after PR #4 merged:**
- **Private LAN IPs**: `10.0.0.102` (`config/mcp/servers.json`'s
  `browser-network.url`, `config/mcp/README.md`) and `192.168.1.107`
  (`config/mcp/mcp-env.template`) were real internal IPs for the home
  server. `README.md`/`mcp-env.template` were plain placeholder swaps.
  `servers.json`'s `url` was a live functional value with no existing
  indirection mechanism to reuse — `env` and `args` secrets already had
  one (`resolve_secrets`/`resolve_arg_secrets` in `installers/mcp.sh`), but
  nothing handled a server's top-level `url` field. Added
  `resolve_url_secrets()` (same `secret:KEY` → `${KEY}` whole-value
  rewrite, same untested-for-non-`env`-fields caveat as `args`).
  **While adding it, found and fixed a real bug**: the early `return 0` in
  `resolve_secrets()` when a config has no `env`-based secrets would have
  skipped `resolve_arg_secrets`/`resolve_url_secrets` entirely — didn't
  bite here only because `azure-devops` always has an `env` secret too, so
  it always happened to fall through. Restructured so the arg/url
  resolvers always run regardless of whether `env` has any.
  **Action needed**: `secret_set MCP_BROWSER_URL "http://<host>:3002/sse"`
  (the actual browser-network host) before `./install.sh --mcp`.
- **Real personal email** `danielpmo@gmail.com`, tracked in
  `docs/plans/open-source-vision-analysis.md` and `workflow_state.md`
  (both were citing what used to be in the untracked `claude.json`) —
  redacted to `<user-email>`.
- **Full name leak**: `config/bash/bash_aliases:6` had
  `/mnt/c/Users/daniel.paiva/...` — real first+last name via a Windows
  path. Genericized to `$USER`.
- **First-name-only path mentions** (`/Users/daniel/...`) across
  `config/claude/skills/archer-verification/SKILL.md` and six
  `docs/learning/`/`docs/plans/` files — genericized to `/Users/you/`.
- **Correction**: `archer-verification` was mischaracterized above as
  "named after a specific client project." It isn't — it's the user's own
  personal side project (a Telegram bot + persistent Claude container
  called archer-pro-active), not a client's. No employer info in it, only
  the path/name exposure just fixed.
- `workflow_state.md`'s own "Private Data Patterns" scan-list ironically
  contained the literal sensitive values it was cataloguing (the email,
  both IPs, the WSL path) — genericized the list itself, and dropped a
  stale note suggesting `danielpmo1371` → `nuvemlabs`, superseded by
  issue 17's decision to host under the personal account.

## Still open

- **The git-history rewrite itself** (see Plan below) — nothing in this
  progress section touches history, only the current tree.
- `router-backups/` — still present, still needs the byte-level check and
  removal from history.
- `secrets/secrets-list-macos` — still needs a look.
- `config/claude/skills/archer-verification/`,
  `config/claude/skills/fetch-azdo-logs/`,
  `config/claude/agents/fetch-azdo-logs.md` — named after / may reference a
  specific client project; not reviewed in this pass.
- Live verification that the keychain-backed values actually work end to
  end (`./install.sh --mcp`, then a real `ado-task` call and an actual
  azure-devops MCP connection) — untestable from this environment.

## Plan

1. Full-history secret/PII sweep (gitleaks with a wider ruleset than the
   current `.gitleaksignore` allows, plus manual review of `router-backups/`
   and `secrets/`) — don't rely on keyword grep alone.
2. Decide per-item: delete outright, or move to a private, non-shared
   location (e.g. an untracked local dir, or a separate private repo).
3. Rewrite history to remove anything that was ever committed
   (`git filter-repo --path ... --invert-paths`), not just the current tree.
4. Rename employer-identifying files/skills to generic equivalents where the
   underlying tool is otherwise reusable (ties into issue 14 Tier 3/4).
5. Force-push the cleaned history — **coordinate first**: this rewrites
   commit SHAs on a repo whose bootstrap script is publicly curl-able
   (`README.md`), so anyone with an existing clone needs to re-clone.

## Order

This blocks: issue 14 (extraction), and any point at which the repo is
actually shared/publicized beyond the current README's public bootstrap URL.
