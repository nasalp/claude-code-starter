#!/usr/bin/env node
/**
 * Project Initialization Check
 *
 * Cross-platform (Windows, macOS, Linux)
 *
 * Called from session-start.js to detect whether the current project
 * has been properly initialized with ECC configuration.
 *
 * Returns a structured report of what is present and what is missing.
 * Does NOT modify any files.
 */

const fs = require('fs');
const path = require('path');

/**
 * Check if a path exists (file or directory)
 * @param {string} p - Path to check
 * @returns {boolean}
 */
function exists(p) {
  try {
    return fs.existsSync(p);
  } catch {
    return false;
  }
}

/**
 * Check if a directory has any files matching a pattern
 * @param {string} dir - Directory to check
 * @param {string} ext - File extension (e.g., '.sh', '.md')
 * @returns {boolean}
 */
function hasFilesWithExtension(dir, ext) {
  try {
    if (!fs.existsSync(dir)) return false;
    const entries = fs.readdirSync(dir);
    return entries.some(e => e.endsWith(ext));
  } catch {
    return false;
  }
}

/**
 * Check if a file contains a specific string
 * @param {string} filePath - File to check
 * @param {string} needle - String to search for
 * @returns {boolean}
 */
function fileContains(filePath, needle) {
  try {
    if (!fs.existsSync(filePath)) return false;
    const content = fs.readFileSync(filePath, 'utf8');
    return content.includes(needle);
  } catch {
    return false;
  }
}

/**
 * Run initialization check for a project directory
 * @param {string} projectDir - Project root directory
 * @returns {{ missing: string[], present: string[], needsInit: boolean, summary: string }}
 */
function checkProjectInit(projectDir) {
  const missing = [];
  const present = [];

  // 1. CLAUDE.md in project root
  const claudeMd = path.join(projectDir, 'CLAUDE.md');
  if (exists(claudeMd)) {
    present.push('CLAUDE.md');
  } else {
    missing.push('CLAUDE.md (project-level context file)');
  }

  // 2. .claude/ directory
  const claudeDir = path.join(projectDir, '.claude');
  if (exists(claudeDir)) {
    present.push('.claude/');
  } else {
    missing.push('.claude/ directory');
  }

  // 3. .claude/settings.json (project-level)
  const settingsJson = path.join(projectDir, '.claude', 'settings.json');
  if (exists(settingsJson)) {
    present.push('.claude/settings.json');
  } else {
    missing.push('.claude/settings.json (project hooks and settings)');
  }

  // 4. Hooks in .claude/hooks/
  const hooksDir = path.join(projectDir, '.claude', 'hooks');
  if (hasFilesWithExtension(hooksDir, '.sh')) {
    present.push('.claude/hooks/ (shell hooks)');
  } else {
    missing.push('.claude/hooks/ (enforcement hooks)');
  }

  // 5. Rules imported
  const rulesDir = path.join(projectDir, '.claude', 'rules');
  if (exists(rulesDir) && hasFilesWithExtension(rulesDir, '.md')) {
    present.push('.claude/rules/ (project rules)');
  } else {
    missing.push('.claude/rules/ (coding standards and rules)');
  }

  // 6. spec/ directory
  const specDir = path.join(projectDir, 'spec');
  if (exists(specDir)) {
    present.push('spec/ (specifications)');
  } else {
    missing.push('spec/ (feature specifications directory)');
  }

  // 7. Check if CLAUDE.md imports GLOBAL.md (if CLAUDE.md exists)
  if (exists(claudeMd)) {
    if (fileContains(claudeMd, 'GLOBAL.md') || fileContains(claudeMd, '@~/.claude/')) {
      present.push('CLAUDE.md imports global config');
    }
    // Not flagged as missing -- GLOBAL.md import is optional
  }

  const needsInit = missing.length > 0;

  let summary;
  if (!needsInit) {
    summary = 'Project is fully initialized.';
  } else if (missing.length >= 4) {
    summary = 'Project needs initialization. Run /user:init-project to set up.';
  } else {
    summary = `Project partially initialized. Missing: ${missing.join(', ')}`;
  }

  return { missing, present, needsInit, summary };
}

module.exports = { checkProjectInit };

// CLI mode: run directly for diagnostics
if (require.main === module) {
  const projectDir = process.argv[2] || process.cwd();
  const result = checkProjectInit(projectDir);

  if (result.needsInit) {
    console.error(`[InitCheck] ${result.summary}`);
    if (result.missing.length > 0) {
      result.missing.forEach(m => console.error(`[InitCheck]   MISSING: ${m}`));
    }
  } else {
    console.error(`[InitCheck] ${result.summary}`);
  }

  // Output structured data to stdout (for SessionStart injection)
  if (result.needsInit) {
    console.log(JSON.stringify(result, null, 2));
  }
}
