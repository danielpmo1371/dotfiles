const fs = require('fs');
const path = require('path');

class FolderScaffold {
  constructor(projectRoot) {
    this.projectRoot = projectRoot;
    this.phaseNames = {
      1: 'bootstrap',
      2: 'scope-discovery',
      3: 'audit',
      4: 'scope-refinement',
      5: 'reporting',
      6: 'planning',
      7: 'execution',
      8: 'verification',
      9: 'pr-delivery',
      10: 'retrospective'
    };
  }

  getPhaseNames() {
    return { ...this.phaseNames };
  }

  create(workItemId, title) {
    // Validate inputs
    if (!workItemId || typeof workItemId !== 'string') {
      throw new Error('workItemId is required and must be a string');
    }
    if (!title || typeof title !== 'string') {
      throw new Error('title is required and must be a non-empty string');
    }

    // Sanitize title (alphanumeric + hyphens, CamelCase preserved, max 50 chars)
    const sanitized = title
      .replace(/[^a-zA-Z0-9\s-]/g, '') // Remove special chars
      .replace(/\s+/g, '-')             // Spaces to hyphens
      .replace(/-+/g, '-')              // Collapse multiple hyphens
      .substring(0, 50);                // Max 50 chars

    // Validate sanitized output
    if (!sanitized || sanitized === '-') {
      throw new Error('title must contain at least one alphanumeric character');
    }

    // Extract ID from work item (e.g., "US#12345" → "12345")
    const id = workItemId.replace(/[^\d]/g, '');
    if (!id) {
      throw new Error('workItemId must contain at least one digit');
    }

    // Create root folder
    const folderName = `user_story-${id}-${sanitized}`;
    const folderPath = path.join(this.projectRoot, folderName);

    if (fs.existsSync(folderPath)) {
      throw new Error(`Folder already exists: ${folderPath}`);
    }

    fs.mkdirSync(folderPath, { recursive: true });

    // Create phase folders dynamically (templates/phase-folders/ reserved for future use)
    for (let i = 1; i <= 10; i++) {
      const phaseName = this.phaseNames[i];
      const paddedNum = String(i).padStart(2, '0');
      const phaseFolder = path.join(folderPath, `${paddedNum}-${phaseName}`);
      fs.mkdirSync(phaseFolder, { recursive: true });

      // Add .gitkeep to preserve empty folders
      fs.writeFileSync(path.join(phaseFolder, '.gitkeep'), '', 'utf8');
    }

    return folderPath;
  }
}

module.exports = FolderScaffold;
