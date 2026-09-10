# Spec delta: pdlc-safety — review authorship provenance

## ADDED Requirements

### Requirement: The review verdict MUST record whether the review was independent

The review verdict artifact MUST record an `independence` field with one of
exactly three values: `self-authored`, `independent`, or `unknown`.

`self-authored` MUST be recorded when the caller declares that the reviewing
context authored the diff under review, and MUST take precedence over an
observed or imported dispatch — a witnessed dispatch cannot refute the
declaration. `independent` MUST be recorded only when a dispatch was observed
or a pull-request review was imported and no self-authorship was declared. Every
other case MUST record `unknown`; absence of a signal MUST NOT be recorded as
`independent`.

`independence` MUST remain provenance. It MUST NOT, alone or collapsed with any
other field, act as a deny predicate.

`schema_version` MUST be incremented to 3. `predicate_version` MUST NOT change:
this adds a descriptive field and alters no fire condition, so existing records
remain poolable and no pre-registered observation horizon is restarted.

#### Scenario: A declared self-review is recorded as such

- **GIVEN** a context that authored the diff it is reviewing
- **WHEN** the verdict is recorded with the self-authorship flag
- **THEN** `independence` is `self-authored`
- **AND** it is `self-authored` even when a reviewer dispatch was observed

#### Scenario: An observed dispatch with no declaration is independent

- **GIVEN** a reviewer subagent dispatch recorded for this branch
- **WHEN** the verdict is recorded without the self-authorship flag
- **THEN** `independence` is `independent`

#### Scenario: No signal is not an independence claim

- **GIVEN** no observed dispatch, no imported pull-request review, and no
  self-authorship declaration
- **WHEN** the verdict is recorded
- **THEN** `independence` is `unknown`

#### Scenario: The field never changes a gate decision

- **GIVEN** two otherwise identical clean verdicts covering HEAD
- **WHEN** one records `independence: "independent"` and the other
  `independence: "self-authored"`
- **THEN** the push gate's output MUST be identical for both
