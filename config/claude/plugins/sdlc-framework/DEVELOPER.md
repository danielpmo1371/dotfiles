# SDLC Framework — Extension Developer Guide

This guide covers how to extend the SDLC Framework for project-specific needs.

## Architecture Overview

The SDLC Framework uses a three-tier design:

1. **Core Plugin** (`sdlc-framework`) — Universal SDLC orchestration
2. **Project Configuration** (`.sdlc.json`) — Declarative project data
3. **Extension Plugin** (optional) — Behavioral customizations

Most projects only need `.sdlc.json`. Extensions are for complex projects requiring custom auditors, validators, or templates.

## .sdlc.json Schema Reference

Place `.sdlc.json` in your project root. It is version-controlled and declarative (data only, no logic).

### Minimal Configuration

```json
{
  "project": {
    "name": "My Project",
    "abbreviation": "MP",
    "workItemSystem": "azdo",
    "azdo": {
      "organization": "my-org",
      "project": "My Project"
    }
  }
}
```

### Full Schema

```json
{
  "project": {
    "name": "string — Human-readable project name",
    "abbreviation": "string — Short code (e.g., TD, FCH)",
    "workItemSystem": "azdo",
    "azdo": {
      "organization": "string — Azure DevOps organization name",
      "project": "string — Azure DevOps project name",
      "defaultTeam": "string (optional) — Default team for queries",
      "workItemTypes": ["User Story", "Bug", "Task"]
    }
  },

  "repositories": [
    {
      "name": "string — Repository identifier (e.g., td-api)",
      "path": "string — Relative path from project root (e.g., ./td-api)",
      "type": "string — Tech stack: dotnet | node | angular | terraform | bicep",
      "branches": {
        "pattern": "string — Branch naming pattern (e.g., candidate/*)",
        "latest": "string — Current active branch (e.g., candidate/8.12.0)"
      },
      "pipelines": {
        "ci": "number — Azure DevOps CI pipeline definition ID",
        "cd": "number (optional) — CD pipeline definition ID"
      }
    }
  ],

  "environments": ["string — Ordered list of deployment environments"],

  "automation": {
    "pipelineSafety": {
      "allowedEnvironments": ["string — Environments AI can deploy to"],
      "blockedEnvironments": ["string — Environments AI must NEVER deploy to"]
    },
    "worktreePaths": {
      "root": "string — Pattern for story folders (e.g., ./user_story-{id}-{title})",
      "repoPattern": "string — Pattern for repo clones within story folder"
    }
  },

  "phases": {
    "enabled": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
    "optional": [4, 5],
    "complexity": {
      "simple": [1, 6, 7, 8],
      "medium": [1, 2, 6, 7, 8, 9],
      "complex": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    }
  },

  "extensions": {
    "plugin": "string (optional) — Name of extension plugin (e.g., sdlc-td)",
    "auditors": ["string — Custom auditor names"],
    "validators": ["string — Custom validator names"],
    "templates": ["string — Custom template names"]
  }
}
```

### Field Details

| Field | Required | Description |
|-------|----------|-------------|
| `project.name` | Yes | Displayed in reports and status |
| `project.azdo.organization` | Yes | Used for AZDO MCP calls |
| `project.azdo.project` | Yes | Used for work item and pipeline queries |
| `repositories` | No | Auto-detected from CWD if absent |
| `environments` | No | Defaults to `["dev", "sit", "uat", "pre", "prd"]` |
| `automation.pipelineSafety` | No | Defaults: allow `dev/sit/uat`, block `pre/prd` |
| `phases.complexity` | No | Defaults to all 10 phases for all tiers |
| `extensions.plugin` | No | Only needed if using an extension plugin |

## Creating Project Extensions

When `.sdlc.json` alone is not enough, create an extension plugin.

### Directory Structure

```
<project>/.claude/plugins/sdlc-<project>/
  plugin.json          # Manifest with extends field
  auditors/            # Custom audit scripts
    nuget-consolidation.sh
    functions-worker-validator.sh
  validators/          # Custom validation scripts
    candidate-branch-checker.sh
  templates/           # Custom report/plan templates
    plan-template.md
    report-template.md
```

### Extension plugin.json

