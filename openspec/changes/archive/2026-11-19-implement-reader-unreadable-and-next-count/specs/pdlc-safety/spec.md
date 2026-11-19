## ADDED Requirements

### Requirement: The IMPLEMENT shadow reader never reads an unreadable file as an empty one

When the IMPLEMENT shadow corpus or its label sidecar exists but cannot be read, `scripts/shadow-adjudicate.sh` MUST say which file is unreadable and MUST NOT report a count, a rate or a record derived from it. `--status` and `--next` MUST exit 0 with that message. `--rate-episodes` MUST print no rows, name the cause on stderr and exit 2 when the corpus is unreadable. A request to record a label MUST be refused with that cause when the corpus is unreadable.

#### Scenario: The label sidecar is unreadable

- **GIVEN** a corpus with one would-block record that the sidecar labels `false_block`, and the sidecar's mode denies reading
- **WHEN** the reader runs `--status` and `--next`
- **THEN** each says the sidecar exists but is not readable
- **AND** `--status` prints no unadjudicated count, no verdict count and no rate
- **AND** `--next` does not offer the labelled record

#### Scenario: The corpus is unreadable

- **GIVEN** a corpus whose mode denies reading
- **WHEN** the reader runs `--status`, `--next`, `--rate-episodes` and a label command
- **THEN** each says the corpus exists but is not readable
- **AND** `--rate-episodes` prints no rows and exits 2
- **AND** the label is refused without saying that the record does not exist

### Requirement: The IMPLEMENT reader's --next counts only the records it offers

When no record is outstanding, `scripts/shadow-adjudicate.sh --next` MUST state the number of adjudicated records as the number of records it offers from: those of the adjudicable population that would block, are not advisory-silent and carry a parseable `ts`. It MUST state separately how many other records of that population were never offered. When the population holds records and none is offerable, it MUST say so and MUST NOT describe the corpus as adjudicated or as having no records.

#### Scenario: One labelled record among records that are never offered

- **GIVEN** a corpus with one labelled would-block record, one attested record, one advisory-silent record and one record with an unparseable `ts`
- **WHEN** the reader runs `--next`
- **THEN** it reports that all 1 offerable record is adjudicated
- **AND** it reports that 3 more records were never offered

#### Scenario: No record is offerable

- **GIVEN** a corpus holding only an attested record
- **WHEN** the reader runs `--next`
- **THEN** it reports that none of the 1 record is offerable
- **AND** it does not say the records are adjudicated or that there are none yet
