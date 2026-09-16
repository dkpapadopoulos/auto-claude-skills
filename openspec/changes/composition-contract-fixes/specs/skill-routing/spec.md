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

#### Assurance boundary

This requirement spans three mechanisms with three different strengths, and stating
them as one undifferentiated MUST overclaims what the implementation can deliver.

- **Routing is deterministic and enforceable.** Which skill the hook selects is decided
  by regex and score. It is measurable offline, and it is the part this requirement can
  genuinely guarantee.
- **Model choice is probabilistic and NOT enforceable by description.** The audit
  measured the model invoking `panel` on a second-opinion prompt it had NOT been routed
  to, because panel was the only consultation-shaped option in the roster. Adding a
  better-fitting option and narrowing panel's description changes which option is most
  attractive; neither makes panel unreachable. "MUST NOT reach the many-model panel" is
  therefore achievable as *correct routing plus demonstrated native preference*, and is
  NOT achievable as a guarantee, unless invocation is mediated.
- **Payload isolation is enforceable only at the dispatch boundary.** "Exactly one
  participant" and "the payload does not contain the prior answer" are properties of
  how the dispatch context is assembled, not of which skill was selected. A SKILL.md
  instructing the model to assemble the right payload is instruction-following that the
  model may violate. Enforcing it requires a dispatcher that constructs the
  participant's context and validates it per mode.

Two consequences follow, and both are requirements rather than commentary:

- Evidence for each clause MUST be gathered at that clause's own boundary: routing by
  the deterministic probe, participant count and payload exposure by inspecting an
  actual dispatch trace, native preference by explicitly-invoked live runs. A
  skill-content assertion MUST NOT be offered as evidence for a dispatch property.
- Exclusion MUST be checked against the participant's EFFECTIVE context, not the
  visible prompt argument. A clean prompt attached to a fork of the requester's
  conversation, or a shared artifact the participant can retrieve, defeats exclusion
  while the prompt text looks correct.

Note also that excluding the verbatim prior answer does not establish independent
reasoning: a requester who rewrites the question as a leading summary reintroduces the
influence. "Prior answer excluded" is a testable information-handling property and is
the one this requirement asserts; "independent judgement" is a stronger claim that this
requirement does NOT make.

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