```json
{
  "name": "sdlc-td",
  "version": "1.0.0",
  "description": "TD project extensions for SDLC Framework",
  "extends": "sdlc-framework",
  "components": {
    "auditors": [
      "nuget-consolidation",
      "functions-worker-validator"
    ],
    "validators": [
      "candidate-branch-checker"
    ],
    "templates": [
      "plan-template",
      "report-template"
    ]
  }
}
```

### Custom Auditors

Auditors run during Phase 3 (Audit). Each auditor is a shell script that:
- Receives the repository path as `$1`
- Outputs findings to stdout in a structured format
- Exits with code 0 (pass), 1 (warnings), or 2 (critical findings)

**Example: `auditors/nuget-consolidation.sh`**

```bash
#!/usr/bin/env bash
# Check for NuGet package version inconsistencies across projects
REPO_PATH="${1:-.}"

echo "## NuGet Consolidation Check"
echo ""

# Find all .csproj files and extract package references
duplicates=$(find "$REPO_PATH" -name "*.csproj" -exec grep -h "PackageReference" {} \; \
  | sort | uniq -c | sort -rn | awk '$1 > 1')

if [[ -n "$duplicates" ]]; then
  echo "**WARN**: Inconsistent package versions found:"
  echo "$duplicates"
  exit 1
else
  echo "All NuGet packages are consolidated."
  exit 0
fi
```

### Custom Validators

Validators run at phase transitions. They verify that preconditions are met before advancing.

**Example: `validators/candidate-branch-checker.sh`**

```bash
#!/usr/bin/env bash
# Verify work is on a candidate/* branch
REPO_PATH="${1:-.}"
BRANCH=$(cd "$REPO_PATH" && git branch --show-current 2>/dev/null)

if [[ "$BRANCH" == candidate/* ]]; then
  echo "OK: On candidate branch $BRANCH"
  exit 0
else
  echo "FAIL: Expected candidate/* branch, found: $BRANCH"
  exit 1
fi
```

### Custom Templates

Templates provide project-specific formatting for plans, reports, and other deliverables. They are markdown files with `{placeholder}` tokens that the framework replaces at runtime.

**Available placeholders:**
- `{work_item_id}`, `{title}`, `{timestamp}`
- `{phase_name}`, `{phase_number}`
- `{repository_list}`, `{environment}`
- `{findings}`, `{decisions}`, `{blockers}`

## Integration Points per Phase

| Phase | Extension Hook | Description |
|-------|---------------|-------------|
| 1. Bootstrap | — | No extension hooks (core handles AZDO fetch) |
| 2. Scope Discovery | — | Repo list from `.sdlc.json` repositories |
| 3. Audit | `auditors/*` | Custom audit scripts run after generic scans |
| 4. Scope Refinement | — | Extension findings feed into refinement |
| 5. Reporting | `templates/*` | Custom report templates |
| 6. Planning | `templates/*` | Custom plan templates with project conventions |
| 7. Execution | `validators/*` | Pre-execution validators (branch checks, etc.) |
| 8. Verification | `validators/*` | Post-execution validators (test thresholds, etc.) |
| 9. PR/Delivery | `templates/*` | Custom PR description templates |
| 10. Retrospective | — | Uses core retrospective format |

## Testing Extensions

### Manual Testing

1. Run the setup checker:
   ```bash
   bash ~/.claude/plugins/sdlc-framework/scripts/setup.sh
   ```

2. Test individual auditors:
   ```bash
   bash .claude/plugins/sdlc-td/auditors/nuget-consolidation.sh ./td-api
   ```

3. Test validators:
   ```bash
   bash .claude/plugins/sdlc-td/validators/candidate-branch-checker.sh ./td-api
   ```

### Integration Testing

Start a workflow with `/sdlc-start <test-work-item>` in guided mode. Verify:
- Extension auditors run during Phase 3
- Extension validators run at phase transitions
- Extension templates are used for reports and plans
- Graceful fallback when extension components are missing

## Graceful Degradation

The framework handles missing extensions gracefully:
- Missing auditors: skipped with a warning in the audit report
- Missing validators: skipped, phase advances with a note
- Missing templates: falls back to core framework defaults
- Missing `.sdlc.json`: uses generic defaults, auto-detects what it can

This ensures the core framework works for any project, even without configuration.
