# Spec delta: pdlc-safety — parser defects in the gate's subject resolution

## ADDED Requirements

### Requirement: A shell redirection operand MUST NOT be read as a reference

Command-text parsers that extract a reference — a pull-request number, a
refspec — MUST skip shell redirection operands. A redirection operand MUST be
recognised structurally (an optional named file descriptor, an optional `&`, an
optional digit run, then `<` or `>`), never by enumerating spellings, and an
operator whose target is the following word MUST cause that word to be skipped
as well.

#### Scenario: A merge command carrying a stderr redirection resolves its PR

- **GIVEN** a merge command that names a pull-request number and redirects
  stderr with `2>&1`
- **WHEN** the reference is extracted
- **THEN** it MUST be the pull-request number
- **AND** the redirection MUST NOT be counted as a second candidate reference

#### Scenario: A genuinely ambiguous command still refuses

- **GIVEN** a merge command carrying two candidate references, neither of which
  is a redirection operand
- **WHEN** the reference is extracted
- **THEN** nothing MUST be returned, because a plausible wrong label is worse
  than none

### Requirement: The gate MUST NOT assert that a command ships content it does not ship

When every recognised push in a command deletes a reference, the IMPLEMENT
evidence leg MUST NOT state that the push edits source, and MUST record the
event as having emitted no advisory.

The predicate establishing this MUST be advisory-only. It is weaker than the
certification that permits gate legs to be skipped — it accounts only for
recognised push segments, not for every segment — and it MUST NOT be used to
skip, suppress, or shortcut any deny. Certification for gate purposes MUST
continue to require that every segment be accounted for.

#### Scenario: A deletion whose certification is defeated by a pipeline stage

- **GIVEN** a command whose every recognised push deletes a reference, followed
  by a pipeline stage that cannot be vouched for
- **WHEN** the IMPLEMENT evidence leg runs
- **THEN** no advisory claiming the push edits source MUST be emitted
- **AND** the shadow record MUST mark that no advisory was emitted

#### Scenario: A deletion mixed with a real push still advises

- **GIVEN** a command that deletes a reference AND pushes content
- **WHEN** the IMPLEMENT evidence leg runs
- **THEN** the advisory MUST be emitted as before
- **AND** the record MUST mark that an advisory was emitted

Every leg that skips on the strict certification MUST have that skip asserted,
including legs that only emit an advisory. An unasserted skip is how a weaker
predicate migrates onto the gate path unnoticed.

#### Scenario: The weaker predicate never widens a gate

- **GIVEN** a command that the weaker predicate accepts and the strict
  certification refuses
- **WHEN** the push gate evaluates its content-dependent legs
- **THEN** those legs MUST behave exactly as they did before this change
#### Scenario: An advisory leg's skip is bound to the strict predicate

- **GIVEN** a command whose recognised pushes all delete a reference but whose
  certification is refused because a segment cannot be accounted for
- **WHEN** a leg that skips on deletion-only subjects runs
- **THEN** that leg MUST still run, because certification was not established
- **AND** this MUST hold for advisory legs as well as denying ones

### Requirement: Rate membership MUST be a recorded observation, not an inference

The shadow record MUST carry whether the leg emitted an advisory, and the
false-block rate MUST be computed only over episodes for which it did. An
episode MUST NOT be excluded merely because a field is absent or malformed:
exclusion biases the measurement toward clearing the deny-flip, so an
unrecoverable value MUST resolve to inclusion. The excluded population MUST be
reported alongside the rate, never dropped silently.

#### Scenario: An event the leg said nothing about is outside the rate

- **GIVEN** a record that would have blocked but produced no advisory
- **WHEN** the corpus status is computed
- **THEN** the episode MUST NOT be in the rate population
- **AND** it MUST be reported as an explicit exclusion
- **AND** it MUST NOT be counted as an attestation-satisfied episode

#### Scenario: A missing membership field keeps the episode in

- **GIVEN** a would-block record with no recorded advisory field
- **WHEN** the corpus status is computed
- **THEN** the episode MUST remain in the rate population
