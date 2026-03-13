const assert = require('assert');
const fs = require('fs');
const path = require('path');
const StateManager = require('../lib/state-manager');

describe('StateManager', () => {
  const testDir = '/tmp/sdlc-test-state';

  beforeEach(() => {
    if (fs.existsSync(testDir)) {
      fs.rmSync(testDir, { recursive: true });
    }
    fs.mkdirSync(testDir, { recursive: true });
  });

  afterEach(() => {
    if (fs.existsSync(testDir)) {
      fs.rmSync(testDir, { recursive: true });
    }
  });

  it('should initialize new state file from template', () => {
    const manager = new StateManager(testDir, 'US#12345', 'TestStory');
    manager.initialize({ mode: 'autonomous', complexity: 'medium' });

    const statePath = path.join(testDir, 'workflow_state.md');
    assert.ok(fs.existsSync(statePath), 'State file should exist');

    const content = fs.readFileSync(statePath, 'utf8');
    assert.ok(content.includes('US#12345'), 'Should include work item ID');
    assert.ok(content.includes('TestStory'), 'Should include story title');
    assert.ok(content.includes('Mode: Autonomous'), 'Should include mode');
  });

  it('should update phase status', () => {
    const manager = new StateManager(testDir, 'US#12345', 'TestStory');
    manager.initialize({ mode: 'autonomous', complexity: 'medium' });

    manager.updatePhase(1, 'completed', 'Bootstrap complete - folder created');

    const content = fs.readFileSync(manager.statePath, 'utf8');
    assert.ok(content.includes('[x] 1. Bootstrap'), 'Phase 1 should be checked');
    assert.ok(content.includes('Bootstrap complete'), 'Should include summary');
  });

  it('should store decision in Memory MCP', async () => {
    const manager = new StateManager(testDir, 'US#12345', 'TestStory');
    manager.initialize({ mode: 'autonomous', complexity: 'medium' });

    // Mock Memory MCP (will be real in integration)
    const mockMemory = [];
    manager.setMemoryClient({
      store: (entry) => mockMemory.push(entry)
    });

    await manager.logDecision(2, 'Include 3 repos only', 'Architect confirmed scope', 'user');

    assert.strictEqual(mockMemory.length, 1);
    assert.strictEqual(mockMemory[0].tags.includes('sdlc'), true);
    assert.strictEqual(mockMemory[0].tags.includes('US#12345'), true);
  });
});
