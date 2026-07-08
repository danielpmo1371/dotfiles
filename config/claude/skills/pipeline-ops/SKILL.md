---
name: pipeline-ops
description: |
  Trigger, monitor, and manage Azure DevOps pipelines safely. Use when user says "deploy", "run pipeline", "trigger build", "run CI", "deploy to sit", "push and deploy", or mentions pipeline operations. Delegates to the pipeline-runner agent for execution. For log analysis only, prefer the fetch-azdo-logs skill.
allowed-tools: Bash, Read, Grep, Glob, Edit, Write
---

# Pipeline Operations

## Role

You manage Azure DevOps pipeline operations with strict safety guardrails. You detect the service, validate the request, trigger pipelines via MCP, monitor progress, and handle failures.

## Quick Start

Trigger a deployment for the current service and branch:

1. Detect service: `~/.claude/scripts/pipeline-registry.sh`
2. Get branch: `git branch --show-current`
3. Validate: `echo '{...}' | ~/.claude/scripts/pipeline-validator.sh`
4. Trigger via MCP: `pipelines_run_pipeline`
5. Monitor: `get_build_status` polling
6. On failure: delegate to `fetch-azdo-logs` agent

## Prerequisites

- `AZDO_PAT` environment variable set
- Project-level `.claude/pipeline-registry.json` in a parent directory — hand-authored and committed to the workspace repo; schema and authoring guide in [REGISTRY.md](REGISTRY.md)
- Azure DevOps MCP server configured
- AZDO pipeline guard hooks installed: `~/.claude/hooks/pipeline-guard.sh` and `~/.claude/hooks/pipeline-trigger-guard.sh` — installed by `installers/claude-azdo-pipeline-hooks.sh` (auto-invoked by `./install.sh --claude`) or directly via `./install.sh --claude-azdo-pipeline-hooks`
- Validator/registry scripts in `~/.claude/scripts/` — delivered by the whole-dir `scripts` symlink from `claude.sh`

## Available Scripts

| Script | Purpose |
|---|---|
| `~/.claude/scripts/pipeline-validator.sh` | Validates requests against safety rules. Input/output JSON via stdin/stdout. |
| `~/.claude/scripts/pipeline-registry.sh` | Detects service from CWD and resolves pipeline IDs. |
| `~/.claude/scripts/fetch-azdo-pipeline-logs.sh` | Fetches pipeline logs for failure analysis. |

## Safety Rules (NON-NEGOTIABLE)

1. **NEVER** trigger pipelines targeting PRE or PRD environments
2. **ALWAYS** validate through `pipeline-validator.sh` before any trigger
3. CI pipelines: allowed on any branch, no stage restrictions
4. CD pipelines: restricted to DRY/SIT/UAT/NPE stages only
5. Maximum ONE auto-fix retry per pipeline run
6. Current git branch by default; explicit branch only if user specifies

## Workflow

### CI (Build) Pipeline

```bash
# 1. Detect
SERVICE_INFO=$(~/.claude/scripts/pipeline-registry.sh)
BRANCH=$(git branch --show-current)

# 2. Extract CI pipeline ID
CI_ID=$(echo "$SERVICE_INFO" | jq -r '.ci.id')
PROJECT=$(echo "$SERVICE_INFO" | jq -r '.project')

# 3. Validate
echo "{\"service\":\"$SERVICE\",\"type\":\"ci\",\"branch\":\"$BRANCH\",\"pipelineId\":\"$CI_ID\",\"project\":\"$PROJECT\"}" | ~/.claude/scripts/pipeline-validator.sh

# 4. If approved, trigger via MCP (use ToolSearch first)
# 5. Monitor via get_build_status polling
```

### CD (Deploy) Pipeline

Same flow but with `type: "cd"` and explicit stages from `stages.allowed`.

## Failure Recovery

When a pipeline fails:
1. Use the `fetch-azdo-logs` agent to analyze
2. Attempt one code fix based on diagnosis
3. If fix applied, re-trigger (once only)
4. If can't fix, report diagnosis and stop

## Service Registry

The workspace-level `.claude/pipeline-registry.json` is the source of truth for pipeline
IDs and stage safety lists — never hardcode or duplicate its values in docs. To list
what's available, query the registry itself (found by walking up from CWD):

```bash
jq -r '.services | to_entries[] | "\(.key)  ci:\(.value.ci.id // "-")  cd:\(.value.cd.id // "-")  \(.value.project)"' \
  <workspace-root>/.claude/pipeline-registry.json
```

Schema, validation semantics, and the authoring guide for new workspaces:
[REGISTRY.md](REGISTRY.md) (installed at `~/.claude/skills/pipeline-ops/REGISTRY.md`).
