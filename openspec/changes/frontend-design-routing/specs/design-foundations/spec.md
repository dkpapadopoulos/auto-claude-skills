# design-foundations

## ADDED Requirements

### Requirement: The shipped seed is a taste floor, not a house style

Aesthetic authority for UI work SHALL rest with the frontend design skill, not with the
shipped seed. The DESIGN-phase guidance that names the seed SHALL state, in the text that
reaches the prompt, that the shipped palette and type scale are a starting floor which the
reader is expected to replace with project-specific choices. That guidance MUST NOT
instruct the reader to adopt the shipped values in preference to making deliberate
brief-specific choices, AND MUST NOT imply that adopting them unchanged is non-compliant —
unchanged adoption remains a supported outcome, so the guidance must express a floor rather
than an obligation to diverge.

#### Scenario: The rendered hint does not contradict the frontend design skill

- **GIVEN** a UI prompt in the DESIGN phase that renders both the seed guidance and a
  selection of the frontend design skill
- **WHEN** the rendered text is read as one context
- **THEN** it MUST NOT contain both an instruction to adopt the shipped values and an
  instruction to choose brief-specific values without stating which governs
- **AND** it MUST identify the shipped palette and type scale as an overridable floor

#### Scenario: The floor framing does not make unchanged adoption read as a defect

- **GIVEN** the reworded DESIGN-phase seed guidance
- **WHEN** it is read by someone who intends to adopt the seed without changing a value
- **THEN** it MUST NOT state or imply that doing so is incorrect, incomplete, or a
  violation of the method
- **AND** no check shipped with the seed may report an unchanged adoption as a failure

### Requirement: The seed method's comparison step is demand-driven

Where the design method directs the reader to a variant-comparison skill, that instruction
SHALL be actionable at the point the method reaches it, without depending on that skill
having been trigger-routed by the prompt. The method MUST NOT rely on UI vocabulary
selecting the comparison skill, and the comparison skill's triggers MUST NOT be widened to
UI vocabulary to satisfy the method.

#### Scenario: The method's comparison step works on an unrouted prompt

- **GIVEN** a UI prompt that selects the frontend design skill but not the
  variant-comparison skill
- **WHEN** the reader follows the design method to its comparison step
- **THEN** the method MUST state that the comparison skill is to be invoked at that point,
  so the step is executable without a prior routing match

#### Scenario: Satisfying the method does not widen comparison routing

- **GIVEN** the 224-prompt negative corpus at `tests/probes/negative-corpus/`
- **WHEN** it is scanned after the method change
- **THEN** the set of prompts routing to the variant-comparison skill MUST NOT grow
