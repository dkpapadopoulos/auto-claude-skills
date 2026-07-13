# Proposal: Design-Guard Spec-Path Fallback

## Why

Post-merge dogfooding of the G/W/T body check (PR #105) on all 10 of this repo's real design docs found that in spec-driven mode the guard's `[OK] Acceptance Scenarios` state is structurally unreachable: the guard reads only `design_path`, but spec-driven changes keep their acceptance scenarios in sibling `specs/<cap>/spec.md` files. Result: 8/10 real docs render a permanent `[X]` — standing noise that trains agents to ignore the advisory (the paired uptake probe measured 0/5 uptake in both arms, and a permanently-red advisory cannot be effective regardless of placement).

## What Changes

- `hooks/skill-activation-hook.sh` (DESIGN COMPLETENESS block): when the design-file acceptance check fails (`_DC_ACC=0`), glob sibling `<design_dir>/specs/*/spec.md` files and count uppercase WHEN/THEN tokens across them; aggregated `min(WHEN, THEN) >= 2` flips the line to a distinct `[OK] Acceptance Scenarios (in sibling specs/)`. GIVEN is deliberately not required — the OpenSpec scenario template makes it optional (verified against the repo's real spec files: 2 of 7 sampled changes are WHEN/THEN-only). Strictly additive: only `[X]→[OK]`; every error path degrades to the current rendering. Breadcrumb gains `gwt_specs=N`.
- `tests/test-routing.sh`: regression tests — spec-driven layout satisfied, GIVEN-less bold-WHEN/THEN template compatibility, thin spec files stay `[X]`, no-specs-dir unchanged.

## Capabilities (Modified)

- `skill-routing` — PLAN-phase design guard gains the spec-path fallback.

No new capabilities.

## Impact

- Advisory-only and fail-open posture unchanged; the check runs only in PLAN phase when a design_path exists and the design-file check failed.
- Default-mode (`docs/plans/`) designs are unaffected (no `specs/` sibling → silent skip).
- Cost: one `cat | awk` pass over sibling spec files, only on the failure path.
