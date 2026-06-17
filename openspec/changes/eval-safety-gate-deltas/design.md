# Design: Eval/Safety Gate Deltas

## Architecture

Three advisory edits, all expressing "safety is the first-class gate", placed where they already route:

1. **`EVAL STRATEGY` DESIGN hint** (`config/default-triggers.json` → mirrored to `fallback-registry.json`). Always-on composition hint, sibling to `DESIGN→PLAN CONTRACT` / `PERSIST DESIGN`. The hint instructs the model to classify probabilistic-vs-deterministic verification and **ask the user when unclear** — replacing a brittle prompt-regex with in-context (model) classification, which is the architecture's preferred fallthrough mechanism. Carries the eval-set checklist inline (so it is self-contained even when `agent-safety-review` did not route).

2. **`runtime-validation` rules** (REVIEW/SHIP skill). Append-only eval-scenario discipline (Tier 1) + a mandatory Safety-Relevant Paths subsection that forbids deferring auth/data-deletion/money/destructive paths to manual checks.

3. **`agent-safety-review` constraint** (DESIGN skill, autonomy-triggered). Safety eval cases authored red before the behavior — composes with `test-driven-development`.

The three compose: DESIGN classifies and demands the safety subset red-before-code; REVIEW/SHIP `runtime-validation` runs the packs and enforces safety-path exercise + append-only growth.

## Trade-offs (accepted)

- **Advisory only.** None of this enforces on a builder's product repo — impossible from our side (no LLM/secrets in hooks; forgeable markers; issue #58). Guidance is the honest ceiling. The value is the prompt, not a gate.
- **`agent-safety-review` trigger is autonomy-only** (`autonomous.loop|overnight|background.agent|…`), so its constraint surfaces only for autonomy-flavored designs. A non-autonomous conversational-AI feature is covered instead by the always-on `EVAL STRATEGY` DESIGN hint. Accepted v1 limitation (see revival triggers).
- **One more always-on DESIGN hint** (third). Accepted: it self-suppresses for deterministic work (the branch instruction) and replaces a noisy regex. Kept concise to limit injection cost.

## Dissenting views (from the debates)

- **Architect** initially proposed a conditional AI-feature `methodology_hint` with an AI-shape regex, and (separately) a fuller eval-driven methodology/skill. **Rejected**: the regex is the high-noise, low-reliability piece (collides with `ralph-loop`/`unified-context-stack` triggers; prior dead-regex precedent), and a new skill overlaps `agent-safety-review` + `runtime-validation`.
- **Critic + Codex** argued the whole bundle is ~80% already shipped and 15% medical org-process; the residual real delta is the small prose shipped here. This view prevailed.
- **Pragmatist** wanted a ~15-line checklist in `agent-safety-review`; superseded by the user's "model-asks" insight, which relocated the checklist to the always-on DESIGN hint where it reaches non-autonomous AI features too.

## Decisions & Trade-offs (rejected alternatives)

- **Frozen/measurable-bar hint** — rejected/deferred: the measurable-bar nudge already shipped (`skill-activation-hook.sh` numeric-bar `[i]` line) and is under an active measurement window (H2, ~2026-07-09). A second hint would duplicate it and contaminate the measurement. Revival: after the H2 readout, if measurable-bar adoption stalls.
- **Pre-registered decision-mapping / stopping-rule / safety-stop fields on the hypothesis artifact** — deferred: real sample size is one (the plugin dogfooding itself). Revival: ≥2 LEARN reviews where the roll-out/back call was argued after the fact.
- **Conditional AI-feature auto-trigger (regex)** — deferred: fragile/noisy. Revival: a named non-autonomous AI feature that misses the guidance → widen `agent-safety-review`'s trigger (cheaper than a new hint).
- **New "eval-driven AI feature" skill** — rejected: overlaps two shipped skills; advisory text needs no runnable skill.
- **Rejected outright as org-process** (not plugin-shaped): mandatory LLM-judge pinning as a gate, 100% escalation-recall numeric bars, control-group experiment mandate, clinical/named co-signers, the weekly demo ceremony, an OST tree tool.

## Acceptance check

`tests/test-adversarial-governance.sh` asserts the `EVAL STRATEGY` hint in both config files, the `runtime-validation` safety-path + append-only rules, and the `agent-safety-review` red-before-code constraint. `tests/test-registry.sh` drift canary guards the fallback mirror.
