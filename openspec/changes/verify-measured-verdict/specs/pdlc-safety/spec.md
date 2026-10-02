# pdlc-safety

## ADDED Requirements

### Requirement: VERIFY accepts only a measured verdict, advisory first

The push gate's VERIFY leg SHALL treat a verdict as satisfying evidence only when its
`discovery_source` names a value that `scripts/verify-and-record.sh` itself emits.
Values naming a hand-authored artifact SHALL NOT satisfy it. The leg SHALL be
advisory-only until the pre-registered decision rule in `design.md` is met, and SHALL
never emit a `permissionDecision`.

#### Scenario: Invoking the skill and executing nothing no longer reads as verified

- **GIVEN** an active chain with REVIEW credited and `verification-before-completion` in `.completed`
- **AND** no verdict artifact covering HEAD
- **WHEN** the VERIFY leg evaluates a `git push`
- **THEN** it SHALL record a would-block shadow record
- **AND** it SHALL NOT emit a `permissionDecision` while advisory

#### Scenario: A hand-authored ladder verdict is recorded as an explained would-block

- **GIVEN** a clean verdict covering HEAD whose `discovery_source` is `claude-md-commands`
- **WHEN** the VERIFY leg evaluates a `git push`
- **THEN** the shadow record SHALL classify the would-block as `explained_ladder`
- **AND** the push SHALL proceed unchanged

#### Scenario: A measured verdict satisfies the leg silently

- **GIVEN** a clean verdict covering HEAD whose `discovery_source` is `verify-yml`
- **WHEN** the VERIFY leg evaluates a `git push`
- **THEN** it SHALL add no advisory and write no shadow record

#### Scenario: An unreadable verdict is not counted against the rate

- **GIVEN** a verdict artifact that exists but does not parse, or omits `discovery_source`
- **WHEN** the VERIFY leg evaluates a `git push`
- **THEN** the shadow record SHALL classify it `cannot_check`, never `unexplained`
