---
name: pipeline-ops
description: |
  Trigger, monitor, and manage Azure DevOps pipelines safely. Use when user says "deploy", "run pipeline", "trigger build", "run CI", "deploy to sit", "push and deploy", or mentions pipeline operations. Delegates to the pipeline-runner agent for execution. For log analysis only, prefer the fetch-azdo-logs skill.
allowed-tools: Agent, Bash, Read, Grep, Glob
---

# Pipeline Operations

Router only. The workflow, decision rules, safety rules and report format live in one place: the `pipeline-runner` agent (`~/.claude/agents/pipeline-runner.md`). Do not restate them here.

## When this triggers

"deploy", "run pipeline", "trigger build", "run CI", "deploy to sit", "push and deploy", or any request to start, re-run or watch an Azure DevOps pipeline.

## What to do

- Trigger, monitor or deploy: dispatch `Agent` with `subagent_type: pipeline-runner`, passing whatever the user named (service, environment, stages, branch) plus "apply the decision rules; do not ask". `/pipe-deploy` does the same from the command line.
- Analyse an existing build's logs only: `Agent` with `subagent_type: fetch-azdo-logs`, or the `fetch-azdo-logs` skill for a manual walk-through.
- Author a registry, or a stage is wrongly blocked: [REGISTRY.md](REGISTRY.md) (installed at `~/.claude/skills/pipeline-ops/REGISTRY.md`).

## Prerequisites

- `AZDO_PAT` in the environment (`secrets-doctor AZDO_PAT` when a 401 shows up)
- Azure DevOps MCP server configured (>= 2.10, action-based `pipelines_*` tools)
- `<workspace-root>/.claude/pipeline-registry.json`, hand-authored and committed; found by walking up from CWD
- Guard hooks `~/.claude/hooks/pipeline-guard.sh` and `pipeline-trigger-guard.sh`: `./install.sh --claude` or `./install.sh --claude-azdo-pipeline-hooks`
- `~/.claude/scripts/pipeline-validator.sh` and `pipeline-registry.sh`: the whole-dir `scripts` symlink from `installers/claude.sh`
