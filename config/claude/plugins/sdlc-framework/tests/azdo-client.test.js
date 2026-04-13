const assert = require('assert');
const AzdoClient = require('../lib/azdo-client');

describe('AzdoClient', () => {
  let client;

  beforeEach(() => {
    client = new AzdoClient();
  });

  describe('parseWorkItemId', () => {
    it('should extract ID from US# prefix', () => {
      assert.strictEqual(client.parseWorkItemId('US#170514'), 170514);
    });

    it('should extract ID from Bug# prefix', () => {
      assert.strictEqual(client.parseWorkItemId('Bug#67890'), 67890);
    });

    it('should extract ID from Task# prefix', () => {
      assert.strictEqual(client.parseWorkItemId('Task#12345'), 12345);
    });

    it('should extract ID from plain number string', () => {
      assert.strictEqual(client.parseWorkItemId('170514'), 170514);
    });

    it('should extract ID from hash prefix', () => {
      assert.strictEqual(client.parseWorkItemId('#170514'), 170514);
    });

    it('should extract ID from full AZDO URL', () => {
      const url = 'https://dev.azure.com/org/project/_workitems/edit/170514';
      assert.strictEqual(client.parseWorkItemId(url), 170514);
    });

    it('should extract ID from AZDO URL with query params', () => {
      const url = 'https://dev.azure.com/org/project/_workitems/edit/170514?fullScreen=true';
      assert.strictEqual(client.parseWorkItemId(url), 170514);
    });

    it('should return null for invalid input', () => {
      assert.strictEqual(client.parseWorkItemId(''), null);
      assert.strictEqual(client.parseWorkItemId(null), null);
      assert.strictEqual(client.parseWorkItemId(undefined), null);
      assert.strictEqual(client.parseWorkItemId('no-numbers-here'), null);
    });

    it('should return null for non-string input', () => {
      assert.strictEqual(client.parseWorkItemId(12345), null);
      assert.strictEqual(client.parseWorkItemId({}), null);
    });

    it('should handle Feature# prefix', () => {
      assert.strictEqual(client.parseWorkItemId('Feature#99999'), 99999);
    });

    it('should handle case-insensitive prefixes', () => {
      assert.strictEqual(client.parseWorkItemId('us#170514'), 170514);
      assert.strictEqual(client.parseWorkItemId('bug#67890'), 67890);
      assert.strictEqual(client.parseWorkItemId('task#12345'), 12345);
    });
  });

  describe('parseWorkItemType', () => {
    it('should return User Story for US# prefix', () => {
      assert.strictEqual(client.parseWorkItemType('US#170514'), 'User Story');
    });

    it('should return Bug for Bug# prefix', () => {
      assert.strictEqual(client.parseWorkItemType('Bug#67890'), 'Bug');
    });

    it('should return Task for Task# prefix', () => {
      assert.strictEqual(client.parseWorkItemType('Task#12345'), 'Task');
    });

    it('should return Feature for Feature# prefix', () => {
      assert.strictEqual(client.parseWorkItemType('Feature#99999'), 'Feature');
    });

    it('should return null for plain number', () => {
      assert.strictEqual(client.parseWorkItemType('170514'), null);
    });

    it('should return null for hash prefix only', () => {
      assert.strictEqual(client.parseWorkItemType('#170514'), null);
    });

    it('should return null for URL input', () => {
      const url = 'https://dev.azure.com/org/project/_workitems/edit/170514';
      assert.strictEqual(client.parseWorkItemType(url), null);
    });

    it('should return null for invalid input', () => {
      assert.strictEqual(client.parseWorkItemType(null), null);
      assert.strictEqual(client.parseWorkItemType(''), null);
      assert.strictEqual(client.parseWorkItemType(123), null);
    });

    it('should handle case-insensitive prefixes', () => {
      assert.strictEqual(client.parseWorkItemType('us#170514'), 'User Story');
      assert.strictEqual(client.parseWorkItemType('BUG#67890'), 'Bug');
    });
  });

  describe('extractRequirements', () => {
    const sampleFields = {
      'System.Title': 'Update dependencies for security patches',
      'System.Description': '<p>We need to update all packages</p>',
      'Microsoft.VSTS.Common.AcceptanceCriteria': '<ul><li>All tests pass</li><li>No breaking changes</li></ul>',
      'System.AssignedTo': { displayName: 'Daniel Paiva', uniqueName: 'daniel@example.com' },
      'System.State': 'Active',
      'System.Tags': 'security; dependencies; sprint-42',
      'Microsoft.VSTS.Common.Priority': 2,
      'Microsoft.VSTS.Scheduling.StoryPoints': 5
    };

    it('should extract title', () => {
      const result = client.extractRequirements(sampleFields);
      assert.strictEqual(result.title, 'Update dependencies for security patches');
    });

    it('should extract description', () => {
      const result = client.extractRequirements(sampleFields);
      assert.strictEqual(result.description, '<p>We need to update all packages</p>');
    });

    it('should extract acceptance criteria', () => {
      const result = client.extractRequirements(sampleFields);
      assert.strictEqual(result.acceptanceCriteria, '<ul><li>All tests pass</li><li>No breaking changes</li></ul>');
    });

    it('should extract assigned to display name', () => {
      const result = client.extractRequirements(sampleFields);
      assert.strictEqual(result.assignedTo, 'Daniel Paiva');
    });

    it('should extract state', () => {
      const result = client.extractRequirements(sampleFields);
      assert.strictEqual(result.state, 'Active');
    });

    it('should parse tags into array', () => {
      const result = client.extractRequirements(sampleFields);
      assert.deepStrictEqual(result.tags, ['security', 'dependencies', 'sprint-42']);
    });

    it('should extract priority', () => {
      const result = client.extractRequirements(sampleFields);
      assert.strictEqual(result.priority, 2);
    });

    it('should extract story points', () => {
      const result = client.extractRequirements(sampleFields);
      assert.strictEqual(result.storyPoints, 5);
    });

    it('should handle missing fields gracefully', () => {
      const result = client.extractRequirements({});
      assert.strictEqual(result.title, null);
      assert.strictEqual(result.description, null);
      assert.strictEqual(result.acceptanceCriteria, null);
      assert.strictEqual(result.assignedTo, null);
      assert.strictEqual(result.state, null);
      assert.deepStrictEqual(result.tags, []);
      assert.strictEqual(result.priority, null);
      assert.strictEqual(result.storyPoints, null);
    });

    it('should handle assignedTo as string', () => {
      const result = client.extractRequirements({
        'System.AssignedTo': 'Daniel Paiva'
      });
      assert.strictEqual(result.assignedTo, 'Daniel Paiva');
    });

    it('should handle empty tags string', () => {
      const result = client.extractRequirements({ 'System.Tags': '' });
      assert.deepStrictEqual(result.tags, []);
    });

    it('should throw on non-object input', () => {
      assert.throws(() => client.extractRequirements(null), /workItemFields must be a non-null object/);
      assert.throws(() => client.extractRequirements('string'), /workItemFields must be a non-null object/);
      assert.throws(() => client.extractRequirements(undefined), /workItemFields must be a non-null object/);
    });
  });

  describe('formatForBootstrap', () => {
    const sampleFields = {
      'System.Title': 'Update dependencies',
      'System.Description': 'Update all packages',
      'Microsoft.VSTS.Common.AcceptanceCriteria': '- All tests pass',
      'System.AssignedTo': { displayName: 'Daniel' },
      'System.State': 'Active',
      'System.Tags': 'security; sprint-42',
      'Microsoft.VSTS.Common.Priority': 2,
      'Microsoft.VSTS.Scheduling.StoryPoints': 3
    };

    it('should return markdown string', () => {
      const result = client.formatForBootstrap(170514, sampleFields);
      assert.strictEqual(typeof result, 'string');
    });

    it('should include work item ID in header', () => {
      const result = client.formatForBootstrap(170514, sampleFields);
      assert.ok(result.includes('170514'), 'Should contain work item ID');
    });

    it('should include title', () => {
      const result = client.formatForBootstrap(170514, sampleFields);
      assert.ok(result.includes('Update dependencies'), 'Should contain title');
    });

    it('should include acceptance criteria section', () => {
      const result = client.formatForBootstrap(170514, sampleFields);
      assert.ok(result.includes('Acceptance Criteria'), 'Should have AC section');
      assert.ok(result.includes('All tests pass'), 'Should contain AC content');
    });

    it('should include AZDO link', () => {
      const result = client.formatForBootstrap(170514, sampleFields);
      assert.ok(result.includes('_workitems/edit/170514'), 'Should contain AZDO link');
    });

    it('should include stakeholder info', () => {
      const result = client.formatForBootstrap(170514, sampleFields);
      assert.ok(result.includes('Daniel'), 'Should contain assigned to');
    });

    it('should throw if workItemId is invalid', () => {
      assert.throws(() => client.formatForBootstrap(null, sampleFields), /workItemId is required/);
      assert.throws(() => client.formatForBootstrap(0, sampleFields), /workItemId is required/);
    });

    it('should throw if workItemFields is invalid', () => {
      assert.throws(() => client.formatForBootstrap(170514, null), /workItemFields must be a non-null object/);
    });
  });

  describe('buildMcpToolCall', () => {
    it('should return correct tool name', () => {
      const result = client.buildMcpToolCall(170514);
      assert.strictEqual(result.tool, 'mcp__azure-devops__wit_get_work_item');
    });

    it('should include work item ID as param', () => {
      const result = client.buildMcpToolCall(170514);
      assert.strictEqual(result.params.id, 170514);
    });

    it('should throw on invalid ID', () => {
      assert.throws(() => client.buildMcpToolCall(null), /workItemId is required/);
      assert.throws(() => client.buildMcpToolCall(0), /workItemId is required/);
      assert.throws(() => client.buildMcpToolCall(-1), /workItemId must be a positive integer/);
      assert.throws(() => client.buildMcpToolCall('abc'), /workItemId must be a positive integer/);
    });
  });
});
