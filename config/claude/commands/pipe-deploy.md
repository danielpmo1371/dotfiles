---
description: Trigger CI/CD pipelines for the current service. Auto-detects service from CWD, uses current git branch. Monitors, diagnoses failures, attempts one auto-fix.
allowed-tools: Agent, Bash, Read, Grep, Glob
---

## Pipeline Deploy: $ARGUMENTS

Thin wrapper. The workflow (decision rules, validation, trigger, monitoring, one auto-fix, audit line, report) lives in the `pipeline-runner` agent; do not restate its steps here and never put a question to the user.

Parse `$ARGUMENTS` (all optional, any order):
- service: a word matching a registry service name (`~/.claude/scripts/pipeline-registry.sh <name>` resolves it)
- environment: `dev`, `sit` or `uat` (never `pre`/`prd`)
- stages: comma-separated CD stage names
- branch: contains `/`, or is `develop` / `main`
- `--ci-only`: run CI without CD

Anything not given is left to the agent's decision rules.

Dispatch `Agent` with `subagent_type: pipeline-runner` and this prompt:

> Deploy. Service: {service or "detect from CWD"}. Environment: {env or "default"}. Stages: {stages or "default"}. Branch: {branch or "current"}. Flags: {flags or "none"}. Apply the decision rules; do not ask. Record the D<n> decision line and include it, the Logs Verified line and the build links in your report.

Relay the agent's report to the user unchanged.
