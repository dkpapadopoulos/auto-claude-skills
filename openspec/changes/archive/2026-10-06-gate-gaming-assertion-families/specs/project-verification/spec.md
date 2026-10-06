## ADDED Requirements

### Requirement: Net removal of unlisted assertion families is suspect

The gate-gaming check SHALL count, per file, the deleted and the added diff lines that call an assertion of a family its fixed list does not name: `assert_<name>`, `assert<Name>(` other than the listed names, and this plugin's `_record_pass` / `_record_fail`. It SHALL report a file when more such lines were deleted than added. A comment-only line and a definition of a helper MUST NOT be counted. The fixed list and its rule MUST run unchanged on the same input, and a diff they flag MUST still be flagged. A line MUST be attributed to a file by the diff's hunk structure, and MUST NOT be attributed by a line's resemblance to a file header.

#### Scenario: A deleted bash assertion

- **GIVEN** a branch diff that deletes an `assert_equals` line from a test file and adds none
- **WHEN** the verdict is written
- **THEN** `gate_gaming_status` MUST be `suspect`
- **AND** the hit MUST name the file and both counts

#### Scenario: An assertion edited in place

- **GIVEN** a diff that deletes one such assertion line and adds one in the same file
- **WHEN** the check runs
- **THEN** that file MUST NOT be reported

#### Scenario: An assertion commented out, and one moved to another file

- **WHEN** an assertion line is replaced by a comment, or deleted from one file and added to another
- **THEN** the file that lost it MUST be reported

#### Scenario: A source line that imitates a file header

- **GIVEN** a diff in which an added source line reads like a `+++` header naming another file, followed by deleted assertions
- **WHEN** the check runs
- **THEN** the deletions MUST be charged to the file they were deleted from

#### Scenario: A helper definition is deleted

- **WHEN** the only deleted lines are definitions such as `assert_not_empty() {`
- **THEN** the check MUST NOT report the file

### Requirement: A not-clean verdict states a remedy that can be carried out

The verdict writer SHALL record the lines the gate-gaming check flagged, at most ten, with control characters removed. When the push guard denies a push because the verification verdict for exactly the pushed commit is not clean, its text SHALL name every blocker and what clears it, and for a `suspect` result SHALL state that re-running verification cannot clear it while the diff is unchanged. That text MUST NOT contain a flagged diff line, and MUST show a gate name only when the name is a plain label; other names MUST be counted. For a verdict at any other commit, or none, the previous text SHALL stand. The decision to deny MUST NOT change.

#### Scenario: A suspect verdict at the pushed commit

- **GIVEN** a routing change whose verdict at HEAD is `suspect`
- **WHEN** a push is attempted
- **THEN** the push MUST be denied by routing governance
- **AND** the reason given to the model MUST say that re-running cannot clear it, and how many lines were flagged
- **AND** the reason MUST NOT say to run verification until it reports a clean verdict

#### Scenario: Text chosen by the branch author

- **GIVEN** a verdict whose flagged line, or whose failing gate's name, is worded as an instruction
- **WHEN** the remedy is rendered
- **THEN** that wording MUST NOT appear in it

#### Scenario: A verdict for an earlier commit

- **GIVEN** a `suspect` verdict for an ancestor of the pushed commit
- **WHEN** a push is attempted
- **THEN** the push MUST be denied with the text that asks for a verdict at this commit
