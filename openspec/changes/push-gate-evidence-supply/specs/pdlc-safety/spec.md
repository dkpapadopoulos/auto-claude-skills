# Spec delta: pdlc-safety — a bypassed push is not recorded as an allow

## ADDED Requirements

### Requirement: The diagnostic log distinguishes a bypassed command from an allowed one

When the human push-gate bypass is active, the push gate MUST record the command's
outcome under a label distinct from an ordinary allow. The bypass is resolved before
the diagnostic capture trap is armed, so a record is already written for these
commands; it MUST NOT claim a decision the gate did not make.

This is a correction to an existing record's label. It MUST NOT introduce any new
collection, any new file, or any corpus an agent reads to reason about its operator.
The bypass itself MUST remain unconditional: the gate MUST NOT deny, delay, warn on,
or otherwise respond to the bypass being set.

The requirement's scope is the environment-variable bypass only. A command issued
outside the harness never invokes the hook, so no record is possible for it by
construction, and the resulting measurement MUST be described as a clean denominator
for harness-issued commands rather than as full visibility into operator compliance.

Any rate computed over this log — conversion, deny rate, or bypass share — MUST
exclude bypass records from the allow population, because a bypass is evidence that
the gate was skipped rather than satisfied.

#### Scenario: a bypassed push is not counted as an allow

- **GIVEN** the push gate's human bypass is active for the hook process
- **WHEN** a `git push` is gated
- **THEN** the command proceeds exactly as it does today
- **AND** the diagnostic record for it is labelled as a bypass, not as an allow

#### Scenario: an ordinary allow is unchanged

- **GIVEN** the bypass is not active
- **AND** every gate the command faces is satisfied
- **WHEN** the command is gated
- **THEN** the diagnostic record is labelled as an allow, byte-identical to today

#### Scenario: the bypass is never itself gated

- **GIVEN** the bypass is active
- **AND** the composition chain's REVIEW and VERIFY milestones are both incomplete
- **WHEN** a `git push` is gated
- **THEN** the gate emits no denial
- **AND** no advisory reports the bypass back to the model
