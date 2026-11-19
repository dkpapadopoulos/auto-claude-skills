## ADDED Requirements

### Requirement: The IMPLEMENT shadow reader reads past a malformed line and withholds the rate over a damaged sidecar

Every read of the IMPLEMENT shadow corpus and of its label sidecar in `scripts/shadow-adjudicate.sh` MUST skip a line that is not a JSON object and continue with the lines after it. `--status` MUST report the number of sidecar lines that hold no readable label, and while that number is above zero it MUST NOT print a rate, a band or a worst case, and MUST say that the rate cannot be checked.

#### Scenario: A truncated sidecar line ahead of a false_block label

- **GIVEN** 30 labelled would-block episodes across two repositories, one of them `false_block`, and a truncated line in the sidecar immediately before the `false_block` label
- **WHEN** the reader runs `--status` and `--next`
- **THEN** `--status` counts 1 `false_block` and 0 unadjudicated episodes
- **AND** it reports 1 unparseable label and prints `cannot check` in place of the rate and band
- **AND** `--next` offers no record

#### Scenario: A truncated corpus line ahead of a record

- **GIVEN** a corpus whose first line is truncated and whose second line is a would-block record
- **WHEN** `--next` offers that record and a label is recorded for it
- **THEN** the label is accepted
- **AND** `--status` counts the episode as would-block with its label
