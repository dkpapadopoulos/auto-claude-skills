## ADDED Requirements

### Requirement: A label for a record_id on both sides of the separator is counted once

When a record at or after the plugin-version separator and a record the separator excludes carry the same `record_id`, `scripts/shadow-adjudicate.sh` and `scripts/review-shadow-adjudicate.sh` MUST read a label for that id against the record at or after the separator. They MUST NOT include it in the number of labels reported as not counted for pre-separator records, and MUST report it on a separate line as a label for a shared id, whether or not the rate counts it. A label for an id that only excluded records carry MUST still be reported with the pre-separator labels.

#### Scenario: One id on both sides, labelled false_block

- **GIVEN** a corpus with a countable record and a pre-separator record that share a `record_id`, in either order, and a human `false_block` label for that id
- **WHEN** either reader runs `--status`
- **THEN** it counts 1 `false_block`
- **AND** it reports no label on a pre-separator record as not counted
- **AND** it reports 1 label for a shared id

#### Scenario: The later record is outside the rate

- **GIVEN** a pre-separator record and a later record with the same `record_id`, where the later record would not block, and a human `false_block` label for that id
- **WHEN** the REVIEW reader runs `--status`
- **THEN** it counts 0 `false_block`
- **AND** it still reports 1 label for a shared id

### Requirement: The separator is validated the same way in every shell that can source the lib

`shadow_acs_sep_json` in `hooks/lib/shadow-corpus.sh` MUST print nothing and return 1 unless the separator is three dot-separated components, each `0` or one to nine digits with no leading zero. `hooks/lib/shadow-corpus.sh` MUST load, and this MUST hold, under bash, dash, zsh and sh.

#### Scenario: A two-part separator under zsh and dash

- **GIVEN** the lib sourced under zsh, and under dash, with the separator set to `3.103`
- **WHEN** `shadow_acs_sep_json` is called with matching predicates
- **THEN** it prints nothing and returns 1 in both shells
