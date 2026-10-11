## ADDED Requirements

### Requirement: The prompt carrier is a measured backstop

The prompt-carrier hook's documented premise SHALL state that `SessionStart(compact)` fires for most auto compactions and that the carrier covers the remainder, with the measured pairing counts. `scripts/compaction-pairing.sh` SHALL report, per month, auto and manual compactions, SessionStart recoveries and carrier recoveries, and list unpaired compactions; it MUST exit 0 when every compaction is paired, 1 when any is unpaired, and 3 when the log is missing or empty.

#### Scenario: Fully paired month

- **WHEN** the log holds 11 auto compactions and 11 SessionStart recoveries
- **THEN** the reader exits 0 and lists no unpaired compaction

#### Scenario: One unpaired compaction

- **WHEN** the log holds a compaction with no recovery event before the next compaction
- **THEN** the reader exits 1 and prints that compaction's timestamp

#### Scenario: Empty or missing log

- **WHEN** the log file is empty or absent
- **THEN** the reader exits 3 and prints a cannot-check message, never "paired"
