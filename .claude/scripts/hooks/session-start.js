#!/usr/bin/env node
/**
 * SessionStart Hook - Load previous context on new session
 *
 * Cross-platform (Windows, macOS, Linux)
 *
 * Runs when a new Claude session starts. Loads the most recent session
 * summary into Claude's context via stdout, and reports available
 * sessions and learned skills.
 */

const {
  getSessionsDir,
  getLearnedSkillsDir,
  findFiles,
  ensureDir,
  readFile,
  log,
  output
} = require('../lib/utils');
const { getPackageManager, getSelectionPrompt } = require('../lib/package-manager');
const { listAliases } = require('../lib/session-aliases');
const { detectProjectType } = require('../lib/project-detect');
const { checkProjectInit } = require('./init-check');

async function main() {
  const sessionsDir = getSessionsDir();
  const learnedDir = getLearnedSkillsDir();

  // Ensure directories exist
  ensureDir(sessionsDir);
  ensureDir(learnedDir);

  // Check for recent session files (last 7 days)
  const recentSessions = findFiles(sessionsDir, '*-session.tmp', { maxAge: 7 });

  if (recentSessions.length > 0) {
    const latest = recentSessions[0];
    log(`[SessionStart] Found ${recentSessions.length} recent session(s)`);
    log(`[SessionStart] Latest: ${latest.path}`);

    // Read and inject the latest session content into Claude's context
    const content = readFile(latest.path);
    if (content && !content.includes('[Session context goes here]')) {
      // Only inject if the session has actual content (not the blank template)
      output(`Previous session summary:\n${content}`);
    }
  }

  // Check for learned skills
  const learnedSkills = findFiles(learnedDir, '*.md');

  if (learnedSkills.length > 0) {
    log(`[SessionStart] ${learnedSkills.length} learned skill(s) available in ${learnedDir}`);
  }

  // Check for available session aliases
  const aliases = listAliases({ limit: 5 });

  if (aliases.length > 0) {
    const aliasNames = aliases.map(a => a.name).join(', ');
    log(`[SessionStart] ${aliases.length} session alias(es) available: ${aliasNames}`);
    log(`[SessionStart] Use /sessions load <alias> to continue a previous session`);
  }

  // Detect and report package manager
  const pm = getPackageManager();
  log(`[SessionStart] Package manager: ${pm.name} (${pm.source})`);

  // If no explicit package manager config was found, show selection prompt
  if (pm.source === 'default') {
    log('[SessionStart] No package manager preference found.');
    log(getSelectionPrompt());
  }

  // Detect project type and frameworks (#293)
  const projectInfo = detectProjectType();
  if (projectInfo.languages.length > 0 || projectInfo.frameworks.length > 0) {
    const parts = [];
    if (projectInfo.languages.length > 0) {
      parts.push(`languages: ${projectInfo.languages.join(', ')}`);
    }
    if (projectInfo.frameworks.length > 0) {
      parts.push(`frameworks: ${projectInfo.frameworks.join(', ')}`);
    }
    log(`[SessionStart] Project detected — ${parts.join('; ')}`);
    output(`Project type: ${JSON.stringify(projectInfo)}`);
  } else {
    log('[SessionStart] No specific project type detected');
  }

  // Check project initialization status
  try {
    const initResult = checkProjectInit(process.cwd());
    if (initResult.needsInit) {
      log(`[SessionStart] Project initialization incomplete — ${initResult.missing.length} item(s) missing`);
      const lines = [
        'PROJECT INIT CHECK: Incomplete setup detected.',
        `Missing: ${initResult.missing.join('; ')}`,
        'Suggest running /user:init-project to set up project configuration.'
      ];
      output(lines.join('\n'));
    } else {
      log('[SessionStart] Project initialization: OK');
    }
  } catch (initErr) {
    log(`[SessionStart] Init check skipped: ${initErr.message}`);
  }

  // Check for FEATURE.md (active spec) and compaction state
  try {
    const featureMd = require('path').join(process.cwd(), 'FEATURE.md');
    if (require('fs').existsSync(featureMd)) {
      log('[SessionStart] Active FEATURE.md found — read it for current task context');
      output('Active spec: FEATURE.md exists in project root. Read it for current task context.');
    }

    // Check for compaction state (breadcrumb from pre-compact)
    const compactionState = require('path').join(getSessionsDir(), 'compaction-state.json');
    if (require('fs').existsSync(compactionState)) {
      const stateContent = readFile(compactionState);
      if (stateContent) {
        log('[SessionStart] Compaction state found — restoring task context');
        output(`Post-compaction context restore:\n${stateContent}`);
      }
    }
  } catch (featureErr) {
    // Non-critical, skip silently
  }

  process.exit(0);
}

main().catch(err => {
  console.error('[SessionStart] Error:', err.message);
  process.exit(0); // Don't block on errors
});
