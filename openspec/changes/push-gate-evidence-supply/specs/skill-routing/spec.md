# Spec delta: skill-routing — SHIP requests the verdict the push gate requires

## ADDED Requirements

### Requirement: The SHIP composition requests the verification verdict its own gate reads

The SHIP phase composition MUST include the skill that produces the sha-bound
verification verdict, because the push gate's `routing-governance` and
`verify-hardening` legs read that artifact and no other composition step writes it.
A phase whose gate demands an artifact that the phase never requests is a
contradiction between the rendered chain and the enforced gate, and the rendered
chain is the only instruction the model receives.

The step MUST be sequenced before the steps that commit documentation, so that a
verdict recorded at the start of SHIP is not invalidated by the phase's own later
commits under the existing ancestor-acceptance rule.

The step's rendered purpose text MUST state the two facts that make it fail silently
when they are unknown: that the gate MAY need backgrounding if it runs long, and that a
HEAD that moves while it runs produces a verdict covering no commit. The text MUST NOT
assert a runtime figure or any other measurement taken from one particular repository —
this string ships to every install, and a repo whose gate takes seconds would be told
something false.

This requirement is satisfied by configuration data alone. It MUST NOT be implemented
by adding a hook, a predicate, a skill, or a new evidence artifact, because the
producing skill, the consuming gate, and the rendering path all already exist.

#### Scenario: SHIP asks for the verdict

- **GIVEN** a session entering the SHIP phase
- **WHEN** the composition chain is rendered
- **THEN** the verification-verdict producer appears as a step in the SHIP sequence
- **AND** its purpose text names both hazards: that the gate may need backgrounding, and the mid-run HEAD-move hazard
- **AND** the text asserts no repo-specific runtime figure

#### Scenario: a verdict recorded at the start of SHIP survives the phase

- **GIVEN** a clean verdict recorded at the first step of SHIP
- **AND** later SHIP steps commit only documentation and specification files
- **WHEN** the push gate evaluates the resulting push
- **THEN** the verdict is accepted for those commits under ancestor acceptance

#### Scenario: no new enforcement surface is introduced

- **GIVEN** this change as merged
- **WHEN** the push gate's deny predicates are compared against their prior behaviour
- **THEN** no deny predicate, deny site, or evidence read differs
- **AND** the shadow corpus's predicate version is unchanged
