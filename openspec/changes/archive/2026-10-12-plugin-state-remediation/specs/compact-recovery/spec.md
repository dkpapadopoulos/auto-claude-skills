## ADDED Requirements

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
