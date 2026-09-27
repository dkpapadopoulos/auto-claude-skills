# Route UI work to frontend-design, and restore the DESIGN precondition on a domain-only match

## Why

UI/frontend prompts are supposed to reach the `frontend-design` skill alongside the
`design-seed` method, under `brainstorming` as the DESIGN process driver. Three measured
defects break that, none of them in `prototype-lab`:

1. **`frontend-design`'s trigger does not match its own declared nouns.** The closing
   `($|[^a-z])` boundary means a trailing `s` blocks the match. Measured no-match:
   `polish the dashboards`, `add wireframes`, `build the react components`. Measured
   match: `design the dashboard screens`, `redesign the settings ui`. ACS's own
   `design-seed` hint already carries `components?|dashboards?|wireframes?|screens?`,
   so the hint fired where the skill it should pair with did not. **Resolved by this
   change**: `screens?` (restored 2026-09-27, owner decision) and the other plural
   morphology below bring `frontend-design`'s trigger in line with the hint's vocabulary.

2. **On a domain-only match the DESIGN precondition silently stops firing.**
   `_walk_composition_chain` accepts only a selected `process` skill, or a `workflow`
   skill carrying `precedes`/`requires`, as `_CHAIN_ANCHOR` — never a `domain` skill. When
   no process trigger matches, the chain block disappears and with it `brainstorming`'s
   `precondition`, which renders ONLY under the `CURRENT` marker and carries the
   product-discovery prerequisite AND the agent-safety-review lethal-trifecta
   classification gate. There is no fallback path. The code's own comment states why it
   lives in the mandatory channel: "the same guidance as an advisory hint gets 0/5 uptake."

3. **The `design-seed` hint and `frontend-design` issue contradictory instructions in one
   context window.** The hint says "adopt the shipped styleguide seed rather than inventing
   tokens"; `frontend-design` says make "deliberate, opinionated choices ... specific to
   this brief ... not the default families you would reach for on any other project."

`phase_compositions[*].driver` is populated for all 8 phases and is read NOWHERE in
`hooks/` or `scripts/`. It already means "the process skill this phase defers to
regardless of what fired" — exactly the missing anchor.

## What Changes

- `config/default-triggers.json`: add plural morphology to `frontend-design`'s trigger
  (`screens?`, `components?`, `layouts?`, `dashboards?`, `mockups?`, `wireframes?`, the
  `front.end` alias). Deliberately NOT importing `theming`/`design.tokens?`/`style.guides?`.
- `hooks/skill-activation-hook.sh`: when `PROCESS_SKILL` is empty AND the workflow-anchor
  scan found nothing, render the `precondition` of the skill named by
  `phase_compositions[PRIMARY_PHASE].driver`, under a one-line attribution naming its
  `Skill()` invocation. Display-only: it establishes no chain, writes no composition state,
  and emits no continuation directive. Anchoring the full chain on `driver` was considered
  and rejected — it writes `.chain`, which contains both push-gate milestones and would arm
  `deny:chain-review`/`deny:chain-verify` on a prompt that merely asked a UI question.
- `config/default-triggers.json`: narrow `prototype-lab`'s `side.by.side` alternative to a
  proximity form requiring a variant-shaped noun within 40 characters.
- `config/default-triggers.json`: add a floor-not-house-style clause to the `design-seed`
  hint, so aesthetic authority sits with `frontend-design`.
- `docs/design-seed-method.md`: make the `prototype-lab` pointer at `:49` demand-driven.
- `config/fallback-registry.json` regenerated in lockstep.

## Capabilities

### Modified
- `skill-routing` — phase-driver chain anchoring; domain trigger vocabulary contract.
- `design-foundations` — aesthetic authority and the seed's status as a floor.

## Impact

- Routing-governed paths (`config/`, `hooks/`) — the push gate requires a clean
  `project-verification` verdict covering HEAD before any of this can be pushed.
- `prototype-lab` is NOT widened to UI vocabulary. That was measured and rejected.
- No change to composition state at all, and none permitted: a driver-derived render is
  not invocation evidence. The constraint is on the whole state file, not only
  `.completed` — `.chain` is the field that arms the push gate.
