## Why

REVIEW's PARALLEL entry for `implementation-drift-check` carries `"gate": "artifact-presence"` with an `artifacts` list, so it renders only when the repo holds comparison material: plans, specs, openspec changes or eval packs. SHIP's SEQUENCE entry for the same skill, `FALLBACK: Run drift check if it did not run in REVIEW`, had no gate. In a repo with no comparison material, SHIP therefore told the model to run a skill that REVIEW had correctly hidden, with nothing to drift against (measured: the line rendered for "ship it" in an empty git repo).

The hook already evaluates `gate` on SEQUENCE entries the same way it does on PARALLEL ones, so the fix is configuration only.

This is the one low-risk piece of the shortlist item "stop rendering zero-use skills only where a precondition is false".

## What Changes

- SHIP's `implementation-drift-check` SEQUENCE entry gains `"gate": "artifact-presence"` and the same `artifacts` list as REVIEW's PARALLEL entry, in both `config/default-triggers.json` and `config/fallback-registry.json`, byte-identical.
- `tests/test-ship-drift-gate.sh` holds the two lists equal in each config, holds the SHIP entry equal across configs, and renders the real hook for a SHIP prompt in a temp git repo with and without `docs/plans/x-plan.md`.

Not changed (see design.md): `runtime-validation`'s SHIP fallback, the phase-map lines, and the AUTONOMY CHECK and EVAL STRATEGY hints.

## Capabilities

### Modified Capabilities

- `skill-routing`: SHIP's drift-check fallback renders only when REVIEW's artifact-presence gate for the same skill would pass.

## Impact

`config/default-triggers.json`, `config/fallback-registry.json`, new `tests/test-ship-drift-gate.sh`. No hook change. `tests/test-injection-budget.sh` is unchanged: its SHIP shape runs against this repository, which has comparison material, so the line still renders there and no measured byte moves.
