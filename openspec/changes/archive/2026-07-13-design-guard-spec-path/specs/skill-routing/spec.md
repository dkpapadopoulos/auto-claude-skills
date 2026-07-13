# Spec Delta: skill-routing — Design Guard Spec-Path Fallback

## ADDED Requirements

### Requirement: Spec-driven acceptance scenarios satisfy the design guard via sibling spec files

When the design-file acceptance-scenarios check fails, the DESIGN COMPLETENESS check in `hooks/skill-activation-hook.sh` SHALL count uppercase WHEN/THEN tokens across sibling `<design_dir>/specs/*/spec.md` files and SHALL mark the Acceptance Scenarios line `[OK]` (with a distinct "in sibling specs/" annotation) when the aggregated `min(WHEN, THEN) >= 2`. GIVEN MUST NOT be required in spec files (the OpenSpec scenario template makes it optional). The fallback SHALL be strictly additive — it only flips `[X]` to `[OK]`; any error degrades to the design-file verdict — and the guard SHALL remain advisory-only.

#### Scenario: Spec-driven change satisfies via sibling specs

- GIVEN a design file whose acceptance section is missing or thin, with a sibling `specs/<cap>/spec.md` containing at least 2 WHEN/THEN scenario pairs
- WHEN the PLAN-phase design guard runs
- THEN the Acceptance Scenarios line renders `[OK]` with the sibling-specs annotation

#### Scenario: GIVEN-less template scenarios count

- GIVEN sibling spec files whose scenarios use only bold `- **WHEN**` / `- **THEN**` lines with no GIVEN
- WHEN the guard runs
- THEN the aggregated count treats them as valid scenarios and the line renders `[OK]`

#### Scenario: Thin sibling specs do not flip the verdict

- GIVEN a design file failing the acceptance check and sibling spec files carrying fewer than 2 WHEN/THEN pairs
- WHEN the guard runs
- THEN the line keeps the existing design-file `[X]` message (missing or thin, unchanged)

#### Scenario: Default-mode designs are unaffected

- GIVEN a design file with no sibling `specs/` directory (e.g. `docs/plans/*-design.md`)
- WHEN the guard runs
- THEN the fallback is skipped silently and rendering is byte-identical to the pre-fallback behavior
