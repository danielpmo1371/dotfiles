# Pipeline Registry Authoring Guide

- [Location and discovery](#location-and-discovery)
- [Consumers](#consumers)
- [Schema](#schema)
- [How the validator uses `stages` (CD)](#how-the-validator-uses-stages-cd)
- [Caveats](#caveats)
- [Authoring checklist for a new workspace](#authoring-checklist-for-a-new-workspace)

`.claude/pipeline-registry.json` is the per-workspace source of truth for Azure DevOps
pipeline IDs and stage safety lists. It is **hand-authored** (nothing generates it) and
**must be committed** to the workspace repo — it is safety-load-bearing: the validator's
CD stage decisions are driven by its `stages` lists.

## Location and discovery

Place the file at `<workspace-root>/.claude/pipeline-registry.json`. All consumers find
it by walking up parent directories from the current working directory, so it covers
every service repo checked out under the workspace root.

## Consumers

| Consumer | What it reads |
|---|---|
| `~/.claude/scripts/pipeline-registry.sh` | `.organization`, `.services` keys (CWD-based service detection, ID resolution) |
| `~/.claude/scripts/pipeline-validator.sh` | `.services.<name>.stages.allowed/blocked` (CD), `.terraform.*` (terraform), `.cd.id` (service fallback match) |
| `~/.claude/hooks/pipeline-guard.sh` | `.services.<name>.{ci,cd,test,terraform}.id`, `.stages.blocked` |

## Schema

```jsonc
{
  "organization": "my-azdo-org",          // AzDO organization slug
  "services": {
    "my-api": {                           // key = service name; MUST match what
                                          // pipeline-registry.sh detects from CWD
      "project": "My AzDO Project",       // AzDO project name (not the org)
      "ci":   { "id": 380, "name": "my-api-ci" },   // null if no CI pipeline
      "cd":   { "id": 768, "name": "my-api-cd" },   // null if no CD pipeline
      "test": { "id": 812, "name": "my-api-test" }, // optional
      "folder": "my-api",                 // repo directory name under workspace root
      "stages": {
        "all":     ["dryae", "sitae", "uatae", "preae", "prdae"],  // every stage in the CD pipeline
        "allowed": ["dryae", "sitae", "uatae"],                    // stages AI may trigger
        "blocked": ["preae", "prdae"]                              // stages AI must NEVER trigger
      }
    },
    "my-iac": {
      "project": "My AzDO Project",
      "ci": null,
      "cd": null,
      "terraform": {
        "id": 802,
        "name": "My - Terraform",
        "defaultParameters": { "deployToggle": "plan", "TF_LOG": "NONE" },
        "alwaysSkipStages": ["apply_mystack"],       // optional; skipped on every run
        "parameters": {
          "environment": {
            "values":  ["dev", "sit", "uat", "pre", "prd"],
            "allowed": ["dev", "sit", "uat"],
            "blocked": ["pre", "prd"]
          },
          "location": { "values": ["ae", "ase"], "default": "ae" }
        }
      },
      "folder": "my-iac",
      "stages": {
        "all":     ["plan_mystack", "apply_mystack"],
        "allowed": ["plan_mystack"],
        "blocked": ["apply_mystack"]
      }
    }
  }
}
```

Stage names must match the AzDO pipeline stage names **exactly as defined in the
pipeline YAML** (matching is case-insensitive but otherwise exact — no prefixes, no
globs). Enumerate them from the pipeline definition, not from memory.

## How the validator uses `stages` (CD)

Checks run in this order — earlier rules cannot be overridden by later ones:

1. **Hardcoded blocklist first.** Any requested stage containing `pre`, `prd`, `prod`,
   `pre-prod`, or `production` (case-insensitive substring) is blocked. This list lives
   in `pipeline-validator.sh` itself and is never consulted from the registry.
2. **Registry exact match** (when the service has a registry entry with a non-empty
   `stages.allowed`): a stage in `stages.blocked` is blocked; a stage not in
   `stages.allowed` is blocked (default-deny). This is the only layer that can block
   prod stages whose names carry no pre/prd/prod substring (e.g. td-apim's
   `INZ_PaaS_SHARED`) — which is why `blocked` must list them explicitly, and why
   the registry must be authored carefully and kept in version control.
3. **Generic prefix fallback** (no registry, no service entry, or empty
   `stages.allowed`): the stage must start with one of the validator's generic allowed
   prefixes (`dry`, `sit`, `uat`, `npe`, ...). Everything else is blocked.

## Caveats

- **Fallback is silent.** A missing, malformed, or unparseable registry drops the
  validator to the prefix fallback with only a line in
  `~/.claude/logs/pipeline-validator.log`. Fallback still fails closed, but
  service-specific stage names (like `INZ_PaaS_SHARED_SIT`) will be wrongly blocked —
  if an allowed stage is unexpectedly rejected, validate the registry JSON first:
  `jq . .claude/pipeline-registry.json`.
- **Empty `allowed` disables the registry path entirely** for that service, including
  its `blocked` list. Never author an entry with `blocked` populated but `allowed`
  empty; list every triggerable stage explicitly.
- **`stages.all` is documentation** for humans and agents selecting stages; the
  validator decides only from `allowed`/`blocked`.

## Authoring checklist for a new workspace

1. List every pipeline: `az pipelines list --org ... --project ...` or the AzDO UI.
2. For each service: record `ci`/`cd`/`test` IDs and names; use `null` where absent.
3. Enumerate CD stage names from each pipeline's YAML; fill `all`, then split into
   `allowed` (non-prod only) and `blocked` (every pre/prod-like stage, explicitly —
   even though default-deny would catch them, the explicit list documents intent and
   survives future edits to `allowed`).
4. Validate the JSON: `jq . .claude/pipeline-registry.json`.
5. Dry-run the validator from inside the workspace with an allowed and a blocked stage
   and confirm the decisions:
   `echo '{"service":"my-api","type":"cd","branch":"develop","pipelineId":"768","stages":["sitae"]}' | ~/.claude/scripts/pipeline-validator.sh`
6. **Commit the file** to the workspace repo so changes to safety lists are reviewable.
