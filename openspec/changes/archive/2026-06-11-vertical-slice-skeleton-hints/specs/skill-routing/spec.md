# skill-routing — delta spec: vertical-slice-skeleton-hints

## ADDED Requirements

### Requirement: Vertical-slice decomposition hint in PLAN-phase composition

The PLAN-phase composition MUST emit an advisory hint steering work decomposition toward thin end-to-end vertical slices (each task touching all layers and independently testable) over file-disjoint horizontal layers, and SHOULD direct that tasks sized for `agent-team-execution` be sliced by behavior rather than by file. The hint MUST be present and byte-identical in both `config/default-triggers.json` and `config/fallback-registry.json` (fallback-drift gate). The hint MUST be advisory only: it MUST NOT alter the design-completeness verdict, role caps, composition state, or any push/transition gate. The hint MUST be independent of the spec-driven session-start rewrite — its text MUST NOT contain the `CARRY SCENARIOS` token that keys that transform — so it survives unchanged in both default and spec-driven presets.

#### Scenario: PLAN-phase prompt receives the vertical-slice hint

- GIVEN a session whose primary phase resolves to PLAN
- WHEN the activation hook emits PLAN-phase composition hints
- THEN a hint steering toward thin end-to-end vertical slices over file-disjoint horizontal layers is present in the output

#### Scenario: Hint stays in sync across both registries

- GIVEN the PLAN composition hints in `config/default-triggers.json`
- WHEN compared against `config/fallback-registry.json`
- THEN the vertical-slice hint text is present and identical in both files

#### Scenario: Spec-driven rewrite leaves the hint untouched

- GIVEN the repo preset is `spec-driven`
- WHEN session-start rewrites the PLAN hint whose text matches `CARRY SCENARIOS`
- THEN the vertical-slice hint is not matched by that transform and passes through unchanged
