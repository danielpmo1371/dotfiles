const VALID_COMPLEXITIES = ['simple', 'medium', 'complex'];
const MIN_PHASE = 1;
const MAX_PHASE = 10;
const VALID_MODES = ['autonomous', 'guided'];

const REQUIRED_SCOPE_FIELDS = [
  'affectedFiles',
  'affectedRepos',
  'hasArchitecturalChanges',
  'hasSecurityImplications',
  'hasDatabaseChanges',
  'hasApiChanges'
];

const DEFAULT_PHASES = {
  simple: [1, 6, 7, 8],
  medium: [1, 2, 6, 7, 8, 9],
  complex: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
};

const PHASE_DESCRIPTIONS = {
  1:  { name: 'Bootstrap',        specialist: 'Bootstrap Specialist',      estimatedDuration: '5-10 min',  description: 'Parse work item, extract requirements, identify acceptance criteria, and establish task context.' },
  2:  { name: 'Scope Discovery',  specialist: 'Scope Analyst',             estimatedDuration: '10-20 min', description: 'Analyze codebase impact, identify affected files and repos, map dependencies and subsystems.' },
  3:  { name: 'Audit',            specialist: 'Audit Specialist',          estimatedDuration: '15-30 min', description: 'Review existing code quality, security posture, test coverage, and technical debt in affected areas.' },
  4:  { name: 'Scope Refinement', specialist: 'Scope Analyst',             estimatedDuration: '10-15 min', description: 'Refine scope based on audit findings, adjust estimates, and flag newly discovered risks.' },
  5:  { name: 'Reporting',        specialist: 'Reporter',                  estimatedDuration: '5-10 min',  description: 'Generate comprehensive analysis report for stakeholder review and decision-making.' },
  6:  { name: 'Planning',         specialist: 'Planning Architect',        estimatedDuration: '10-20 min', description: 'Design implementation approach, create execution plan, identify risks and mitigation strategies.' },
  7:  { name: 'Execution',        specialist: 'Implementation Engineer',   estimatedDuration: '30-120 min', description: 'Implement changes according to the approved plan, writing code and tests.' },
  8:  { name: 'Verification',     specialist: 'QA Specialist',             estimatedDuration: '10-30 min', description: 'Run tests, verify acceptance criteria, validate build integrity, and confirm no regressions.' },
  9:  { name: 'PR/Delivery',      specialist: 'Implementation Engineer',   estimatedDuration: '10-15 min', description: 'Create pull request, run pre-commit hooks, prepare for code review and delivery.' },
  10: { name: 'Retrospective',    specialist: 'Retrospective Analyst',     estimatedDuration: '5-10 min',  description: 'Capture lessons learned, update documentation, store patterns for future reference.' }
};

class PhaseIntelligence {
  assessComplexity(scope) {
    if (!scope || typeof scope !== 'object') {
      throw new Error('scope is required and must be an object');
    }

    for (const field of REQUIRED_SCOPE_FIELDS) {
      if (scope[field] === undefined) {
        throw new Error(`affectedFiles, affectedRepos, hasArchitecturalChanges, hasSecurityImplications, hasDatabaseChanges, hasApiChanges are all required fields in scope`);
      }
    }

    const { affectedFiles, affectedRepos, hasArchitecturalChanges, hasSecurityImplications, hasDatabaseChanges } = scope;

    // Check complex conditions first (most restrictive)
    if (
      affectedFiles > 10 ||
      affectedRepos > 3 ||
      hasArchitecturalChanges ||
      (hasSecurityImplications && hasDatabaseChanges)
    ) {
      return 'complex';
    }

    // Check simple conditions
    if (
      affectedFiles <= 3 &&
      affectedRepos <= 1 &&
      !hasArchitecturalChanges &&
      !hasSecurityImplications &&
      !hasDatabaseChanges
    ) {
      return 'simple';
    }

    return 'medium';
  }

  selectPhases(complexity, customConfig) {
    if (!complexity || typeof complexity !== 'string') {
      throw new Error('complexity is required and must be a string');
    }

    if (!VALID_COMPLEXITIES.includes(complexity)) {
      throw new Error(`Invalid complexity: "${complexity}". Must be one of: ${VALID_COMPLEXITIES.join(', ')}`);
    }

    if (customConfig) {
      if (!Array.isArray(customConfig.phases)) {
        throw new Error('phases must be an array in customConfig');
      }

      for (const phase of customConfig.phases) {
        if (typeof phase !== 'number' || phase < MIN_PHASE || phase > MAX_PHASE) {
          throw new Error(`Invalid phase number: ${phase}. Must be between ${MIN_PHASE} and ${MAX_PHASE}`);
        }
      }

      return [...customConfig.phases];
    }

    return [...DEFAULT_PHASES[complexity]];
  }

