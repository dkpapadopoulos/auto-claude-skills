# Fix the four measured composition-contract defects

## Why

An audit of the deployed plugin measured four defects in ACS's own composition, each
against the real hooks and, for three of them, against live native behaviour. None
depends on adopting any upstream skill; all four are ACS's own contracts failing to
hold. Evidence and provenance: audit commit `8c027b9` on `codex/sdlc-composition-audit`
(unmerged), ported baseline in `tests/probes/`.

The four:

- **D1** The one-model consultation contract has no route. A second-opinion request
  natively invokes `panel`, the many-model method.
- **D2** Independent consultation and interactive debate are not distinguished;
  selection tracks phrasing, so ordinary design vocabulary co-selects three skills.
- **D3** Phase chains are injected into phase-agnostic consultations — 4 of 11
  consultation prompts received a full DESIGN→SHIP chain.
- **D4** The authorized composed planning path reaches `synthesize` and is refused by
  `disable-model-invocation`, with no programmatic way through.

## What Changes

Four contracts become explicit and enforced. This proposal fixes ACS's representation
of intent; it adopts no upstream skill and makes no claim that any upstream method
improves engineering outcomes.

## Capabilities

**Modified — skill-routing.** Consultation intent is represented distinctly from
development intent, and the three consultation contracts (independent single,
independent panel, interactive debate) are distinguished from one another.

**Modified — composition.** A consultation request does not start an unrelated
development chain, and does not disturb one already in progress. An authorized
composition owner may complete a merge when its inputs are real.

## Impact

Routing changes affect every user of the plugin. The likeliest regression is
suppressing legitimate development routing during a consultation detour — a path the
audit's probe never exercised. Positive development controls are required alongside
the consultation negatives.

Out of scope: adopting any upstream skill; any claim about engineering benefit; the
seven unrun contribution comparisons.
