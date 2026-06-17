# Proposal: Eval/Safety Gate Deltas

## Why

An evaluation of an external AI-native PDLC reference (a spec-driven, eval-centric product development lifecycle) was run through three multi-agent design-debates plus a cross-model (Codex) pass. The framework's headline ideas — a frozen measurable acceptance bar, a tiered eval set, pre-registered experiment decisions — were largely **already present** in our PDLC (DESIGN→PLAN acceptance-scenario contract, the advisory numeric-bar nudge under active measurement, `runtime-validation` eval-pack consumption, `outcome-review` hypotheses) or were **medical/org-process** that does not fit a general plugin (LLM-judge mandates, 100% escalation-recall bars, control-group experiments, clinical co-signers).

The debates converged — cross-model-verified — on a small, genuinely-transferable core: **safety is the first-class, non-negotiable gate.** Three concrete gaps remained, all the same insight:

1. Our PDLC never tells a builder to treat a probabilistic/AI feature's verification differently from deterministic work, nor to author its safety eval cases **before** the behavior exists.
2. `runtime-validation` consumes eval packs but never requires that **safety-relevant runtime paths** (auth, data deletion, money, destructive side effects) actually be exercised, and never states that eval scenarios are append-only.
3. `agent-safety-review` covers the lethal trifecta but says nothing about writing safety eval cases red before implementation.

The "auto-detect AI features" routing approach was rejected: a fail-open Bash-3.2 regex cannot reliably classify "is this an AI feature" without noise (collides with existing hint triggers; prior regex work shipped dead patterns). The reliable mechanism is **model-asks**: the DESIGN phase is conversational, so the model classifies (asking the user when unclear) and branches the guidance.

## What Changes

- **DESIGN-phase `EVAL STRATEGY` composition hint** (always-on, advisory): instruct the model to classify probabilistic-vs-deterministic verification — asking the user if unclear — and branch. For AI/LLM/agent behavior: plan an eval *set* (smoke + adversarial/safety subsets, pinned judge model+version, never-delete cases, pre-registered safety-stop) with the safety subset authored **red before implementation**. For deterministic work: standard TDD + the acceptance scenarios already mandated. Safety dimensions are hard pass/fail gates, never averaged. This is the "model-asks, no auto-trigger" mechanism.
- **`runtime-validation`**: add a mandatory **Safety-Relevant Paths** rule (auth/data-deletion/money/destructive side effects MUST be exercised and reported, not deferred to manual checks) and an **append-only** rule for eval-pack safety scenarios (never delete to pass; deprecate with a dated rationale; grow from production failures).
- **`agent-safety-review`**: add a Constraint that for AI/LLM/agent features the safety eval cases MUST be authored and failing (red) **before the behavior is implemented**, composing with `test-driven-development`.

Deferred (with revival triggers) and rejected items are recorded in `design.md`.

## Capabilities

### Modified
- **`pdlc-safety`** — the DESIGN-phase safety disciplines gain: an eval-strategy classification step (model-asks), the safety-eval-red-before-code rule in `agent-safety-review`, and the safety-relevant-path-exercise + append-only-eval-scenario rules in `runtime-validation`. The eval-strategy classification requirement specifies the always-on DESIGN hint and its fallback mirror; the `skill-routing` composition is the delivery surface for that hint (no separate `skill-routing` delta — the requirement lives under `pdlc-safety`).

## Impact

**Files modified:**
- `config/default-triggers.json` — one always-on `EVAL STRATEGY` hint in the DESIGN `hints[]` array.
- `config/fallback-registry.json` — regenerated mirror (drift canary: `tests/test-registry.sh`).
- `skills/runtime-validation/SKILL.md` — append-only eval-scenario line (Tier 1) + mandatory Safety-Relevant Paths subsection (before Step 3).
- `skills/agent-safety-review/SKILL.md` — one Constraint bullet (safety eval red before code).
- `tests/test-adversarial-governance.sh` — regression assertions for all of the above.

**Behavioral risk:** Low. All changes are advisory prose/hints; no hook logic, no routing-score change, no enforcement. Fail-open preserved. The numeric-bar measurement window (H2) is untouched — the hint deliberately avoids measurable-bar framing.
