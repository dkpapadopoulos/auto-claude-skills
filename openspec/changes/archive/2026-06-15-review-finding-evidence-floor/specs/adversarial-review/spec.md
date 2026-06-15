## ADDED Requirements

### Requirement: Evidence-Based Finding Discipline

`agent-team-review` MUST apply evidence-based discipline to findings to curb false-positive nit accretion without suppressing real findings.

Each FINDING MUST carry a `Confidence` field (`high|medium|low`) and an `Evidence` field. A finding MAY be classified `blocking` only if its `Evidence` describes an observable failure path — a concrete input, call, or sequence that produces the failure. The `Confidence` field MUST be advisory-only and MUST NOT gate, filter, or demote findings.

During Lead Synthesis the system MUST apply a severity floor to `quality`- and `spec`-category findings: drop `suggestion`-severity findings unmapped to a design-doc capability, and demote `blocking` findings whose `Evidence` lacks an observable failure path to `warning`. The system MUST NOT drop or demote `security` or `governance` findings on these bases — those MAY be `blocking` on structural grounds (removing or weakening an existing safety constraint) without a runnable proof-of-concept. Floored findings MUST remain visible in the review summary so the doubt-theater signal stays detectable.

#### Scenario: Theoretical quality concern is demoted

- **WHEN** a reviewer reports a `quality` finding as `blocking` whose `Evidence` names no observable failure path
- **THEN** Lead Synthesis demotes it to `warning` rather than blocking the merge

#### Scenario: Structural security finding blocks without a PoC

- **WHEN** a reviewer reports a `security` or `governance` finding that removes or weakens an existing safety constraint but provides no runnable proof-of-concept
- **THEN** the finding remains `blocking` and is neither dropped nor demoted

#### Scenario: Unmapped quality suggestion is dropped but visible

- **WHEN** a `quality` `suggestion` does not map to any capability named in the design doc
- **THEN** it is dropped from the active findings AND reported under "Dropped (below severity floor)" with a one-line reason

#### Scenario: Confidence never gates synthesis

- **WHEN** a finding carries `Confidence: low`
- **THEN** synthesis MUST NOT drop or demote it on the basis of confidence alone; only the evidence and severity-floor rules apply
