---
description: Trigger CI/CD pipelines for the current service. Auto-detects service from CWD, uses current git branch. Monitors, diagnoses failures, attempts one auto-fix.
allowed-tools: Bash(*), Read(*), Grep(*), Glob(*)
---

## Pipeline Deploy: $ARGUMENTS

### Step 1: Detect Service and Branch

Detect the current service and branch:

```bash
# Detect service from CWD (or use first argument if it looks like a service name)
SERVICE_INFO=$(~/.claude/scripts/pipeline-registry.sh 2>&1) || true

# Get current branch
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
```

Parse `$ARGUMENTS`:
- If arguments contain a branch name (contains `/` or starts with `feature/`, `release/`, `hotfix/`, `develop`, `main`): use it as branch override
- If arguments contain a service name (matches a known service): use it as service override
- If arguments contain `--ci-only`: skip CD pipeline
- If arguments contain `--skip-ci`: skip CI, go directly to CD
- Otherwise: use auto-detected service and current branch

Display what was detected and ask user to confirm before proceeding.

### Step 2: Resolve Pipeline IDs

From the service info JSON, extract:
- `ci.id` — CI pipeline definition ID
- `cd.id` — CD pipeline definition ID (may be null)
- `project` — AzDO project name
- `stages.allowed` — allowed deployment stages

If no CI or CD pipeline exists for the service, inform the user.

### Step 3: Validate and Trigger CI

Run the validator:
```bash
echo '{"service":"SERVICE","type":"ci","branch":"BRANCH","pipelineId":"CI_ID","project":"PROJECT"}' | ~/.claude/scripts/pipeline-validator.sh
```

If approved, use `ToolSearch` to load `mcp__azure-devops__pipelines_run_pipeline`, then trigger:
- `project`: from registry
- `pipelineId`: CI pipeline ID
- `resources.repositories.self.refName`: `refs/heads/BRANCH`

### Step 4: Monitor CI

Use `ToolSearch` to load `mcp__azure-devops__pipelines_get_build_status`.

Poll every 30 seconds:
1. Call `mcp__azure-devops__pipelines_get_builds` filtered by the CI definition ID, top 1, to get the latest buildId
2. Call `mcp__azure-devops__pipelines_get_build_status` with the buildId
3. Report status to user (in progress / succeeded / failed)
4. Continue until completed

### Step 5: Handle CI Failure

If CI fails:
1. Use the `fetch-azdo-logs` agent (Task tool, subagent_type=fetch-azdo-logs) to fetch and analyze logs
2. Based on the diagnosis, attempt one auto-fix:
   - Read the identified failing file
   - Apply the suggested fix
   - Commit the fix
   - Re-trigger CI (back to Step 3, but only ONCE)
3. If the retry also fails, or the fix agent can't determine a fix:
   - Report the full diagnosis to the user
   - Provide the pipeline URL for manual investigation
   - STOP

### Step 6: Trigger CD (if applicable)

If CI passed and a CD pipeline exists (`cd.id` is not null), and `--ci-only` was NOT specified:

1. Ask user which stages to deploy to (from `stages.allowed` list)
2. Run validator with type=cd and selected stages
3. If approved, trigger CD via MCP with `stagesToSkip` for non-selected stages
4. Monitor CD the same way as CI (Step 4)

### Step 7: Handle CD Failure

Same as Step 5 but for CD pipeline. One auto-fix attempt, then report.

### Step 8: Summary

Report:
- Service deployed
- Branch
- CI result (pass/fail, build number, duration)
- CD result (pass/fail, build number, stages deployed)
- Any fixes applied
- Pipeline URLs for reference

### Safety Rules (NON-NEGOTIABLE)

- **NEVER** trigger pipelines targeting PRE or PRD environments
- **ALWAYS** run through pipeline-validator.sh before any MCP call
- **ALWAYS** use the current branch unless explicitly overridden
- **MAXIMUM ONE** auto-fix retry per pipeline run
- **CD requires explicit stage selection** from the allowed list
