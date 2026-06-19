# Auto-route capture-knowledge at learning-bearing phases

## Why

`capture-knowledge` shipped (PR #65) with `precedes: []`, `requires: []`, and only
its capture-keyword regex (`(capture|save|remember) … (learning|gotcha|decision)`)
as a trigger. It is therefore wired into **no** phase composition: it surfaces only
when the user literally says "capture this." Every other skill auto-surfaces by
phase/intent through the activation hook. So this one skill depends on the user
*knowing it exists* — which directly contradicts the plugin's core thesis of
automatic skill routing (the right skill at the right time, without the user having
to know the catalog).

This is a routing consistency bug, not a speculative feature. Auto-invocation is the
product; a bundled skill that only fires on user keywords is a gap to close.

## What Changes

- Surface `capture-knowledge` as a **model-assessed, relevance-gated** candidate in
  the `phase_compositions` hints for the three phases where durable team learnings
  actually emerge: **LEARN**, **SHIP**, and **DEBUG** (post-resolution).
- The hint is a single advisory line carrying an explicit relevance gate ("if a
  durable, non-obvious, team-relevant learning emerged… else skip"). The **model**
  judges relevance; the existing **human approval at write** is unchanged. This is
  NOT an unconditional banner — it is phase-scoped and only one line, consistent
  with the lean-injection discipline.
- The keyword trigger is retained (explicit "capture this" still works).
- `config/fallback-registry.json` regenerated in sync from `config/default-triggers.json`.

## Impact

- Affected specs: `skill-routing` (ADDED requirement).
- Affected code: `config/default-triggers.json` (LEARN/SHIP/DEBUG `phase_compositions.hints`),
  `config/fallback-registry.json` (regenerated), `tests/test-routing.sh` (new
  real-wiring regression).
- No behavioral change to `capture-knowledge` itself, its keyword trigger, or its
  human-gated write path. No new autonomous action — the model is prompted to
  *consider*, not to write.
