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

#### Scenario: A repo that declares a non-local substrate is out of scope

- **GIVEN** a pushed commit whose `.verify.yml` declares a substrate other than `local`
- **WHEN** the VERIFY leg evaluates a `git push`
- **THEN** it SHALL add no advisory and write no shadow record
- **AND** the declaration SHALL be read from the pushed commit, not the working tree

### Requirement: The deny-flip is decided on human-labelled false blocks

The shadow corpus reader SHALL count only episodes that contain a would-block
record, SHALL require a human label on every such episode, and SHALL report the
decision rule as met only at 29 or more would-block episodes with zero false
blocks, zero unresolved episodes, and true catches in at least two repositories.
It SHALL NOT report the rule as met while any record or label it cannot place
is present. The reader SHALL NOT emit a gate decision.

#### Scenario: An episode the leg could not check is never evidence

- **GIVEN** a corpus of `cannot_check` episodes in one repository and one would-block episode in another
- **WHEN** the reader reports status
- **THEN** only the would-block episode SHALL count toward `n` and toward repository diversity

#### Scenario: A true catch counts for the rule, not against it

- **GIVEN** 29 would-block episodes across two repositories, including `unexplained` ones
- **AND** every episode labelled `true_catch` by a human
- **WHEN** the reader reports status
- **THEN** it SHALL report the decision rule as met

#### Scenario: Silence and agent labels clear nothing

- **GIVEN** a would-block episode with no label, an `unknown` label, or only an agent-claimed label
- **WHEN** the reader reports status
- **THEN** the episode SHALL be unresolved and the decision rule SHALL NOT be met

#### Scenario: One confirmed false block ends the window for this version

- **GIVEN** an otherwise complete corpus in which a human labelled one episode `false_block`
- **WHEN** the reader reports status
- **THEN** it SHALL report the decision rule as not met and name the false block
