## ADDED Requirements

### Requirement: The shadow readers do not pool across the plugin-version separator

`scripts/review-shadow-adjudicate.sh` (at REVIEW predicate version 3) and `scripts/shadow-adjudicate.sh` (at IMPLEMENT predicate version 6) MUST leave out of every population they report a record of that predicate version whose `acs_version` is below 3.103.1, or is absent or not a `<n>.<n>.<n>` string. The populations are `--status`, `--rate-episodes`, `--next` and, for the REVIEW reader, `--evidence-miss`. Versions MUST be compared per component as numbers. Each reader MUST report the excluded records with their cause and a count, MUST refuse to record a label for one, and MUST refuse to run when `hooks/lib/shadow-corpus.sh` does not supply the rule. At any other adjudicable predicate version the separator MUST exclude nothing.

#### Scenario: Records on both sides of the separator

- **GIVEN** a corpus of would-block records at the leg's separator predicate stamped 3.103.1, 3.104.0, 3.103.0 and 3.99.9, one with no `acs_version` and one with an empty one
- **WHEN** the reader runs `--status` and `--rate-episodes`
- **THEN** only the records stamped 3.103.1 and 3.104.0 form episodes
- **AND** `--status` reports four pre-separator records, two below the separator and two with no usable stamp

#### Scenario: Labelling an excluded record

- **GIVEN** a record at the separator predicate stamped 3.99.9
- **WHEN** a label is recorded for it
- **THEN** the reader exits non-zero, names the separator as the cause, and writes nothing to the sidecar

#### Scenario: A corpus holding only excluded records

- **GIVEN** a corpus whose only record of the adjudicable predicate is stamped below the separator
- **WHEN** the reader runs `--next`
- **THEN** it says nothing is adjudicable and names the excluded record and its cause

#### Scenario: Another predicate version

- **GIVEN** a producer whose predicate version is not the one the separator names, and records of that version with no stamp and with a stamp below 3.103.1
- **WHEN** the reader runs `--status`
- **THEN** every such record forms an episode and no pre-separator line is printed

### Requirement: The capture replay writes no push-implement log line

When the push guard runs as the diagnostic capture's replay (`PUSH_GATE_CAPTURE_REPLAY=1`), it MUST NOT append the `push-implement` line to the phase-gate log. A live evaluation of the same state MUST still append one.

#### Scenario: A would-block push under the replay

- **GIVEN** a state in which a live evaluation emits the IMPLEMENT advisory
- **WHEN** the guard is run on it with the replay variables set, and then live
- **THEN** the replay appends no `push-implement` line and the live run appends one

### Requirement: The IMPLEMENT reader answers --help without its libs

`scripts/shadow-adjudicate.sh` MUST print its usage and exit 0 when `--help` or `-h` is its first argument, whether or not `hooks/lib/implement-shadow.sh` and `hooks/lib/shadow-corpus.sh` can be loaded. Every other command MUST still refuse when they cannot.

#### Scenario: Both libs absent

- **GIVEN** a copy of the script with neither lib beside it
- **WHEN** it is run with `--help`, and then with `--status`
- **THEN** the first prints the usage and exits 0, and the second exits 2
