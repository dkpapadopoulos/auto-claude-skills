# project-verification — Gate-Gaming Detection (delta)

## ADDED Requirements

### Requirement: Gate-Gaming Detection Before PASS

The skill SHALL inspect the working-tree diff before emitting a PASS verdict and SHALL classify a
`gate_gaming_status` of `clean` or `suspect`. A `suspect` classification SHALL downgrade the verdict
to a reported SUSPECT state and SHALL NOT be emitted as PASS. The check SHALL remain advisory (it
MUST NOT hard-block) and SHALL degrade to `clean` for ecosystems whose markers it does not match.

#### Scenario: Suite passes but assertions were deleted

- **GIVEN** the discovered gate exits 0
- **AND** the working-tree diff removes assertion lines from a test file or adds a `skip`/`xfail`/
  disabled marker
- **WHEN** the skill prepares its verdict
- **THEN** `gate_gaming_status` MUST be `suspect`
- **AND** the verdict MUST NOT be PASS
- **AND** the offending diff lines MUST be shown to the human

#### Scenario: Clean diff passes normally

- **GIVEN** the discovered gate exits 0
- **AND** the working-tree diff contains no removed assertions and no added skip/xfail/disabled markers
- **WHEN** the skill prepares its verdict
- **THEN** `gate_gaming_status` MUST be `clean`
- **AND** the verdict MAY be PASS

### Requirement: Could-Not-Verify Tri-State Evidence

The evidence file SHALL distinguish three command outcomes via `passed[]`, `failed[]`, and a new
`could_not_verify[]` array. A gate command that could not execute (missing binary, runner error,
environment break — as distinct from a test failure) SHALL be recorded in `could_not_verify[]` and
SHALL NOT be silently omitted from all three arrays.

#### Scenario: A gate command cannot run

- **GIVEN** a discovered gate command whose tool is not installed
- **WHEN** the skill runs the gate and emits evidence
- **THEN** that command MUST appear in `could_not_verify[]`
- **AND** that command MUST NOT appear in `passed[]`
- **AND** the verdict for that command MUST be `could-not-verify`, never a silent pass

### Requirement: Deploy-Gate Local-Verification Acceptance

`deploy-gate` SHALL accept a local `project-verification` evidence file as verification-of-record
only when `failed[]` is empty, `could_not_verify[]` is empty, and `gate_gaming_status` is not
`suspect`. An evidence file failing any of these conditions MUST NOT be accepted as local
verification performed.

#### Scenario: Evidence with a could-not-verify gate is not accepted

- **GIVEN** hosted CI is absent
- **AND** a fresh evidence file with empty `failed[]` but a non-empty `could_not_verify[]`
- **WHEN** `deploy-gate` evaluates local verification of record
- **THEN** it MUST NOT accept the file as verification performed
- **AND** it MUST surface that verification was incomplete

#### Scenario: Suspect evidence is not accepted

- **GIVEN** hosted CI is absent
- **AND** a fresh evidence file with empty `failed[]` and empty `could_not_verify[]` but
  `gate_gaming_status: suspect`
- **WHEN** `deploy-gate` evaluates local verification of record
- **THEN** it MUST NOT accept the file as verification performed
