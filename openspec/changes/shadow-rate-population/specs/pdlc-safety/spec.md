## ADDED Requirements

### Requirement: The pre-registered rate MUST be computed over the pre-registered population

`scripts/shadow-adjudicate.sh` SHALL compute the false-block rate, its denominator, and the ≥2-repo diversity floor over episodes containing at least one `would_block: true` record, and over no other population. Records the leg did not block — those where attestation satisfied it — cannot contain a false block and MUST NOT enter the denominator.

Membership SHALL be read from the `would_block` boolean itself. It MUST NOT be inferred from `impl_evidence_kind`, which is format-frozen and describes evidence rather than rate membership, and which correlates with `would_block` in current data only incidentally.

The diversity floor is explicitly in scope: were attestation episodes able to satisfy it, the corpus could clear the ≥2-repo requirement with no false-block evidence spanning repos at all.

#### Scenario: The corpus contains attested non-blocks

- **WHEN** `--status` runs over a corpus mixing would-block and attested records
- **THEN** the rate population, the adjudicated count, the verdict counts and the repo set include only the would-block episodes

#### Scenario: An attested episode is the only one in a second repo

- **WHEN** the sole episode in a second repository is attestation-only
- **THEN** the ≥2-repo diversity floor is NOT satisfied

#### Scenario: A record the leg did not block is queued for adjudication

- **WHEN** `--next` selects the next record to adjudicate
- **THEN** it never offers a record whose `would_block` is absent, non-boolean, or false

### Requirement: The excluded population MUST remain visible, not merely excluded

Attestation-only episodes SHALL be reported on their own line, labelled as an observation. They exist because a prior change added them specifically to measure how often attestation rather than implementation work satisfied the leg; excluding them from the rate MUST NOT remove them from the report.

Consequently the population filter MUST NOT be applied inside the shared episode-grouping function, whose output other reporting depends on.

#### Scenario: A reader wants both numbers

- **WHEN** `--status` runs
- **THEN** the total episode count, the would-block population and the attestation-only population are each reported separately, so neither can be mistaken for the other

### Requirement: An episode's population membership MUST NOT depend on record order

An episode containing both a would-block record and a non-blocking one SHALL be classified as a would-block episode. The rule is "any record would have blocked", chosen because episode identity is anchored on the earliest record: a rule reading only the anchor would classify the same episode differently depending on the order records arrived.

A `would_block` field that is absent or not boolean SHALL be reported as an exclusion and MUST NOT be coerced to false, since folding an unknown into the non-blocking population hides it in the bucket that biases toward clearing the flip.

#### Scenario: A mixed episode is grouped in either order

- **WHEN** an episode holds a would-block record and an attested record, in either arrival order
- **THEN** it is classified as a would-block episode in both cases

#### Scenario: A record omits would_block

- **WHEN** a record has no `would_block` field, or a non-boolean one
- **THEN** it is reported as excluded and is counted as neither would-block nor attestation-only
