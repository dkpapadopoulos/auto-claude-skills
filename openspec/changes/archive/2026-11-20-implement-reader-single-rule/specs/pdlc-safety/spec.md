## MODIFIED Requirements

### Requirement: The IMPLEMENT shadow reader reads past a malformed line and withholds the rate over a damaged sidecar or corpus

Every read of the IMPLEMENT shadow corpus and of its label sidecar in `scripts/shadow-adjudicate.sh` MUST skip a line that is not a JSON object and continue with the lines after it. `--status` MUST report the number of sidecar lines that hold no label, where a label is a JSON object with a string `record_id` and a `verdict` of `true_catch`, `false_block` or `unknown`; such a line MUST NOT supersede an earlier label for the same record. `--status` MUST also report the number of labels naming a `record_id` the corpus does not hold. While any of these is above zero, `--status` MUST NOT print a rate, a band or a worst case, and MUST say that the rate cannot be checked: sidecar lines that hold no label, labels naming an absent record, unparseable corpus lines (counted bytewise, so a line of invalid bytes is a line), adjudicable records whose `ts` cannot be placed, and episodes excluded for a malformed `would_block`. A line of whitespace only is not a line for either count.

`--status` MUST also withhold on two subtractions that name no cause, and on a human label that a later line replaced. First, every record that a valid human-claimed label names MUST be a member of a would-block episode for which the readout found a label; a record that is not MUST be reported under `other-predicate labels` when it is of another predicate version, under `pre-separator labels` when the separator excludes it, under `orphan labels` when the corpus does not hold it, and otherwise under `labels outside the rate`, which MUST withhold the rate. `other-predicate labels` and `pre-separator labels` MUST NOT withhold it. Second, the adjudicable records with a non-empty `record_id` and a placeable `ts` MUST be the records in the episodes, compared by `record_id`; each record on one side only MUST be counted under `unplaced records`, which MUST withhold the rate. `--status` MUST also count, under `superseded human labels`, each record of the adjudicable population whose latest label is not human-claimed while an earlier label for it was, and MUST withhold the rate while that count is above zero. Labels MUST be matched to records as strings. A `ts` is placeable only when it is a string that matches the timestamp form in full, and a record whose `ts` is anything else MUST be counted as a malformed `ts`.

#### Scenario: A truncated sidecar line ahead of a false_block label

- **GIVEN** 30 labelled would-block episodes across two repositories, one of them `false_block`, and a truncated line in the sidecar immediately before the `false_block` label
- **WHEN** the reader runs `--status` and `--next`
- **THEN** `--status` counts 1 `false_block` and 0 unadjudicated episodes
- **AND** it reports 1 unparseable label and prints `cannot check` in place of the rate and band
- **AND** `--next` offers no record

#### Scenario: A sidecar object with no verdict after a false_block label

- **GIVEN** 30 labelled would-block episodes, one of them `false_block`, and a later sidecar line for the same record that is an object with no `verdict`
- **WHEN** the reader runs `--status`
- **THEN** it still counts 1 `false_block`
- **AND** it reports 1 unparseable label and prints `cannot check` in place of the rate and band

#### Scenario: The false_block's corpus record cannot be placed

- **GIVEN** 31 labelled would-block episodes, one of them `false_block`, whose corpus line is truncated or whose `ts` is not a timestamp
- **WHEN** the reader runs `--status`
- **THEN** it reports the unparseable line or the malformed `ts`
- **AND** it prints `cannot check` in place of the rate and band

#### Scenario: The false_block's record is gone or its would_block is malformed

- **GIVEN** 31 labelled would-block episodes, one of them `false_block`, whose corpus line has been removed, or whose `would_block` is no longer a boolean
- **WHEN** the reader runs `--status`
- **THEN** it reports 1 orphan label, or 1 malformed `would_block`
- **AND** it prints `cannot check` in place of the rate and band

#### Scenario: A truncated corpus line ahead of a record

- **GIVEN** a corpus whose first line is truncated and whose second line is a would-block record
- **WHEN** `--next` offers that record and a label is recorded for it
- **THEN** the label is accepted
- **AND** `--status` counts the episode as would-block with its label

#### Scenario: The false_block's record stops being a would-block record

- **GIVEN** 31 labelled would-block episodes, one of them `false_block`, whose corpus record is edited so that `would_block` is false or `advisory_emitted` is false
- **WHEN** the reader runs `--status`
- **THEN** it reports 1 label outside the rate and no orphan label
- **AND** it prints `cannot check` in place of the rate and band

#### Scenario: The false_block's record is moved to another predicate version

- **GIVEN** 31 labelled would-block episodes, one of them `false_block`, whose corpus record is edited to the previous `predicate_version`, or to the current one written as a JSON string
- **WHEN** the reader runs `--status`
- **THEN** it reports 1 other-predicate label
- **AND** it prints the rate over the remaining 30 episodes

#### Scenario: Two record ids that are equal as numbers

- **GIVEN** records `100` and `1e2` in separate episodes, labelled `true_catch` and `false_block` by a human
- **WHEN** the reader runs `--status`
- **THEN** it counts one `false_block` and one `true_catch`

#### Scenario: A record no episode holds

- **GIVEN** 30 labelled would-block episodes and one more adjudicable record whose `branch` is a JSON object
- **WHEN** the reader runs `--status`
- **THEN** it reports 1 unplaced record
- **AND** it prints `cannot check` in place of the rate and band

#### Scenario: An agent relabels a record a human labelled false_block

- **GIVEN** 30 labelled would-block episodes, one of them a human `false_block`, and a later agent-claimed `true_catch` for the same record
- **WHEN** the reader runs `--status`
- **THEN** it reports 1 superseded human label and prints `cannot check` in place of the rate and band
- **AND** after a human labels the record again, the rate prints

#### Scenario: Whitespace-only lines

- **GIVEN** 30 labelled would-block episodes, with blank and whitespace-only lines appended to the corpus and to the sidecar
- **WHEN** the reader runs `--status`
- **THEN** it reports no unparseable line and no unparseable label
- **AND** it prints the rate


## ADDED Requirements

### Requirement: The IMPLEMENT reader refuses a label on a record it never offers

`scripts/shadow-adjudicate.sh` MUST refuse to record a label for a record that `--next` never offers: one whose `would_block` is not the boolean true, whose `advisory_emitted` is the boolean false, or whose `ts` is not placeable. It MUST decide the record's predicate version by JSON value, so a `predicate_version` written as a string is another predicate. A refusal MUST say the record is not adjudicable, exit 1 and write nothing.

#### Scenario: An attested record

- **GIVEN** a corpus with one attested record and one would-block record
- **WHEN** a label is requested for each
- **THEN** the label for the attested record is refused as not adjudicable and the sidecar is unchanged
- **AND** the label for the would-block record is recorded
