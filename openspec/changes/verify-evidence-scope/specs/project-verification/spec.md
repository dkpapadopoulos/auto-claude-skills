# project-verification: a clean verdict reports a check

## ADDED Requirements

### Requirement: A clean verdict reports at least one check

A verification verdict MUST be treated as clean only when the artifact is
exactly one JSON object, its `failed` and `could_not_verify` fields are absent
or empty arrays, its `passed` field is an array whose entries are all strings
with at least one entry containing a non-whitespace character, and its
`gate_gaming_status` is `clean`. This is a requirement that a check was
REPORTED. It MUST NOT be described as showing that the check ran, or as saying
who wrote the record: the artifact is workflow evidence an agent can write.

Both supported writers MUST produce records this accepts: the deterministic
writer `scripts/verify-and-record.sh`, and the hand-authored shape documented
in the `project-verification` skill.

When a verdict is not clean, the remedy text MUST name every blocker that
applies to that one record, including a record that is not one well-formed
verdict and a record that reports no check.

#### Scenario: A record that reports no check

- **GIVEN** a verdict artifact holding only `sha` and `gate_gaming_status: "clean"`
- **WHEN** a gate leg asks whether the verdict is clean
- **THEN** the answer MUST be no
- **AND** the remedy MUST say the verdict reports no check and to verify again

#### Scenario: An entry that is not a check name

- **GIVEN** a verdict whose `passed` holds a non-string entry, or only whitespace
- **WHEN** a gate leg asks whether the verdict is clean
- **THEN** the answer MUST be no

#### Scenario: The supported writers

- **GIVEN** a verdict written by `scripts/verify-and-record.sh` for a passing gate
- **OR** a verdict in the hand-authored shape with one or more `passed` names and nothing failed or unverifiable
- **WHEN** a gate leg asks whether the verdict is clean
- **THEN** the answer MUST be yes

#### Scenario: A record that is not one well-formed verdict

- **GIVEN** an artifact holding two JSON documents, a non-object, or a result field of the wrong type
- **WHEN** the remedy is rendered
- **THEN** it MUST say the record is not one well-formed verdict and to verify again

#### Scenario: More than one blocker

- **GIVEN** a verdict that is `suspect` and reports no check
- **WHEN** the remedy is rendered
- **THEN** it MUST carry the sentence for each of the two blockers
