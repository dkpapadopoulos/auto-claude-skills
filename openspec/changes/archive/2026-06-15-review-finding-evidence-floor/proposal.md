## Why

The REVIEW phase suffered recurring false-positive nit accretion ("crying wolf"): advisory findings that accumulate every round without ever being actionable, eroding trust in `agent-team-review` output. A multi-agent adversarial-refute gate was considered but rejected via design-debate + Codex stress-test (3–10× cost, unfalsifiable without a baseline). This change ships the cheapest alternative the refute gate would have to beat.

## What Changes

Adds evidence-based finding discipline to `agent-team-review`:
- `Confidence` and `Evidence` fields on every FINDING; a finding may be `blocking` only if its Evidence names an observable failure path.
- A Lead-Synthesis **severity floor**: drop `quality`/`spec` suggestions unmapped to a design-doc capability; demote evidence-less `quality`/`spec` blockers to `warning`.
- `security`/`governance` findings are exempt from drop AND demote — they may block on structural grounds (per the adversarial-reviewer criterion) with no proof-of-concept required.
- Dropped findings stay visible in a "Dropped (below severity floor)" summary section, preserving the doubt-theater signal.
- `Confidence` is advisory-only and never gates synthesis (confidence-weighting would reintroduce self-preferential bias).

## Capabilities

### Modified Capabilities
- `adversarial-review`: adds an evidence-based finding-discipline requirement to the existing review-governance surface.

## Impact

- `skills/agent-team-review/SKILL.md` — FINDING format, Lead Synthesis, reviewer spawn templates, description trigger.
- `tests/test-adversarial-governance.sh` — 8 regression assertions.
- No `hooks/`, `config/`, routing, permission, or bypass changes. The change strengthens an existing review gate.
