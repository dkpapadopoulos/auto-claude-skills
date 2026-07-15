# Proposal: Installed-Plugin Drift Canary at Session Start

## Why

The plugin executes from a versioned cache
(`~/.claude/plugins/cache/acsm/auto-claude-skills/<version>/`), while
development happens in the source repo. When the cache lags the source, the
session silently enforces **old gate logic** — this has bitten twice
(pre-#107 cache false-denied phrase mentions). Nothing today tells the user
their running plugin has drifted from the source they are editing.

This is post-audit triage item 1 (2026-07-15, Codex-sparred), agreed minimal
design "Codex D2": no commits-behind metrics (cache dirs are not clones; 200ms
session-start budget), just a version compare plus a cheap manifest hash over
the gate-enforcement files the F5 canary already owns.

## What Changes

- `hooks/session-start-hook.sh`: new drift-canary block immediately after the
  F5 push-gate precondition canary, appending to the same `WARNINGS` array.
  Fires only when the session cwd is the plugin's own source repo and the
  running `PLUGIN_ROOT` is a different directory. Warning-only, fail-open,
  jq-path only.
- `tests/test-plugin-drift-canary.sh`: new behavioral test (disposable plugin
  root + disposable source repo, payload `.cwd`), red-first.
- Docs: CLAUDE.md gotcha note pairing the drift-canary file list with the F5
  canary list.

## Capabilities

### Modified
- `pdlc-safety`: adds the installed-plugin drift canary (version-drift and
  enforcement-manifest-drift warnings) beside the existing F5 push-gate
  precondition canary it extends.

## Impact

- No behavior change for sessions outside the plugin source repo (silent skip).
- No gating/deny behavior anywhere — warnings only.
- Session-start budget: ~10 `cksum` calls + 2 `jq` reads, only in the
  source-repo case.
