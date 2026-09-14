# Spec delta: skill-routing — consultation contracts

## ADDED Requirements

### Requirement: A single-model consultation is routed and described distinctly from a panel

A request for one other model's opinion MUST reach a consultation method that
dispatches exactly one participant, and MUST NOT reach the many-model panel. The
method MUST distinguish two modes: an independent opinion, where the requester's prior
answer is EXCLUDED from what the participant sees, and an answer critique, where it is
deliberately INCLUDED.

Roster size alone MUST NOT be treated as satisfying this requirement, because the
distinction is what the participant is shown, not how many participants there are.

Both the routing triggers AND the model-visible skill descriptions MUST be changed. A
change to triggers alone is insufficient: a model presented with a roster whose only
consultation-shaped option is the panel will select the panel regardless of routing.

#### Scenario: an independent second opinion excludes the prior answer

- **GIVEN** a user asks for a second opinion from one other model on an approach
- **WHEN** the request is routed and the consultation dispatched
- **THEN** exactly one participant is dispatched
- **AND** the payload does not contain the assistant's prior answer

#### Scenario: an explicit critique includes the prior answer

- **GIVEN** a user asks another model to critique the answer just given
- **WHEN** the consultation is dispatched
- **THEN** the payload includes that prior answer

#### Scenario: a genuine panel request still reaches the panel

- **GIVEN** a user asks for independent answers from several models, unmerged
- **WHEN** the request is routed
- **THEN** the panel method is selected and no synthesis is performed

### Requirement: A consultation does not start or disturb a development workflow

A request whose intent is consultation only MUST NOT cause a development composition
chain to be rendered. A consultation request made while a development chain is already
in progress MUST preserve that chain, and a subsequent continuation MUST resume it.

Chain suppression MUST NOT be applied to a mixed request that asks for consultation
AND for development work to follow.

#### Scenario: a consultation-only request starts no chain

- **GIVEN** no development workflow is in progress
- **WHEN** the user asks only for another model's opinion
- **THEN** no development composition chain is rendered

#### Scenario: a consultation detour preserves an active workflow

- **GIVEN** a development chain is in progress
- **WHEN** the user asks for a consultation and afterwards says "continue"
- **THEN** the original chain is resumed at the step it had reached

### Requirement: An authorized composition owner merges only on input evidence

A composition owner MAY complete a merge of independent perspectives ONLY when its
inputs are established as complete, attributable to distinct participants, associated
with the current request, and not superseded. A marker asserting that results exist,
or the mere presence of files, MUST NOT satisfy this.

The existing restriction preventing standalone model invocation of the synthesis
method MUST be preserved.

#### Scenario: an authorized composed flow completes

- **GIVEN** a panel has produced attributed perspectives from distinct participants for
  the current request
- **WHEN** an authorized composition owner is asked to merge them
- **THEN** the merge completes and retains attribution and recorded disagreement

#### Scenario: a merge without real inputs is refused

- **GIVEN** no independent perspectives have been gathered for the current request
- **WHEN** a merge is requested
- **THEN** the merge is refused rather than synthesised from the requester's own output
