const fs = require('fs');
const path = require('path');

class StateManager {
  constructor(storyDir, workItemId, title) {
    this.storyDir = storyDir;
    this.workItemId = workItemId;
    this.title = title;
    this.statePath = path.join(storyDir, 'workflow_state.md');
  }

  initialize({ mode, complexity }) {
    // Validate inputs
    if (!mode || typeof mode !== 'string') {
      throw new Error('mode is required and must be a string');
    }
    if (!complexity || typeof complexity !== 'string') {
      throw new Error('complexity is required and must be a string');
    }

    const template = this._loadTemplate();
    const content = template
      .replace(/{work_item_id}/g, this.workItemId)
      .replace(/{title}/g, this.title)
      .replace(/{mode}/g, mode.charAt(0).toUpperCase() + mode.slice(1))
      .replace(/{complexity}/g, complexity.charAt(0).toUpperCase() + complexity.slice(1))
      .replace(/{timestamp}/g, new Date().toISOString());

    fs.writeFileSync(this.statePath, content, 'utf8');
  }

  setMemoryClient(client) {
    this.memoryClient = client;
  }

  updatePhase(phaseNum, status, summary) {
    if (!fs.existsSync(this.statePath)) {
      throw new Error('State file not initialized. Call initialize() first.');
    }

    let content = fs.readFileSync(this.statePath, 'utf8');

    // Update phase checkbox
    const phaseRegex = new RegExp(`- \\[ \\] ${phaseNum}\\.`, 'g');
    if (status === 'completed') {
      content = content.replace(phaseRegex, `- [x] ${phaseNum}.`);
    }

    // Update current state section
    const stateRegex = /\*\*Active Phase:\*\* .+/;
    content = content.replace(stateRegex, `**Active Phase:** ${phaseNum + 1}. (next phase)`);

    // Update progress counter
    const completedCount = (content.match(/- \[x\]/g) || []).length;
    const progressRegex = /\*\*Progress:\*\* \d+\/10 phases complete/;
    content = content.replace(progressRegex, `**Progress:** ${completedCount}/10 phases complete`);

    // Add to activity log
    const timestamp = new Date().toISOString();
    const logEntry = `\n### ${timestamp} - Phase ${phaseNum} ${status}\n- ${summary}\n`;
    content = content.replace('## Team Lead Decisions', logEntry + '\n## Team Lead Decisions');

    // Update last modified
    content = content.replace(/\*Last updated:.+/, `*Last updated: ${timestamp} by StateManager*`);

    fs.writeFileSync(this.statePath, content, 'utf8');
  }

  async logDecision(phase, decision, rationale, decidedBy) {
    if (!fs.existsSync(this.statePath)) {
      throw new Error('State file not initialized. Call initialize() first.');
    }

    const timestamp = new Date().toISOString();

    // Update file (insert into Key Decisions section, not Current State)
    let content = fs.readFileSync(this.statePath, 'utf8');
    const decisionEntry = `\n### Phase ${phase}: (${timestamp})\n- **Decision:** ${decision}\n- **Rationale:** ${rationale}\n- **Decided by:** ${decidedBy}\n`;

    // Find Key Decisions section and insert after header
    const keyDecisionsRegex = /(## Key Decisions\n\n)/;
    if (keyDecisionsRegex.test(content)) {
      content = content.replace(keyDecisionsRegex, `$1${decisionEntry}\n`);
    } else {
      // Fallback: insert before Current State
      content = content.replace('## Current State', decisionEntry + '\n## Current State');
    }

    fs.writeFileSync(this.statePath, content, 'utf8');

    // Store in Memory MCP (if client available)
    if (this.memoryClient) {
      try {
        await this.memoryClient.store({
          content: `${this.workItemId} Phase ${phase} decision: ${decision}. Rationale: ${rationale}`,
          tags: ['sdlc', this.workItemId, `phase:${phase}`, 'decision'],
          memory_type: 'decision',
          metadata: {
            phase,
            decided_by: decidedBy,
            timestamp
          }
        });
      } catch (error) {
        console.warn(`Failed to store decision in Memory MCP: ${error.message}`);
        // Continue -- file write already succeeded
      }
    }
  }

  _loadTemplate() {
    const templatePath = path.join(__dirname, '..', 'templates', 'workflow_state.md.tmpl');

    if (!fs.existsSync(templatePath)) {
      throw new Error(`Template not found: ${templatePath}. Run from plugin root or ensure templates/ exists.`);
    }

    return fs.readFileSync(templatePath, 'utf8');
  }
}

module.exports = StateManager;
