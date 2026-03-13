# SDLC Framework

Comprehensive SDLC orchestration for Claude Code - from story bootstrap through retrospective.

## Overview

The SDLC Framework provides intelligent, autonomous software development lifecycle management with:

- **Team Lead (Opus)** - Orchestrates workflow, spawns specialists, makes smart stopping decisions
- **8 Specialist Agents** - Bootstrap, Scope, Audit, Planning, Engineer, QA, Reporter, Retrospective
- **Phase Management** - 10 phases with complexity-based selection (simple/medium/complex)
- **State Tracking** - Dual-source (workflow_state.md + Memory MCP) with cross-session persistence
- **Graceful Degradation** - Works with or without optional plugins

## Quick Start

```bash
# Start work on a user story
/sdlc start US#170514

# Choose mode: Autonomous (AI-driven) or Guided (step approval)
# Framework handles bootstrap → planning → execution → delivery

# Resume work after break
/sdlc resume US#170514

# Check status
/sdlc status
```

## Prerequisites

**Required Plugins:**
- superpowers (>=4.3.0)
- feature-dev
- pr-review-toolkit

**Recommended Plugins:**
- pipeline-ops (Azure DevOps pipeline operations)
- code-review-suite (Pre-commit validation)
- session-reporting (Session documentation)
- memory-management (Persistent memory)
- learning-tools (Post-mortem analysis)

**Installation:**

```bash
# Run dependency checker
~/.claude/plugins/sdlc-framework/scripts/setup.sh
```

## Project Configuration

Create `.sdlc.json` in your project root:

```json
{
  "project": {
    "name": "My Project",
    "workItemSystem": "azdo",
    "azdo": {
      "organization": "my-org",
      "project": "My Project"
    }
  },
  "repositories": [
    {
      "name": "my-api",
      "path": "./my-api",
      "type": "dotnet",
      "branches": {
        "pattern": "feature/*"
      }
    }
  ],
  "environments": ["dev", "test", "prod"]
}
```

## How It Works

1. **Bootstrap** - Pull work item from AZDO, create folder structure
2. **Scope Discovery** - Analyze affected repos, dependencies
3. **Audit** - Run security/dependency scans
4. **Scope Refinement** - Align with stakeholders (if needed)
5. **Reporting** - Generate stakeholder reports (if needed)
6. **Planning** - Create detailed execution plan
7. **Execution** - Implement changes in isolated worktrees
8. **Verification** - Run builds and tests
9. **PR/Delivery** - Create PRs, handle reviews
10. **Retrospective** - Extract lessons, update memory

**Complexity Tiers:**
- **Simple** (1-file fix): Phases 1, 6, 7, 8 only
- **Medium** (feature): Phases 1, 2, 6, 7, 8, 9
- **Complex** (multi-repo): All 10 phases

## Autonomous vs Guided Mode

**Autonomous:**
- AI auto-advances through phases
- Stops only at critical decision points
- Best for routine work

**Guided:**
- User approves each phase transition
- Full visibility and control
- Best for unfamiliar work

## Extending the Framework

See [DEVELOPER.md](DEVELOPER.md) for creating project-specific extensions.

## Documentation

- Design: `~/repos/td/docs/plans/2026-03-13-sdlc-framework-design.md`
- Implementation Plan: `~/repos/td/docs/superpowers/plans/2026-03-13-sdlc-framework-core.md`

## License

MIT
