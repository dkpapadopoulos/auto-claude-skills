# design-foundations

## ADDED Requirements

### Requirement: A replication MUST NOT reuse a brief the seed was amended against

A comparison of the design seed against a no-seed arm SHALL NOT use a task
brief whose scoring results were used to amend the seed, unless every dimension
the amendment addresses is declared contaminated before either arm runs.

#### Scenario: The pilot's brief is reused

- **GIVEN** a registration that names the brief used by the pilot that closed
  on 2026-09-24
- **WHEN** the registration is reviewed before launch
- **THEN** it MUST declare the dimension scoring identification of unresolved
  values as contaminated, and MUST NOT report that dimension as evidence for
  the seed

### Requirement: Blind parties MUST be blind by construction

The party that chooses the task and the party that derives what is measured
SHALL have no access to the design seed, to this repository, to the documents
of any earlier comparison, or to any earlier comparison's results. That SHALL
be enforced by what the party is sent or by its launch configuration, and MUST
NOT rest on an instruction to the party.

#### Scenario: The launch configuration is checked before use

- **GIVEN** the launch configuration a blind party will run under
- **WHEN** a probe is run under that same configuration
- **THEN** a read of a file inside the permitted directory MUST succeed
- **AND** a read of the seed's styleguide by absolute path MUST fail
- **AND** a read of a file placed outside the permitted directory MUST fail
- **AND** the probe's initial prompt context MUST NOT name the design seed

#### Scenario: The check cannot be made to pass

- **GIVEN** a launch configuration under which any of those four results is
  wrong
- **WHEN** the stage is about to start
- **THEN** the stage MUST NOT run under the description "blind"

### Requirement: Presentation properties MUST be measured from the rendered page

A property concerning typography, colour, spacing, alignment or consistency
SHALL be computed by a script from the rendered page. A judge SHALL score such
a property only when it carries a written anchor for each score. A property
with neither SHALL be reported as not measured.

#### Scenario: A measure is calibrated in both directions

- **GIVEN** a measure for one property, and two pages built before any arm
  exists, one that has the property and one that lacks it
- **WHEN** the measure is run on both pages
- **THEN** it MUST score the first above the second by more than its registered
  tolerance

#### Scenario: A property cannot be measured and has no anchors

- **GIVEN** a derived property for which no measure was built and no anchors
  were written
- **WHEN** the instrument is frozen
- **THEN** the property MUST appear in the record as not measured
- **AND** it MUST NOT be scored

### Requirement: The party that is not blind MUST NOT choose what is measured

The author of the design seed, and any party that has read it, SHALL NOT choose
the task, the stored report the fixture is built from, the states the fixture
exercises, the properties measured, or which direction of a property is better.

#### Scenario: The fixture's contents are chosen

- **GIVEN** a fixture built for a comparison
- **WHEN** its provenance is inspected
- **THEN** the record MUST name the blind party that chose the stored report
  and the states it exercises