  shouldStop(phase, results, mode) {
    if (phase === undefined || phase === null) {
      throw new Error('phase is required');
    }

    if (!results || typeof results !== 'object') {
      throw new Error('results is required and must be an object');
    }

    if (mode === undefined) {
      mode = 'autonomous';
    }

    if (!VALID_MODES.includes(mode)) {
      throw new Error(`Invalid mode: "${mode}". Must be one of: ${VALID_MODES.join(', ')}`);
    }

    // Guided mode: always stop
    if (mode === 'guided') {
      return { stop: true, reason: 'Phase boundary reached in guided mode', severity: 'info' };
    }

    // Autonomous mode: check phase-specific conditions
    return this._checkAutonomousStop(phase, results);
  }

  getPhaseDescription(phaseNum) {
    if (typeof phaseNum !== 'number' || phaseNum < MIN_PHASE || phaseNum > MAX_PHASE) {
      throw new Error(`Invalid phase number: ${phaseNum}. Must be between ${MIN_PHASE} and ${MAX_PHASE}`);
    }

    return { ...PHASE_DESCRIPTIONS[phaseNum] };
  }

  getNextPhase(currentPhase, selectedPhases) {
    if (currentPhase === undefined || currentPhase === null) {
      throw new Error('currentPhase is required');
    }

    if (!selectedPhases || !Array.isArray(selectedPhases)) {
      throw new Error('selectedPhases is required and must be an array');
    }

    const next = selectedPhases.find(p => p > currentPhase);
    return next !== undefined ? next : null;
  }

  _checkAutonomousStop(phase, results) {
    const noStop = { stop: false, reason: null, severity: 'info' };

    switch (phase) {
      case 1: {
        if (results.requirementsUnclear) {
          return { stop: true, reason: 'Requirements are unclear and need clarification', severity: 'warning' };
        }
        if (results.conflictingStakeholders) {
          return { stop: true, reason: 'Conflicting stakeholder requirements detected', severity: 'warning' };
        }
        if (results.missingAC) {
          return { stop: true, reason: 'Missing acceptance criteria', severity: 'warning' };
        }
        return noStop;
      }

      case 2: {
        if (results.affectedFiles > 10) {
          return { stop: true, reason: `Large scope: ${results.affectedFiles} files affected`, severity: 'warning' };
        }
        if (results.affectedRepos > 5) {
          return { stop: true, reason: `Cross-repo impact: ${results.affectedRepos} repos affected`, severity: 'warning' };
        }
        if (results.unfamiliarSubsystems) {
          return { stop: true, reason: 'Unfamiliar subsystems detected in scope', severity: 'warning' };
        }
        return noStop;
      }

      case 3: {
        if (results.criticalFindings > 0) {
          return { stop: true, reason: `${results.criticalFindings} critical finding(s) in audit`, severity: 'critical' };
        }
        if (results.highFindings > 0) {
          return { stop: true, reason: `${results.highFindings} high-severity finding(s) in audit`, severity: 'critical' };
        }
        if (results.totalIssues > 50) {
          return { stop: true, reason: `High issue count: ${results.totalIssues} total issues`, severity: 'warning' };
        }
        return noStop;
      }

      case 6: {
        if (results.multipleApproaches) {
          return { stop: true, reason: 'Multiple implementation approaches identified — user decision needed', severity: 'warning' };
        }
        if (results.highRiskItems > 0) {
          return { stop: true, reason: `${results.highRiskItems} high-risk item(s) in plan`, severity: 'critical' };
        }
        return noStop;
      }

      case 7: {
        if (results.buildFailures > 0) {
          return { stop: true, reason: `${results.buildFailures} build failure(s)`, severity: 'critical' };
        }
        if (results.testFailures > 0) {
          return { stop: true, reason: `${results.testFailures} test failure(s)`, severity: 'critical' };
        }
        if (results.mergeConflicts) {
          return { stop: true, reason: 'Merge conflicts detected', severity: 'critical' };
        }
        return noStop;
      }

      case 8: {
        if (results.anyFailures) {
          return { stop: true, reason: 'Verification failures detected', severity: 'critical' };
        }
        return noStop;
      }

      case 9: {
        if (results.hookFailures) {
          return { stop: true, reason: 'Pre-commit hook failures detected', severity: 'warning' };
        }
        if (results.reviewFeedback) {
          return { stop: true, reason: 'Review feedback requires attention', severity: 'warning' };
        }
        return noStop;
      }

      default:
        return noStop;
    }
  }
}

module.exports = PhaseIntelligence;
