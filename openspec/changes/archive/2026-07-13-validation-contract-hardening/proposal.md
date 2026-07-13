# Proposal: Validation-Contract Hardening

## Why

An adoption triage of two "intent-based engineering" documents (RPI/HumanLayer + specs-as-source), adversarially reviewed with Codex, found exactly two genuine deltas — both closing gaps where the repo's validation-contract story is prose-covered but not enforced:

1. **Expectation provenance in `runtime-validation`.** The skill derives validation scenarios from three source tiers (`eval-pack`, `intent-truth`, `generic-smoke`) and its report carries a `Source` column restricted to those values — but nothing forbids the validating agent from deriving *what counts as correct* from the implementation diff it just watched being written. A validator whose expectations come from the code confirms bugs instead of catching them (same failure family as gate-gaming and behavioral-eval read-contamination, both already documented in this repo).
2. **GIVEN/WHEN/THEN body check in the PLAN-phase design guard.** The DESIGN→PLAN contract hint promises "2-4 GIVEN/WHEN/THEN scenarios" (`config/default-triggers.json` DESIGN→PLAN CONTRACT), but the deterministic guard in `hooks/skill-activation-hook.sh` only grep-checks that an `## Acceptance Scenarios` heading exists. An empty heading passes today — a gate-gaming hole.

## What Changes

- `skills/runtime-validation/SKILL.md`: add an **Expectation provenance (MUST)** rule to Step 2 (scenario derivation) — every expected outcome MUST trace to one of the three source tiers; the implementation may inform *which* paths to exercise, never *what counts as correct* — plus a reinforcing line at the report's `Source` column definition.
- `hooks/skill-activation-hook.sh`: extend the advisory DESIGN COMPLETENESS check — when the Acceptance Scenarios heading is present, count GIVEN/WHEN/THEN triplets within that section (case-sensitive uppercase, section-scoped); `min(GIVEN, WHEN, THEN) >= 2` keeps `[OK]`, fewer renders a distinct `[X]` "heading present but <2 scenarios" advisory line. Fail-open to heading-presence semantics on any extraction error. Never denies.
- `tests/test-validation-skill-content.sh`: content assertions for the provenance rule.
- `tests/test-routing.sh`: regression cases for the G/W/T body check (satisfied / empty-heading / thin / out-of-section tokens / fail-open).

## Capabilities (Modified)

- `runtime-validation` — scenario-derivation contract gains the provenance MUST rule.
- `skill-routing` — PLAN-phase design guard gains the G/W/T body check.

No new capabilities.

## Impact

- No gate posture change: the design guard stays advisory-only; runtime-validation's change is skill prose + tests.
- No hook budget impact beyond one awk pass over a single design file, only in PLAN phase when a design_path exists and the heading is present.
- Rejected alternatives (clean-context validator dispatch, hard-deny G/W/T gate, per-directive behavioral uptake evals) are recorded in design.md with revival criteria.
