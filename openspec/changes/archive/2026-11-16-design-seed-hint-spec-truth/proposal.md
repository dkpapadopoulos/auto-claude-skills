# Proposal: the design-seed requirement says where the hint is

## Why

`design-foundations` requires the design-seed hint to be "present in the DESIGN
composition" and surfaced "through a composition hint". It is not there. It ships as a
`methodology_hints` entry named `design-seed` in `config/default-triggers.json`, and
since the registered hint cut (PR #427) `phase_compositions.DESIGN.hints` is empty by
requirement. The two canonical specs contradict each other, and the stale one invites
someone to "restore" a composition hint that the hint cut removed on purpose.

## What Changes

- The requirement and its one scenario are restated to match what ships: a methodology
  hint, rendered when a skill is selected, the prompt matches the hint's trigger and the
  phase is DESIGN or IMPLEMENT.
- No code, config or test changes. `tests/test-design-seed-hint-reachable.sh` already
  renders the hint through the real hook and pins the behaviour described.

## Capabilities

- **Modified:** `design-foundations` (one requirement).

## Impact

- None at runtime.
- The requirement no longer promises the hint on every DESIGN-phase prompt. It never
  rendered on one that selected no skill or did not match the hint's trigger.
