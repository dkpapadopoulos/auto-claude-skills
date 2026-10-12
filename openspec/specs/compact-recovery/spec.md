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

### Requirement: Recovery text separates confirmed steps from assumed ones

The compaction-recovery text MUST list under "Completed:" only the steps in the composition state's `.completed`. When `.assumed` is a non-empty array it MUST list those steps on a separate line that says they were not invoked and are not evidence. A missing or non-array `.assumed` MUST be treated as empty.

#### Scenario: A session whose steps were only assumed

- **GIVEN** composition state in which one step is in `.completed` and another only in `.assumed`
- **WHEN** the recovery text is rendered
- **THEN** the "Completed:" line names the first step and not the second
- **AND** a separate line names the second step and states it was not invoked

### Requirement: The prompt carrier is a measured backstop

The prompt-carrier hook's documented premise SHALL state that `SessionStart(compact)` fires for most auto compactions and that the carrier covers the remainder, with the measured pairing counts. `scripts/compaction-pairing.sh` SHALL report, per month, auto and manual compactions, SessionStart recoveries and carrier recoveries, and SHALL list unpaired compactions, compactions still open at the end of the log (pending), SessionStart recoveries with no logged compaction (stray, kept out of the count) and lines of no known shape (unrecognised). A carrier recovery, which logs no session path, SHALL close the OLDEST open compaction. The reader MUST exit 0 when every compaction is paired and every line is recognised, 1 when any compaction is unpaired or any line is unrecognised, and 3 when the log is missing or empty or holds no recognised compaction; it MUST NOT report "paired" over zero compactions. The carrier's retirement rule SHALL be stated identically in both hooks, the reader and `CLAUDE.md`: three consecutive months with `carrier=0` AND exit 0 with zero pending, because `carrier=` is a lower bound on SessionStart misses that can also overcount.

#### Scenario: Fully paired month

- **WHEN** the log holds 11 auto compactions and 11 SessionStart recoveries
- **THEN** the reader exits 0 and lists no unpaired compaction

#### Scenario: One unpaired compaction

- **WHEN** the log holds a compaction with no recovery event before the next compaction
- **THEN** the reader exits 1 and prints that compaction's timestamp

#### Scenario: Empty, missing or unrecognisable log

- **WHEN** the log file is empty or absent, or no line in it is a recognised compaction
- **THEN** the reader exits 3 and prints a cannot-check message, never "paired"

#### Scenario: Two sessions open when a carrier recovery arrives

- **WHEN** two compactions from different sessions are open, a carrier recovery is logged, and then a SessionStart recovery for the newer session
- **THEN** the carrier closes the older compaction, the SessionStart recovery closes the newer one, and the reader exits 0 with zero pending

