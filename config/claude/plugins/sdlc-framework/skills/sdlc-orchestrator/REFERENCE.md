# SDLC Orchestrator Reference

## 10-Phase Sequence

```
1. Bootstrap -> 2. Scope Discovery -> 3. Audit -> 4. Scope Refinement ->
5. Reporting -> 6. Planning -> 7. Execution -> 8. Verification ->
9. PR/Delivery -> 10. Retrospective
```

### Phase Details

| # | Phase | Specialist Agent | Model | Est. Duration | Description |
|---|---|---|---|---|---|
| 1 | Bootstrap | `sdlc-bootstrap-specialist` | Sonnet | 5-10 min | Fetch work item from AZDO, create folder scaffold, initialize workflow state |
| 2 | Scope Discovery | `sdlc-scope-analyst` | Sonnet | 10-20 min | Identify affected repos, map dependencies, assess blast radius |
| 3 | Audit | `sdlc-audit-specialist` | Sonnet | 15-30 min | Run package audits, security scans, code quality checks on affected areas |
| 4 | Scope Refinement | `sdlc-scope-analyst` | Sonnet | 10-15 min | Refine scope based on audit findings, adjust estimates, flag new risks |
| 5 | Reporting | `sdlc-reporter` | Sonnet | 5-10 min | Generate stakeholder report summarizing phases 1-4 findings |
| 6 | Planning | `sdlc-planning-architect` | Opus | 10-20 min | Design solution architecture, create execution plan with steps |
| 7 | Execution | `sdlc-implementation-engineer` | Sonnet | 30-120 min | Implement changes per approved plan, commit incrementally |
| 8 | Verification | `sdlc-qa-specialist` | Sonnet | 10-30 min | Run tests, verify acceptance criteria, confirm no regressions |
| 9 | PR/Delivery | `sdlc-reporter` | Sonnet | 10-15 min | Create PR with description, run pre-commit hooks, prepare for review |
| 10 | Retrospective | `sdlc-retrospective-analyst` | Sonnet | 5-10 min | Extract lessons learned, update memory, write retrospective |

## Specialist Agents

### Team Lead (Orchestrator)
- **Model:** Opus (always)
- **Tools:** All
- **Role:** Phase progression, spawn specialists, coordinate, smart stopping, aggregate results
- **Does not delegate to other agents** — coordinates them

### Bootstrap Specialist
- **Model:** Sonnet
- **Tools:** Read, Bash, Write, Glob, Grep
- **Role:** Pull AZDO work item, extract context, create folder structure, initialize workflow_state.md
- **Delegates to:** AZDO MCP, Memory MCP

### Scope Analyst
- **Model:** Sonnet (Opus for >5 repos)
- **Tools:** Read, Grep, Glob, Bash
- **Role:** Identify affected repos, map dependencies, analyze blast radius, detect complexity
- **Delegates to:** `feature-dev:code-explorer` per repo (parallel)

### Audit Specialist
- **Model:** Sonnet (Opus for security-critical)
- **Tools:** Read, Bash, Write
- **Role:** Run domain scans, collect results, summarize with severity, flag for review
- **Delegates to:** `dotnet list package`, `npm audit`, project-specific auditors from extensions

### Planning Architect
- **Model:** Opus (always)
- **Tools:** Read, Write, Grep, Glob
- **Role:** Design solution, create execution plan, identify trade-offs, estimate complexity
- **Delegates to:** `superpowers:brainstorming`, `feature-dev:code-architect`, `superpowers:writing-plans`

### Implementation Engineer
- **Model:** Sonnet (Opus for refactoring)
- **Tools:** All
- **Role:** Execute plan, create worktrees, make changes, run builds, commit incrementally
- **Delegates to:** `superpowers:using-git-worktrees`, `superpowers:test-driven-development`, `superpowers:executing-plans`

### QA Specialist
- **Model:** Sonnet (Opus for test strategy)
- **Tools:** Read, Bash, Write
- **Role:** Run builds/tests, verify acceptance criteria, check regressions, flag failures
- **Delegates to:** `superpowers:verification-before-completion`, `superpowers:systematic-debugging`

### Reporter
- **Model:** Sonnet
- **Tools:** Read, Write
- **Role:** Generate stakeholder reports, create summaries, update work items
- **Delegates to:** Memory MCP, AZDO MCP, optional `session-reporting`

### Retrospective Analyst
- **Model:** Sonnet (Opus for critical incidents)
- **Tools:** Read, Write
- **Role:** Extract lessons, identify improvements, update memory, write retrospective
- **Delegates to:** optional `learning-tools:learn-from-mistake`, Memory MCP

## Complexity Tiers

Complexity is assessed from scope analysis results (Phase 2). The `phase-intelligence.js` library handles the logic.

### Assessment Criteria

| Factor | Simple | Medium | Complex |
|---|---|---|---|
| Affected files | <=3 | 4-10 | >10 |
| Affected repos | <=1 | 2-3 | >3 |
| Architectural changes | No | No | Yes |
| Security implications | No | Possible | Yes |
| Database changes | No | No | Yes (with security) |

