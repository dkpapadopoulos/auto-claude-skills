# pdlc-safety (delta)

## ADDED Requirements

### Requirement: Installed-plugin drift canary at session start

The session-start hook MUST detect installed-plugin drift: when a session
starts with cwd inside the plugin's own source repo and the running plugin
executes from a different directory (the versioned cache), it MUST compare (1) the cache manifest `.version` against the
source manifest `.version` and (2) a `cksum` manifest over the gate-enforcement
files (`openspec-guard.sh`, `branch-ledger.sh`, `verdict.sh`, `git-command.sh`,
`session-token.sh`) between cache and source, and MUST emit a single
`PLUGIN DRIFT CANARY` warning naming what drifted when either check fails. The
canary MUST be warning-only (never gate or deny), MUST stay silent outside the
source repo and when nothing drifted, and MUST fail open — no canary error may
break session start. Expectation provenance: agreed Codex D2 minimal design,
post-audit triage 2026-07-15.

#### Scenario: Version drift is surfaced
- **GIVEN** a session whose cwd is the plugin source repo with manifest version
  `3.71.1` and a running plugin cache whose manifest version is `3.71.0`
- **WHEN** the session-start hook runs
- **THEN** the hook output MUST contain a `PLUGIN DRIFT CANARY` warning naming
  both versions, and session start MUST otherwise proceed normally

#### Scenario: Enforcement drift without a version bump is surfaced
- **GIVEN** cache and source manifests with the SAME version, but
  `hooks/lib/verdict.sh` differs between cache and source
- **WHEN** the session-start hook runs
- **THEN** the hook output MUST contain a `PLUGIN DRIFT CANARY` warning naming
  `verdict.sh` as drifted

#### Scenario: Silent outside the source repo and when healthy
- **GIVEN** (a) a session whose cwd is NOT a plugin source repo, or (b) a
  source-repo session whose cache matches on version and all gate-enforcement
  checksums
- **WHEN** the session-start hook runs
- **THEN** the output MUST NOT contain `PLUGIN DRIFT CANARY`

#### Scenario: Fail-open on unreadable inputs
- **GIVEN** a source-repo session whose running plugin root has no readable
  `.claude-plugin/plugin.json`
- **WHEN** the session-start hook runs
- **THEN** the hook MUST emit no drift warning and MUST still produce its
  normal SessionStart output
