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

Tree-level org/project cleanup done in two follow-up PRs (#4, and the one
that removed `azsetmbdev`/`azsetmbsit`, ado-task's `NZTD BAU` default,
`config/mcp/servers.json`'s org URL + default project). Three keychain
values now required for previous functionality to keep working:
`secret_set AZDO_ORG "<org-slug>"`, `secret_set AZDO_ORG_URL
"https://dev.azure.com/<org>"`, `secret_set AZDO_PROJECT "<project>"`
(`AZDO_PAT` already existed).

**Deliberately not touched, needs a decision:**
- `config/mcp/servers.json`'s `azure-devops` server still has the org name
  as a positional CLI arg (`args: [..., "mbie-immigrationnz-prod", ...]`).
  `installers/mcp.sh`'s `resolve_secrets()` only rewrites `env` block
  values, not `args` — genericizing this safely needs either extending
  that function or the templating layer already scoped in
  `docs/plans/open-source-architecture-plan.md` (Phase 2). Untested
  guesses here risk silently breaking the live MCP connection.
- The AZDO pipeline safety system (`config/claude/hooks/pipeline-guard.sh`,
  `scripts/pipeline-{registry,validator}.sh`, `skills/pipeline-ops/`,
  `agents/pipeline-runner.md`, `commands/pipe-deploy.md`,
  `tests/test-pipeline-hooks.sh`, plus the `sdlc-framework` plugin) still
  hardcodes pipeline id `802`, project `Travel Declaration`, stage name
  `apply_travellerdirectives`, and service `td-iac`/`td-api` across ~10
  files. This is the same blocker issue 14 Tier 1 item 3 already
  identifies ("must become registry-driven config") — it's not cosmetic,
  `802`/`apply_travellerdirectives` are the literal match conditions the
  guard uses to block an unreviewed terraform destroy/apply. A careless
  parameterization (e.g. a constant going unset) risks the guard failing
  open instead of closed. Needs the registry-driven refactor as a
  deliberate piece of work, not a find-replace pass.
- `docs/plans/*.md`, `docs/learning/*.md`, `workflow_state.md` still
  narrate the org/project by name, including a document that describes a
  real PAT-in-public-repo incident. Redacting historical incident write-ups
  is an editorial call, not addressed here.

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
