# design-foundations

## ADDED Requirements

### Requirement: A brief the seed was amended against MUST carry a contamination map

A comparison of the design seed against a no-seed arm that uses a task brief
whose scoring results were used to amend the seed SHALL record, before either
arm runs, a map from each amendment to every scored dimension it could affect.
Every dimension on that map SHALL be declared contaminated and MUST NOT be
reported as evidence for the seed.

#### Scenario: The pilot's brief is reused

- **GIVEN** a registration that names the brief used by the pilot that closed
  on 2026-09-24
- **WHEN** the registration is reviewed before launch
- **THEN** it MUST contain a map from the amendment made in #299 to the
  dimensions it could affect
- **AND** that map MUST include the dimension scoring identification of
  unresolved values

### Requirement: Exposure to the seed MUST be controlled and checked from outside

Each party that chooses the task, specifies what is measured, or approves a
measure SHALL receive a closed, listed set of inputs. The registration SHALL
state, for each such party, what it was given and which capabilities it was
denied. The check that this held SHALL be made from outside the party, and MUST
NOT rest on an instruction to the party or on the party's own report.

The registration SHALL NOT describe a party as having no knowledge of the seed.
It MAY describe the party's exposure as controlled.

#### Scenario: A party that receives one text package

- **GIVEN** a frozen package to be sent to a party
- **WHEN** the package is checked before it is sent
- **THEN** a manifest MUST list every item in it
- **AND** a scan of the package for the seed's name, its file names and the
  earlier comparison's documents MUST find none
- **AND** the search terms used MUST be recorded

#### Scenario: A party that runs in a restricted session

- **GIVEN** the launch configuration a party will run under
- **WHEN** that configuration is checked before use
- **THEN** a read inside the permitted directory MUST succeed
- **AND** a read outside it MUST fail through each file tool and each shell
  route the session has
- **AND** a read through a symlink that points outside MUST fail
- **AND** the launch payload, captured by the launcher, MUST NOT contain the
  seed's name or its file names
- **AND** the list of plugins, hooks and instruction files the session loaded
  MUST be captured

#### Scenario: The configuration checked is the configuration launched

- **GIVEN** a launch configuration that passed its check
- **WHEN** the party is launched
- **THEN** the launch MUST use a configuration whose hash equals the one that
  was checked

#### Scenario: A check does not pass

- **GIVEN** a package or a launch configuration for which any required result
  is wrong
- **WHEN** the stage is about to start
- **THEN** the stage MUST NOT run

### Requirement: A measure MUST be specified by one party and approved by another

For each construct measured by a script, the party that specifies the construct
SHALL state its direction, its scope, how elements are grouped, which ways of
computing it are acceptable, and what size of difference matters. The code
SHALL be approved against that specification by a party that did not write it
and did not write the specification.

A construct SHALL have one vote in a pair's outcome, however many measures it
has.

#### Scenario: A measure is validated before freeze

- **GIVEN** a measure, and pages specified by the approving party
- **WHEN** the measure is run on two pages that look the same and differ in
  markup
- **THEN** it MUST score them within its rendering-noise tolerance of each
  other
- **AND WHEN** it is run on a page whose content is hidden, clipped or covered
- **THEN** it MUST NOT credit that content

#### Scenario: A difference is counted

- **GIVEN** two pages in a pair and one construct
- **WHEN** the pages' scores on that construct are compared
- **THEN** the pair differs on it only if the difference exceeds the
  rendering-noise tolerance AND the size the specifying party said matters

#### Scenario: A construct has no working measure

- **GIVEN** a specified construct for which no measure was approved and no
  anchors were written
- **WHEN** the instrument is frozen
- **THEN** the construct MUST appear in the record as not measured
- **AND** it MUST NOT be scored

### Requirement: Every decision that shapes the instrument MUST be recorded with its maker

The registration SHALL list each decision that determines what is measured or
what is built, the party that made it, and the party that checked it. Where a
party that has read the seed made such a decision, the registration SHALL say
so.

#### Scenario: The author wrote the code for a measure

- **GIVEN** a frozen instrument
- **WHEN** its record is inspected
- **THEN** it MUST name the author as the writer of each measure's code
- **AND** it MUST name the party that approved each one
- **AND** it MUST preserve the specification each was approved against

#### Scenario: A construct was cut

- **GIVEN** a specified construct that does not appear in the frozen instrument
- **WHEN** the record is inspected
- **THEN** it MUST state who cut it and why

### Requirement: A result MUST pass an interpretation gate or be reported as inconclusive

The registration SHALL fix, before any arm runs, the checks a result has to
pass to be read as evidence about improvement. A result that fails a check
SHALL be reported as inconclusive about improvement, and its measurements SHALL
still be reported.

Pairs decided by a fidelity failure SHALL be reported separately from pairs
decided on constructs.

#### Scenario: Every arm falls within tolerance

- **GIVEN** a completed comparison in which, on every construct, both arms'
  scores fall within both thresholds in every pair
- **WHEN** the result is written up
- **THEN** it MUST be reported as inconclusive about improvement

#### Scenario: A planned pair is missing

- **GIVEN** a registration of five pairs and a record holding four
- **WHEN** the result is written up
- **THEN** it MUST be reported as inconclusive about improvement
- **AND** the record MUST say what happened to the fifth

#### Scenario: The result is summarised

- **GIVEN** a completed comparison
- **WHEN** the result is written up
- **THEN** it MAY state how many pairs favoured each arm
- **AND** it MUST NOT name an overall winner

### Requirement: Each arm's launch evidence MUST be preserved

For each arm, the comparison SHALL preserve the launch payload captured by the
launcher and the arm's full transcript.

#### Scenario: A question arises later about what an arm was shown

- **GIVEN** a completed comparison
- **WHEN** someone asks whether an arm's context named the seed
- **THEN** the preserved launch payload MUST be sufficient to answer
