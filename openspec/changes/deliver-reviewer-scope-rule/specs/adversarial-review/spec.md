# Spec delta: adversarial-review — deliver the reviewer scope rule

## ADDED Requirements

### Requirement: The reviewer scope rule MUST be delivered in every reviewer prompt

A scope rule addressed to reviewers MUST appear in the spawn template of every
reviewer lens, not only in the lead-facing protocol prose. A reviewer subagent
reads only its own prompt, so a rule stated once in protocol text constrains no
reviewer.

Where the same rule is held in both a lead-facing and a reviewer-facing copy,
the two copies MUST carry the same category set, the reviewer-facing copies MUST
be identical to one another, and both facts MUST be asserted by a test — a
comment pairing the copies is not sufficient.

The assertion available here is that each spawn template CARRIES the canonical
text. It is NOT an assertion that a reviewer receives only these exclusions: a
contradictory instruction elsewhere in the same prompt, a dispatch path that does
not use these templates, or a lens defined outside the template section all
remain outside what any static check can see. That boundary MUST be stated
wherever the guarantee is claimed, rather than left to be inferred from a passing
gate.

#### Scenario: A lens prompt omits the scope rule

- **GIVEN** the reviewer spawn templates in `agent-team-review`
- **WHEN** any lens prompt does not carry the scope block
- **THEN** the dispatch-brief gate MUST fail
- **AND** the failure MUST name the lens that is missing it

#### Scenario: The two copies diverge

- **GIVEN** a lead-facing scope table and a reviewer-facing scope block
- **WHEN** a category is added to or removed from exactly one of them
- **THEN** the gate MUST fail rather than ship a reviewer scoped by a rule the
  lead does not hold

#### Scenario: The two-category ceiling holds in the delivered copy

- **GIVEN** the scope block delivered to a reviewer
- **WHEN** a third provenance category is added to it
- **THEN** the governance gate MUST fail, whether or not the lead-facing copy
  gained the same category
