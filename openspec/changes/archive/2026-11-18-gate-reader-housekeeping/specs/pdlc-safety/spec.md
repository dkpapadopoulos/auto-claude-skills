## ADDED Requirements

### Requirement: A reviewed commit is evidence only as a full object name

`review_sha_covers` and `review_reviewer_returned_sha` (`hooks/lib/credited-skills.sh`) MUST treat a recorded sha as usable only when it is 40 or 64 lowercase hexadecimal characters. An abbreviated sha MUST be reported as cannot-check by `review_sha_covers` and MUST NOT be returned by `review_reviewer_returned_sha`, even when it resolves unambiguously to a covering commit.

#### Scenario: An abbreviated sha that resolves to a covering commit

- **GIVEN** a commit A that is an ancestor of the subject with no material source change since
- **WHEN** `review_sha_covers` is given the first 7, or the first 39, characters of A
- **THEN** it returns 2 (cannot check)
- **AND** given all 40 characters it returns 0

#### Scenario: A sha256 repository

- **GIVEN** a repository created with the sha256 object format and a commit A covering the subject
- **WHEN** `review_sha_covers` is given A's 64-character name
- **THEN** it returns 0

### Requirement: Reading-side HEAD is never the word HEAD

The push guard (`_HEAD_SHA`, `_subj_head`), `scripts/gate-status.sh` and `review_verdict_delta_files` MUST resolve HEAD with `git rev-parse --verify --quiet HEAD`, so that a repository with no commits yields an empty value and not the word `HEAD`. The guard's decision for a push from such a repository MUST be what it was before this requirement.

#### Scenario: A push from a repository with no commits

- **GIVEN** a repository with no commits and a chain holding REVIEW and VERIFY with neither completed
- **WHEN** the agent runs `git push`
- **THEN** the push gate denies it
- **AND** no message names the word `HEAD` as a commit

#### Scenario: Ledger milestones recorded in a repository with no commits

- **GIVEN** a repository with no commits whose branch ledger holds REVIEW and VERIFY milestones, recorded with no sha
- **WHEN** the agent runs `git push`
- **THEN** the push gate's decision is what it was before this requirement (no deny)
- **AND** it does not print the advisory that the milestone is stale because "HEAD is HEAD"

### Requirement: The capture replay writes no shadow record

When the push guard runs as the diagnostic capture's replay (`PUSH_GATE_CAPTURE_REPLAY=1`), it MUST NOT append a REVIEW or an IMPLEMENT shadow record. A live evaluation of the same state MUST still append one.

#### Scenario: A push denied after the REVIEW record is written

- **GIVEN** a chain with REVIEW credited, no review verdict, and VERIFY missing
- **WHEN** the agent runs `git push` once and the capture replays the guard
- **THEN** the push is denied, the capture log records a replay that denied too, and the REVIEW shadow log holds exactly one record for that push

#### Scenario: The IMPLEMENT record sites under the replay

- **GIVEN** a state in which a live evaluation appends an attested, or a would-block, IMPLEMENT record
- **WHEN** the guard is run on it with the replay variables set
- **THEN** no record is appended

### Requirement: The REVIEW reader announces a sidecar it cannot use

`scripts/review-shadow-adjudicate.sh --status` MUST say that the label sidecar is not readable when it exists and cannot be read, and MUST count that as uncountable. It MUST count a sidecar line that parses to a JSON value other than an object as unparseable. `--help` as the first argument MUST print the usage and exit 0 even when the producer lib cannot be loaded; every other command MUST still refuse there.

#### Scenario: An unreadable sidecar

- **GIVEN** a corpus with one record and a label sidecar with mode 000
- **WHEN** `--status` runs as a non-root user
- **THEN** the output says the sidecar exists but is NOT READABLE and reports 1 uncountable

#### Scenario: Non-object sidecar lines

- **GIVEN** a sidecar holding one label and the lines `[1]` and `"x"`
- **WHEN** `--status` runs
- **THEN** it reports 2 unparseable label lines

#### Scenario: Help without the producer lib

- **GIVEN** a copy of the script with no `hooks/lib` beside it
- **WHEN** it is run with `--help`, and then with `--status`
- **THEN** the first prints the usage and exits 0, and the second exits 2
