# skill-routing

## ADDED Requirements

### Requirement: Phase driver precondition renders on a domain-only match

When no `process` skill was selected and no selected `workflow` skill carries
`precedes`/`requires`, the activation hook SHALL render the `precondition` of the skill
named by `phase_compositions[PRIMARY_PHASE].driver`, attributed by a single line naming
that skill's `Skill()` invocation so the precondition has an antecedent. The driver name
SHALL be read from configuration, never hardcoded. The hook MUST NOT emit the composition
directive ("after completing X, invoke Y; do not stop") on a driver-derived render,
because no trigger matched the driver and the directive would push a full sequence off a
phase default rather than off evidence of intent.

#### Scenario: A domain-only DESIGN match still renders the process precondition

- **GIVEN** a prompt whose only selected skills have `role: domain` and `phase: DESIGN`,
  and no `process` skill matched
- **WHEN** the activation hook renders its output
- **THEN** the output MUST name the DESIGN driver's `Skill()` invocation on one line, AND
  MUST contain that skill's `precondition` text including the lethal-trifecta
  classification instruction
- **AND** the output MUST NOT contain a sequenced composition chain or step markers

#### Scenario: The rendered driver tracks configuration rather than a hardcoded name

- **GIVEN** a registry fixture in which `phase_compositions` is edited so that some phase's
  `driver` names a different existing skill
- **WHEN** a domain-only prompt for that phase is rendered
- **THEN** the output MUST name the skill the edited `driver` field names, and MUST NOT
  name the skill it named before the edit

#### Scenario: A driver-derived render carries no continuation directive

- **GIVEN** a domain-only prompt that renders a driver-derived precondition
- **WHEN** the output is inspected
- **THEN** it MUST NOT contain the composition directive
- **AND** a control prompt that selects a `process` skill by trigger match MUST still
  contain that directive

### Requirement: The driver fallback persists no state and displaces no resolved anchor

A driver-derived render SHALL be display-only. It MUST NOT create, modify, or remove the
composition state file, and MUST NOT cause the driver to become creditable as a completed
composition step on that turn or any later turn. It MUST NOT alter output on any prompt
where a `process` or `workflow` anchor already resolved, and MUST NOT change the order in
which those two anchors are resolved.

#### Scenario: No composition state is written

- **GIVEN** an existing composition state file with non-empty `chain` and `completed`
  belonging to an unrelated chain
- **WHEN** a domain-only prompt renders a driver-derived precondition
- **THEN** the composition state file MUST be byte-for-byte identical to its prior
  content, compared as whole files rather than by inspecting individual fields

#### Scenario: A driver-derived render cannot be credited on a later turn

- **GIVEN** a first prompt that renders a driver-derived precondition for a phase
- **WHEN** a second prompt in the same session genuinely selects a skill further along that
  phase's chain
- **THEN** the driver MUST NOT appear in `completed` by reason of the first prompt, and the
  recorded progress MUST equal what the second prompt alone would have produced

#### Scenario: Inert where a process anchor resolved

- **GIVEN** a prompt that selects a `process` skill by trigger match
- **WHEN** the activation hook renders its output before and after this change
- **THEN** the rendered composition chain MUST be byte-identical between the two runs

#### Scenario: Inert where a workflow anchor resolved

- **GIVEN** a prompt that selects no `process` skill but selects a `workflow` skill
  carrying `precedes` or `requires`
- **WHEN** the activation hook renders its output before and after this change
- **THEN** the rendered composition chain MUST be byte-identical between the two runs, and
  the workflow skill MUST remain the anchor

### Requirement: Driver resolution failure is distinguishable from infrastructure failure

The hook SHALL distinguish "this phase has no resolvable driver" from "the machinery needed
to resolve it is unavailable". Both SHALL fail open, and neither may abort the hook, but
they MUST NOT be reached through a single catch-all that makes a genuine infrastructure
fault indistinguishable from an absent driver.

#### Scenario: An unresolvable driver degrades rather than failing

- **GIVEN** a phase whose configured `driver` names a skill absent from the registry
- **WHEN** a domain-only prompt for that phase is rendered
- **THEN** the hook MUST omit the driver render, MUST emit its remaining output unchanged,
  and MUST exit successfully

#### Scenario: An infrastructure fault does not masquerade as an absent driver

- **GIVEN** an environment in which the registry cannot be parsed
- **WHEN** a domain-only prompt whose phase HAS a resolvable driver is rendered
- **THEN** the hook MUST still exit successfully without a driver render
- **AND** in the same environment repaired, the identical prompt MUST produce the driver
  render, proving the omission was caused by the fault and not by a condition that also
  suppresses a resolvable driver

### Requirement: A routing trigger matches the inflections of the nouns it declares

Where a regex trigger enumerates a countable noun as evidence of a domain, it SHALL match
that noun's plural form as well as its singular. A word-boundary idiom SHALL be used that
is supported by Bash 3.2 on macOS; `\b` MUST NOT be used, because `[[ =~ ]]` there does not
support it and a non-matching trigger fails silently.

#### Scenario: Plural UI nouns route to the frontend design skill

- **GIVEN** the `frontend-design` trigger
- **WHEN** it is tested against prompts naming `dashboards`, `wireframes`, `components`
  and `screens` in the plural
- **THEN** each MUST match, and the corresponding singular forms MUST continue to match

#### Scenario: The plural fix introduces exactly one accepted new firing, and no others

- **GIVEN** the 224-prompt negative corpus at `tests/probes/negative-corpus/`
- **WHEN** it is scanned before and after the trigger change (which restores `screens?`
  alongside the other plural morphology)
- **THEN** exactly one new prompt routes to `frontend-design`: "the collapsible panel on
  the settings screen needs a scrollbar" — accepted as in remit per `frontend-design`'s own
  description ("building new UI or reshaping an existing one"), and because this corpus was
  built for cross-family consultation routing, not to adjudicate this skill's remit
- **AND** no OTHER prompt in the corpus may route to `frontend-design` after the change

### Requirement: Comparison routing stays gated on a comparison ask

A trigger that selects a variant-comparison skill SHALL require evidence of a comparison
request, not merely the presence of display vocabulary. A `side by side` phrase SHALL
qualify only when it co-occurs with a variant-shaped noun in the same clause.

#### Scenario: Display requests do not route to the comparison skill

- **GIVEN** prompts that place unrelated content `side by side` — data series, API
  responses, diffs, or an existing UI feature described in a bug report
- **WHEN** they are scanned against the `prototype-lab` trigger
- **THEN** none may route to `prototype-lab`

#### Scenario: The variant noun is what decides, not the phrase

- **GIVEN** a pair of prompts identical except that one names a variant-shaped noun
  (`alternatives`, `options`, `variants`, `designs`, `approaches`) and the other names
  unrelated content in the same position
- **WHEN** both are scanned against the `prototype-lab` trigger
- **THEN** the prompt naming the variant-shaped noun MUST match and the other MUST NOT,
  for every pair in the set