### Phase Selection by Tier

| Tier | Phases | Typical Duration |
|---|---|---|
| **Simple** | 1, 6, 7, 8 | 45-60 min |
| **Medium** | 1, 2, 6, 7, 8, 9 | 1.5-3 hrs |
| **Complex** | 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 | 3-6 hrs |

Custom phase selection can be configured in `.sdlc.json` under `phases.complexity`.

## Smart Stopping Logic

### Autonomous Mode — Stop Conditions

The Team Lead auto-advances unless these conditions are met:

| Phase | Stop When |
|---|---|
| 1 (Bootstrap) | Requirements unclear, conflicting stakeholders, missing AC |
| 2 (Scope) | Blast radius >10 files, >5 repos affected, unfamiliar subsystems |
| 3 (Audit) | Any CRITICAL/HIGH findings, >50 total issues |
| 4 (Refinement) | Architectural trade-offs requiring stakeholder input, scope grew significantly |
| 6 (Planning) | Multiple valid approaches with trade-offs, HIGH risk items |
| 7 (Execution) | Build failures, test failures, merge conflicts |
| 8 (Verification) | Any verification failures |
| 9 (PR/Delivery) | Pre-commit hook failures, review feedback |
| 10 (Retrospective) | Critical incidents detected during workflow |

### Guided Mode

In Guided mode, the Team Lead stops at **every phase boundary** and presents:
- Phase summary (what was done)
- Key findings or outputs
- Recommendation for next phase
- Option to adjust, skip, or re-run

## State Management

### Dual-Source Strategy

**workflow_state.md** (file-based, human-readable):
- Located at `user_story-{id}-*/workflow_state.md`
- Tracks phases, decisions, specialist activity, blockers
- Updated every phase completion and every decision

**Memory MCP** (persistent, machine-queryable):
- Tags: `sdlc:US#{id}:scope`, `sdlc:US#{id}:decision:{topic}`, etc.
- Cross-session recall and staleness detection

### Resume Synchronization

When resuming a workflow:
1. Read `workflow_state.md`
2. Query Memory MCP for `sdlc:US#{id}:*`
3. Cross-check: file newer -> trust file; memory newer -> trust memory; conflict -> ask user
4. Restore state and continue from last completed phase

## User Story Folder Structure

```
user_story-{id}-{SanitizedTitle}/
  workflow_state.md
  01-bootstrap/
    story-context.md
  02-scope-discovery/
    scope-analysis.md
  03-audit/
    audit-summary.md
    per-repo/
  04-scope-refinement/
  05-reporting/
    status-report.md
  06-planning/
    execution-plan.md
  07-execution/
    execution-log.md
    {repo-worktrees}/
  08-verification/
    verification-report.md
  09-pr-delivery/
    pr-description.md
  10-retrospective/
    retrospective.md
```

## Extension System

### Project Configuration (.sdlc.json)

Place `.sdlc.json` in the project root for declarative project data:

```json
{
  "project": {
    "name": "My Project",
    "workItemSystem": "azdo",
    "azdo": { "organization": "my-org", "project": "My Project" }
  },
  "repositories": [
    { "name": "my-api", "path": "./my-api", "type": "dotnet",
      "pipelines": { "ci": 123, "cd": 456 } }
  ],
  "environments": ["dev", "sit", "uat", "pre", "prd"],
  "automation": {
    "pipelineSafety": { "allowedEnvironments": ["dev", "sit", "uat"] }
  },
  "phases": {
    "complexity": {
      "simple": [1, 6, 7, 8],
      "medium": [1, 2, 6, 7, 8, 9],
      "complex": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    }
  }
}
```

### Extension Plugins

For projects that need behavioral customizations beyond config:

1. Create `<project>/.claude/plugins/sdlc-<project>/`
2. Add `plugin.json` with `extends: "sdlc-framework"`
3. Add domain-specific auditors, validators, templates
4. Reference in `.sdlc.json` under `extensions.plugin`

Extensions can provide:
- Custom auditors (NuGet consolidation, Functions worker validation)
- Custom validators (branch naming, pipeline safety overrides)
- Templates (PR description, report format)
- Phase hooks (pre/post phase actions)

## Troubleshooting

### "AZDO MCP unavailable"
Check that the Azure DevOps MCP server is configured and running. Verify `AZDO_PAT` environment variable is set.

### "Work item not found"
Verify the work item ID is correct and your PAT has access to the project.

### "Missing required plugins"
Install the required plugins: `superpowers`, `feature-dev`, `pr-review-toolkit`. Check with the plugin manager.

### "Phase stuck / not advancing"
Check `workflow_state.md` for blockers. In Autonomous mode, a stop means a critical issue was found. Review the phase output and resolve the issue.

### "State conflict between file and memory"
This happens when one source was updated without the other (e.g., manual file edit). The orchestrator will ask you to choose which source to trust.

### "Extension not loading"
Verify `.sdlc.json` has the correct `extensions.plugin` value and the extension plugin directory exists with a valid `plugin.json`.
