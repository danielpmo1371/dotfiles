const assert = require('assert');
const PhaseIntelligence = require('../lib/phase-intelligence');

describe('PhaseIntelligence', () => {
  let pi;

  beforeEach(() => {
    pi = new PhaseIntelligence();
  });

  describe('assessComplexity()', () => {
    it('should throw if scope is not provided', () => {
      assert.throws(() => pi.assessComplexity(), /scope is required/);
    });

    it('should throw if scope is missing required fields', () => {
      assert.throws(() => pi.assessComplexity({}), /affectedFiles.*required/);
    });

    it('should return "simple" for small, single-repo, no-risk changes', () => {
      const result = pi.assessComplexity({
        affectedFiles: 1,
        affectedRepos: 1,
        hasArchitecturalChanges: false,
        hasSecurityImplications: false,
        hasDatabaseChanges: false,
        hasApiChanges: false
      });
      assert.strictEqual(result, 'simple');
    });

    it('should return "simple" at boundary (3 files, 1 repo)', () => {
      const result = pi.assessComplexity({
        affectedFiles: 3,
        affectedRepos: 1,
        hasArchitecturalChanges: false,
        hasSecurityImplications: false,
        hasDatabaseChanges: false,
        hasApiChanges: false
      });
      assert.strictEqual(result, 'simple');
    });

    it('should return "medium" when affectedFiles is 4 (just above simple threshold)', () => {
      const result = pi.assessComplexity({
        affectedFiles: 4,
        affectedRepos: 1,
        hasArchitecturalChanges: false,
        hasSecurityImplications: false,
        hasDatabaseChanges: false,
        hasApiChanges: false
      });
      assert.strictEqual(result, 'medium');
    });

    it('should return "medium" when affectedRepos is 2', () => {
      const result = pi.assessComplexity({
        affectedFiles: 2,
        affectedRepos: 2,
        hasArchitecturalChanges: false,
        hasSecurityImplications: false,
        hasDatabaseChanges: false,
        hasApiChanges: false
      });
      assert.strictEqual(result, 'medium');
    });

    it('should return "medium" with hasApiChanges but under complex thresholds', () => {
      const result = pi.assessComplexity({
        affectedFiles: 5,
        affectedRepos: 1,
        hasArchitecturalChanges: false,
        hasSecurityImplications: false,
        hasDatabaseChanges: false,
        hasApiChanges: true
      });
      assert.strictEqual(result, 'medium');
    });

    it('should return "medium" with security but no db changes', () => {
      const result = pi.assessComplexity({
        affectedFiles: 5,
        affectedRepos: 1,
        hasArchitecturalChanges: false,
        hasSecurityImplications: true,
        hasDatabaseChanges: false,
        hasApiChanges: false
      });
      assert.strictEqual(result, 'medium');
    });

    it('should return "complex" when affectedFiles > 10', () => {
      const result = pi.assessComplexity({
        affectedFiles: 11,
        affectedRepos: 1,
        hasArchitecturalChanges: false,
        hasSecurityImplications: false,
        hasDatabaseChanges: false,
        hasApiChanges: false
      });
      assert.strictEqual(result, 'complex');
    });

    it('should return "complex" when affectedRepos > 3', () => {
      const result = pi.assessComplexity({
        affectedFiles: 1,
        affectedRepos: 4,
        hasArchitecturalChanges: false,
        hasSecurityImplications: false,
        hasDatabaseChanges: false,
        hasApiChanges: false
      });
      assert.strictEqual(result, 'complex');
    });

    it('should return "complex" when hasArchitecturalChanges', () => {
      const result = pi.assessComplexity({
        affectedFiles: 1,
        affectedRepos: 1,
        hasArchitecturalChanges: true,
        hasSecurityImplications: false,
        hasDatabaseChanges: false,
        hasApiChanges: false
      });
      assert.strictEqual(result, 'complex');
    });

    it('should return "complex" when both security and db changes', () => {
      const result = pi.assessComplexity({
        affectedFiles: 1,
        affectedRepos: 1,
        hasArchitecturalChanges: false,
        hasSecurityImplications: true,
        hasDatabaseChanges: true,
        hasApiChanges: false
      });
      assert.strictEqual(result, 'complex');
    });

    it('should return "medium" when affectedFiles is exactly 10 (boundary)', () => {
      const result = pi.assessComplexity({
        affectedFiles: 10,
        affectedRepos: 1,
        hasArchitecturalChanges: false,
        hasSecurityImplications: false,
        hasDatabaseChanges: false,
        hasApiChanges: false
      });
      assert.strictEqual(result, 'medium');
    });

    it('should return "medium" when affectedRepos is exactly 3 (boundary)', () => {
      const result = pi.assessComplexity({
        affectedFiles: 1,
        affectedRepos: 3,
        hasArchitecturalChanges: false,
        hasSecurityImplications: false,
        hasDatabaseChanges: false,
        hasApiChanges: false
      });
      assert.strictEqual(result, 'medium');
    });
  });

  describe('selectPhases()', () => {
    it('should throw if complexity is not provided', () => {
      assert.throws(() => pi.selectPhases(), /complexity is required/);
    });

    it('should throw for invalid complexity value', () => {
      assert.throws(() => pi.selectPhases('extreme'), /Invalid complexity/);
    });

    it('should return phases [1, 6, 7, 8] for simple', () => {
      const result = pi.selectPhases('simple');
      assert.deepStrictEqual(result, [1, 6, 7, 8]);
    });

    it('should return phases [1, 2, 6, 7, 8, 9] for medium', () => {
      const result = pi.selectPhases('medium');
      assert.deepStrictEqual(result, [1, 2, 6, 7, 8, 9]);
    });

    it('should return all phases for complex', () => {
      const result = pi.selectPhases('complex');
      assert.deepStrictEqual(result, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    });

    it('should apply customConfig override when provided', () => {
      const result = pi.selectPhases('simple', { phases: [1, 7, 8] });
      assert.deepStrictEqual(result, [1, 7, 8]);
    });

    it('should validate customConfig phases are valid numbers', () => {
      assert.throws(
        () => pi.selectPhases('simple', { phases: [1, 99] }),
        /Invalid phase number: 99/
      );
    });

    it('should validate customConfig phases is an array', () => {
      assert.throws(
        () => pi.selectPhases('simple', { phases: 'not-array' }),
        /phases must be an array/
      );
    });
  });

  describe('shouldStop()', () => {
    it('should throw if phase is not provided', () => {
      assert.throws(() => pi.shouldStop(), /phase is required/);
    });

    it('should throw if results is not provided', () => {
      assert.throws(() => pi.shouldStop(1), /results is required/);
    });

    it('should throw if mode is invalid', () => {
      assert.throws(() => pi.shouldStop(1, {}, 'invalid'), /Invalid mode/);
    });

    it('should default mode to autonomous', () => {
      const result = pi.shouldStop(1, {});
      assert.strictEqual(typeof result.stop, 'boolean');
    });

    // Guided mode tests
    it('should always stop in guided mode', () => {
      const result = pi.shouldStop(1, {}, 'guided');
      assert.strictEqual(result.stop, true);
      assert.strictEqual(result.severity, 'info');
      assert.ok(result.reason.includes('guided'));
    });

    it('should always stop in guided mode regardless of phase', () => {
      for (let phase = 1; phase <= 10; phase++) {
        const result = pi.shouldStop(phase, {}, 'guided');
        assert.strictEqual(result.stop, true);
      }
    });

    // Autonomous mode - Phase 1 (Bootstrap)
    it('should stop at phase 1 when requirementsUnclear', () => {
      const result = pi.shouldStop(1, { requirementsUnclear: true }, 'autonomous');
      assert.strictEqual(result.stop, true);
      assert.strictEqual(result.severity, 'warning');
    });

    it('should stop at phase 1 when conflictingStakeholders', () => {
      const result = pi.shouldStop(1, { conflictingStakeholders: true }, 'autonomous');
      assert.strictEqual(result.stop, true);
    });

    it('should stop at phase 1 when missingAC', () => {
      const result = pi.shouldStop(1, { missingAC: true }, 'autonomous');
      assert.strictEqual(result.stop, true);
    });

    it('should not stop at phase 1 when no issues', () => {
      const result = pi.shouldStop(1, {}, 'autonomous');
      assert.strictEqual(result.stop, false);
      assert.strictEqual(result.reason, null);
    });

    // Autonomous mode - Phase 2 (Scope)
    it('should stop at phase 2 when affectedFiles > 10', () => {
      const result = pi.shouldStop(2, { affectedFiles: 11 }, 'autonomous');
      assert.strictEqual(result.stop, true);
    });

    it('should not stop at phase 2 when affectedFiles <= 10', () => {
      const result = pi.shouldStop(2, { affectedFiles: 10 }, 'autonomous');
      assert.strictEqual(result.stop, false);
    });

    it('should stop at phase 2 when affectedRepos > 5', () => {
      const result = pi.shouldStop(2, { affectedRepos: 6 }, 'autonomous');
      assert.strictEqual(result.stop, true);
    });

    it('should stop at phase 2 when unfamiliarSubsystems', () => {
      const result = pi.shouldStop(2, { unfamiliarSubsystems: true }, 'autonomous');
      assert.strictEqual(result.stop, true);
    });

    // Autonomous mode - Phase 3 (Audit)
    it('should stop at phase 3 when criticalFindings > 0', () => {
      const result = pi.shouldStop(3, { criticalFindings: 1 }, 'autonomous');
      assert.strictEqual(result.stop, true);
      assert.strictEqual(result.severity, 'critical');
    });

    it('should stop at phase 3 when highFindings > 0', () => {
      const result = pi.shouldStop(3, { highFindings: 2 }, 'autonomous');
      assert.strictEqual(result.stop, true);
      assert.strictEqual(result.severity, 'critical');
    });

    it('should stop at phase 3 when totalIssues > 50', () => {
      const result = pi.shouldStop(3, { totalIssues: 51 }, 'autonomous');
      assert.strictEqual(result.stop, true);
      assert.strictEqual(result.severity, 'warning');
    });

    it('should not stop at phase 3 with low findings', () => {
      const result = pi.shouldStop(3, { criticalFindings: 0, highFindings: 0, totalIssues: 10 }, 'autonomous');
      assert.strictEqual(result.stop, false);
    });

    // Autonomous mode - Phase 6 (Planning)
    it('should stop at phase 6 when multipleApproaches', () => {
      const result = pi.shouldStop(6, { multipleApproaches: true }, 'autonomous');
      assert.strictEqual(result.stop, true);
    });

    it('should stop at phase 6 when highRiskItems > 0', () => {
      const result = pi.shouldStop(6, { highRiskItems: 1 }, 'autonomous');
      assert.strictEqual(result.stop, true);
      assert.strictEqual(result.severity, 'critical');
    });

    // Autonomous mode - Phase 7 (Execution)
    it('should stop at phase 7 when buildFailures > 0', () => {
      const result = pi.shouldStop(7, { buildFailures: 1 }, 'autonomous');
      assert.strictEqual(result.stop, true);
      assert.strictEqual(result.severity, 'critical');
    });

    it('should stop at phase 7 when testFailures > 0', () => {
      const result = pi.shouldStop(7, { testFailures: 3 }, 'autonomous');
      assert.strictEqual(result.stop, true);
    });

    it('should stop at phase 7 when mergeConflicts', () => {
      const result = pi.shouldStop(7, { mergeConflicts: true }, 'autonomous');
      assert.strictEqual(result.stop, true);
    });

    // Autonomous mode - Phase 8 (Verification)
    it('should stop at phase 8 when anyFailures', () => {
      const result = pi.shouldStop(8, { anyFailures: true }, 'autonomous');
      assert.strictEqual(result.stop, true);
      assert.strictEqual(result.severity, 'critical');
    });

    it('should not stop at phase 8 when no failures', () => {
      const result = pi.shouldStop(8, { anyFailures: false }, 'autonomous');
      assert.strictEqual(result.stop, false);
    });

    // Autonomous mode - Phase 9 (PR)
    it('should stop at phase 9 when hookFailures', () => {
      const result = pi.shouldStop(9, { hookFailures: true }, 'autonomous');
      assert.strictEqual(result.stop, true);
    });

    it('should stop at phase 9 when reviewFeedback', () => {
      const result = pi.shouldStop(9, { reviewFeedback: true }, 'autonomous');
      assert.strictEqual(result.stop, true);
    });

    // Autonomous mode - Phase 4 (Scope Refinement)
    it('should stop at phase 4 when architecturalTradeoffs', () => {
      const result = pi.shouldStop(4, { architecturalTradeoffs: true }, 'autonomous');
      assert.strictEqual(result.stop, true);
      assert.strictEqual(result.severity, 'warning');
    });

    it('should stop at phase 4 when scopeGrew', () => {
      const result = pi.shouldStop(4, { scopeGrew: true }, 'autonomous');
      assert.strictEqual(result.stop, true);
      assert.strictEqual(result.severity, 'warning');
    });

    it('should not stop at phase 4 when no issues', () => {
      const result = pi.shouldStop(4, {}, 'autonomous');
      assert.strictEqual(result.stop, false);
    });

    // Autonomous mode - Phase 5 (Reporting) — always advances
    it('should not stop at phase 5 in autonomous mode', () => {
      const result = pi.shouldStop(5, {}, 'autonomous');
      assert.strictEqual(result.stop, false);
    });

    // Autonomous mode - Phase 10 (Retrospective)
    it('should stop at phase 10 when criticalIncidents', () => {
      const result = pi.shouldStop(10, { criticalIncidents: true }, 'autonomous');
      assert.strictEqual(result.stop, true);
      assert.strictEqual(result.severity, 'critical');
    });

    it('should not stop at phase 10 when no critical incidents', () => {
      const result = pi.shouldStop(10, {}, 'autonomous');
      assert.strictEqual(result.stop, false);
    });
  });

  describe('getPhaseDescription()', () => {
    it('should throw for invalid phase number', () => {
      assert.throws(() => pi.getPhaseDescription(0), /Invalid phase number/);
      assert.throws(() => pi.getPhaseDescription(11), /Invalid phase number/);
    });

    it('should return description for phase 1', () => {
      const desc = pi.getPhaseDescription(1);
      assert.strictEqual(desc.name, 'Bootstrap');
      assert.ok(desc.description);
      assert.ok(desc.specialist);
      assert.ok(desc.estimatedDuration);
    });

    it('should return descriptions for all 10 phases', () => {
      for (let i = 1; i <= 10; i++) {
        const desc = pi.getPhaseDescription(i);
        assert.ok(desc.name, `Phase ${i} missing name`);
        assert.ok(desc.description, `Phase ${i} missing description`);
        assert.ok(desc.specialist, `Phase ${i} missing specialist`);
        assert.ok(desc.estimatedDuration, `Phase ${i} missing estimatedDuration`);
      }
    });

    it('should return correct specialist for execution phase', () => {
      const desc = pi.getPhaseDescription(7);
      assert.strictEqual(desc.name, 'Execution');
    });
  });

  describe('getNextPhase()', () => {
    it('should throw if currentPhase is not provided', () => {
      assert.throws(() => pi.getNextPhase(), /currentPhase is required/);
    });

    it('should throw if selectedPhases is not provided', () => {
      assert.throws(() => pi.getNextPhase(1), /selectedPhases is required/);
    });

    it('should return next phase in simple workflow', () => {
      const selectedPhases = [1, 6, 7, 8];
      assert.strictEqual(pi.getNextPhase(1, selectedPhases), 6);
      assert.strictEqual(pi.getNextPhase(6, selectedPhases), 7);
      assert.strictEqual(pi.getNextPhase(7, selectedPhases), 8);
    });

    it('should return null when all phases complete', () => {
      const selectedPhases = [1, 6, 7, 8];
      assert.strictEqual(pi.getNextPhase(8, selectedPhases), null);
    });

    it('should skip phases not in selectedPhases', () => {
      const selectedPhases = [1, 6, 7, 8];
      // If currentPhase is 2 (not in selected), find next selected after 2
      assert.strictEqual(pi.getNextPhase(2, selectedPhases), 6);
    });

    it('should return null if currentPhase is beyond all selected', () => {
      const selectedPhases = [1, 6, 7, 8];
      assert.strictEqual(pi.getNextPhase(9, selectedPhases), null);
    });

    it('should work with full complex workflow', () => {
      const selectedPhases = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
      assert.strictEqual(pi.getNextPhase(1, selectedPhases), 2);
      assert.strictEqual(pi.getNextPhase(9, selectedPhases), 10);
      assert.strictEqual(pi.getNextPhase(10, selectedPhases), null);
    });
  });
});
