const assert = require('assert');
const fs = require('fs');
const path = require('path');
const FolderScaffold = require('../lib/folder-scaffold');

describe('FolderScaffold', () => {
  const testDir = '/tmp/sdlc-test-scaffold';

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

  it('should create user story folder with sanitized title', () => {
    const scaffold = new FolderScaffold(testDir);
    const folderPath = scaffold.create('US#170514', 'Update Dependencies & Security Patches');

    assert.ok(fs.existsSync(folderPath), 'Story folder should exist');
    assert.ok(folderPath.endsWith('user_story-170514-Update-Dependencies-Security-Patches'), 'Should sanitize title');
  });

  it('should create all 10 phase folders', () => {
    const scaffold = new FolderScaffold(testDir);
    const folderPath = scaffold.create('US#12345', 'Test');

    const phaseNames = scaffold.getPhaseNames();
    for (let i = 1; i <= 10; i++) {
      const paddedNum = String(i).padStart(2, '0');
      const phaseFolder = path.join(folderPath, `${paddedNum}-${phaseNames[i]}`);
      assert.ok(fs.existsSync(phaseFolder), `Phase ${i} folder should exist: ${phaseFolder}`);

      // Verify .gitkeep exists
      const gitkeepPath = path.join(phaseFolder, '.gitkeep');
      assert.ok(fs.existsSync(gitkeepPath), `Phase ${i} should have .gitkeep: ${gitkeepPath}`);
    }
  });

  it('should return immutable phase names copy', () => {
    const scaffold = new FolderScaffold(testDir);
    const names1 = scaffold.getPhaseNames();
    const names2 = scaffold.getPhaseNames();

    // Mutate the returned copy
    names1[1] = 'CORRUPTED';

    // Should not affect future calls
    assert.strictEqual(names2[1], 'bootstrap');
    assert.strictEqual(scaffold.getPhaseNames()[1], 'bootstrap');
  });

  it('should throw error if workItemId has no digits', () => {
    const scaffold = new FolderScaffold(testDir);

    assert.throws(() => {
      scaffold.create('NoDigits', 'Test');
    }, /workItemId must contain at least one digit/);
  });

  it('should throw error if title becomes empty after sanitization', () => {
    const scaffold = new FolderScaffold(testDir);

    assert.throws(() => {
      scaffold.create('US#123', '!!!@@@');
    }, /title must contain at least one alphanumeric character/);
  });

  it('should throw error if workItemId is empty', () => {
    const scaffold = new FolderScaffold(testDir);

    assert.throws(() => {
      scaffold.create('', 'Test');
    }, /workItemId is required/);
  });

  it('should throw error if title is empty', () => {
    const scaffold = new FolderScaffold(testDir);

    assert.throws(() => {
      scaffold.create('US#123', '');
    }, /title is required/);
  });
});
