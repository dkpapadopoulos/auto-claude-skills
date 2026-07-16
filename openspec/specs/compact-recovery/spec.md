# compact-recovery Specification

## Purpose
TBD - created by archiving change compact-recovery-prompt-carrier. Update Purpose after archive.
## Requirements
### Requirement: Post-compaction state recovery survives auto-compaction
The plugin MUST re-inject checkpointed session state into the model's context
after a context compaction, regardless of whether the compaction was automatic
or manual, on any Claude Code version that fires the `PreCompact` hook. The
recovery payload MUST include composition-chain state and, when present, the
confirmed-intent marker and non-archived OpenSpec change context. All recovery
paths MUST fail open: no recovery error may block a prompt, a session start, or
compaction itself.

#### Scenario: auto-compaction recovers at the next prompt
- **GIVEN** a session token with composition state on disk
- **AND** `pre-compact-hook.sh` has run (any trigger) and written the pending marker
- **WHEN** `compact-recovery-prompt-hook.sh` processes the next user prompt
- **THEN** its output MUST contain the compact-recovery block (composition chain and current step)
- **AND** the pending marker MUST be removed, so the following prompt emits no recovery block

#### Scenario: manual /compact recovery consumes the marker first
- **GIVEN** the pending marker exists for the session token
- **WHEN** `compact-recovery-hook.sh` runs as SessionStart(compact)
- **THEN** it MUST emit the recovery block immediately
- **AND** it MUST remove the marker
- **AND** a subsequent `compact-recovery-prompt-hook.sh` run MUST NOT emit a second recovery block

#### Scenario: extended payload carries intent and change context
- **GIVEN** a confirmed-intent marker and a non-archived OpenSpec change entry exist for the session token
- **WHEN** either recovery emitter renders
- **THEN** the output MUST contain the confirmed-intent text
- **AND** MUST contain the change slug of every non-archived change (bounded summary)

#### Scenario: degraded environments stay fail-open
- **GIVEN** cozempic is absent from PATH
- **WHEN** `pre-compact-hook.sh` runs
- **THEN** it MUST still write the pending marker and the compaction event log line and exit 0
- **AND** **GIVEN** jq is absent or state files are malformed or the token is unresolvable
- **WHEN** either recovery emitter runs
- **THEN** it MUST exit 0 without emitting a malformed block

