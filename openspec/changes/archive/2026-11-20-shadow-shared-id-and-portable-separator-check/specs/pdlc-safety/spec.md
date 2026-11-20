## ADDED Requirements

### Requirement: A label for a record_id on both sides of the separator is counted once

When a record at or after the plugin-version separator and a record the separator excludes carry the same `record_id`, `scripts/shadow-adjudicate.sh` and `scripts/review-shadow-adjudicate.sh` MUST count a label for that id with the countable record only. They MUST NOT include it in the number of labels reported for pre-separator records. A label for an id that only excluded records carry MUST still be reported there.

#### Scenario: One id on both sides, labelled false_block

- **GIVEN** a corpus with a countable record and a pre-separator record that share a `record_id`, in either order, and a human `false_block` label for that id
- **WHEN** either reader runs `--status`
- **THEN** it counts 1 `false_block`
- **AND** it reports no label on a pre-separator record

### Requirement: The separator is validated the same way in every shell that can source the lib

`shadow_acs_sep_json` in `hooks/lib/shadow-corpus.sh` MUST print nothing and return 1 unless the separator is three dot-separated components, each `0` or one to nine digits with no leading zero. `hooks/lib/shadow-corpus.sh` MUST load, and this MUST hold, under bash, dash, zsh and sh.

#### Scenario: A two-part separator under zsh and dash

- **GIVEN** the lib sourced under zsh, and under dash, with the separator set to `3.103`
- **WHEN** `shadow_acs_sep_json` is called with matching predicates
- **THEN** it prints nothing and returns 1 in both shells
