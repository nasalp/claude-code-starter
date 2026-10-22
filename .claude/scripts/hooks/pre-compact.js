#!/usr/bin/env node
/**
 * PreCompact Hook - Save state before context compaction
 *
 * Cross-platform (Windows, macOS, Linux)
 *
 * Runs before Claude compacts context, giving you a chance to
 * preserve important state that might get lost in summarization.
 */

const fs = require('fs');
const path = require('path');
const {
  getSessionsDir,
  getDateTimeString,
  getTimeString,
  findFiles,
  ensureDir,
  appendFile,
  writeFile,
  log
} = require('../lib/utils');

/**
 * Capture current task state for post-compaction recovery.
 *
 * Saves a JSON breadcrumb with:
 * - Timestamp of compaction
 * - Whether FEATURE.md exists (and its first 500 chars as summary)
 * - List of recently modified files (git diff --name-only)
 * - Current branch name
 *
 * After compaction, CLAUDE.md instructions tell Claude to check this file
 * and re-read FEATURE.md if it exists.
 */
function saveCompactionState(sessionsDir) {
  const projectDir = process.cwd();
  const state = {
    compactedAt: new Date().toISOString(),
    projectDir,
    featureMd: null,
    branch: null,
    modifiedFiles: [],
    hooksExecutable: true
  };

  // Capture FEATURE.md summary
  try {
    const featurePath = path.join(projectDir, 'FEATURE.md');
    if (fs.existsSync(featurePath)) {
      const content = fs.readFileSync(featurePath, 'utf8');
      state.featureMd = {
        exists: true,
        path: featurePath,
        summary: content.substring(0, 500)
      };
    }
  } catch {
    // Non-critical
  }

  // Capture current branch
  try {
    const { execSync } = require('child_process');
    state.branch = execSync('git rev-parse --abbrev-ref HEAD', {
      cwd: projectDir,
      encoding: 'utf8',
      timeout: 5000
    }).trim();
  } catch {
    // Not in a git repo or git unavailable
  }

  // Capture recently modified files
  try {
    const { execSync } = require('child_process');
    const diff = execSync('git diff --name-only HEAD 2>/dev/null || true', {
      cwd: projectDir,
      encoding: 'utf8',
      timeout: 5000
    }).trim();
    if (diff) {
      state.modifiedFiles = diff.split('\n').filter(Boolean).slice(0, 20);
    }
  } catch {
    // Non-critical
  }

  // Check hooks are still executable
  try {
    const hooksDir = path.join(projectDir, '.claude', 'hooks');
    if (fs.existsSync(hooksDir)) {
      const hookFiles = fs.readdirSync(hooksDir).filter(f => f.endsWith('.sh'));
      for (const hook of hookFiles) {
        const hookPath = path.join(hooksDir, hook);
        try {
          fs.accessSync(hookPath, fs.constants.X_OK);
        } catch {
          state.hooksExecutable = false;
          log(`[PreCompact] WARNING: Hook not executable: ${hook}`);
          break;
        }
      }
    }
  } catch {
    // Non-critical
  }

  // Write compaction state breadcrumb
  const statePath = path.join(sessionsDir, 'compaction-state.json');
  writeFile(statePath, JSON.stringify(state, null, 2));
  log('[PreCompact] Compaction state saved to compaction-state.json');
}

async function main() {
  const sessionsDir = getSessionsDir();
  const compactionLog = path.join(sessionsDir, 'compaction-log.txt');

  ensureDir(sessionsDir);

  // Log compaction event with timestamp
  const timestamp = getDateTimeString();
  appendFile(compactionLog, `[${timestamp}] Context compaction triggered\n`);

  // If there's an active session file, note the compaction
  const sessions = findFiles(sessionsDir, '*-session.tmp');

  if (sessions.length > 0) {
    const activeSession = sessions[0].path;
    const timeStr = getTimeString();
    appendFile(activeSession, `\n---\n**[Compaction occurred at ${timeStr}]** - Context was summarized\n`);
  }

  // Save compaction state breadcrumb for post-compaction recovery
  saveCompactionState(sessionsDir);

  log('[PreCompact] State saved before compaction');
  process.exit(0);
}

main().catch(err => {
  console.error('[PreCompact] Error:', err.message);
  process.exit(0);
});
