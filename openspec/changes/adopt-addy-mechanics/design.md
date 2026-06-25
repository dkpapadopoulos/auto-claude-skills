# Design — adopt addy agent-skills mechanics

Full ranked portfolio and method in `docs/plans/2026-06-25-addy-adoption-design.md`.
This file captures the architecture, dissents, and decisions from the design debate
(architect / critic / pragmatist + Codex 4th voice, file-grounded).

## Architecture

Three capture mechanisms for an external mechanic:
1. **Graft into an owned skill** (PR1 items) — prose in a SKILL.md we own; zero routing/token cost.
2. **Depend on addy's plugin** — REJECTED (competing router, overlap, version drift).
3. **Hook-injected phase directive + inter-skill context contract** (PR2 items) — the
   unique-to-us mechanism. A `methodology_hints[]` entry, hard phase-gated, that wraps a
   dependency skill we cannot edit and threads context to the next skill via session state.

Sequencing rule (architect): **rank by edges created, not capabilities added.** The
deploy-gate threshold graft (T2a) is the *consumer contract* that the deferred observability
skill (T3a) must later produce against — so the contract ships before the producer.

## Trade-offs

- New directives cost UserPromptSubmit tokens and crowd the existing hint block. Mitigated
  by hard phase-gating + tight triggers + capping PR2 to two directives, both eval-gated.
  Honors the PR #45 lean-injection rejection ("no measured benefit" bar).
- Deferring T3a composition risks under-delivering if the telemetry→deploy-gate handoff is
  the real point. Accepted as an explicit revival criterion, not a silent drop.
- STRIDE graft risks bloating security-scanner — kept to a compact checklist.

## Dissenting views

- **Codex:** T1c/T1e (citation, inline-planning) should be *directives*, not grafts —
  they are execution behavior, and grafting them into a retrieval-tier skill violates that
  tier's boundary. **Decision:** graft anyway (cost + low item-value) but place them in
  External Truth *consumption* guidance, not a generic behavior dump, to respect the boundary.
- **Critic:** cut T1a (intent-extraction) outright — duplicates brainstorming +
  product-discovery, risks double-interview, has no eval. **Decision:** keep, but ship only
  behind a red-first quality eval — the path the Critic named as the only honest one — and
  hard-gate it to fire solely when the ask is underspecified AND no approved brief exists.
- **Codex ranked T1b #1**; placed in PR2 behind T1a (earlier in chain, clears a standing trigger).

## Decisions & rejected alternatives

- **Rejected:** addy plugin as a dependency / routing at its skill names (mechanism 2).
- **Rejected:** T1c, T1d, T1e as standalone directives (collapsed into grafts / folded into T3a).
- **Rejected now, revivable:** T3a composition wiring; T3b; T3c (reframe-gated).
- **Confirmed skip:** using-agent-skills, performance-optimization, ci-cd scaffolding,
  ADR-lifecycle, frontend AI-aesthetic.
