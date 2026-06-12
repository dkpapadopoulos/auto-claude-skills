# Proposal: Vertical-slice PLAN hint + skeleton-first Serena steering

## Why

Review of an external harness-engineering / context-management reference (2026-06-12) mapped its recommendations against this repo and found the large majority already shipped — often after explicit prior evaluation (GraphRAG/GitNexus rejected, Serena AST adopted, cozempic/context-economy for compaction, agent-team-review for adversarial review). Two genuine gaps survived the cross-check:

1. **No vertical-slice guidance anywhere.** Grep of `skills/` returned zero hits for vertical-slice / tracer-bullet / thin-slice. Worse, `agent-team-execution` decomposes work into file-disjoint parallel tasks — structurally the horizontal-layering anti-pattern (all schema, then all APIs, then all UI) that delays integration feedback. Nothing steered planning toward thin end-to-end slices.
2. **No skeleton-first steering in the context stack.** `unified-context-stack`'s `internal-truth` tier documents Serena symbol navigation but never tells the agent to read a file's signature skeleton (`get_symbols_overview`) before pulling whole bodies — leaving the cheapest context-economy lever unstated.

A third candidate — wiring OpenSpec acceptance scenarios into the behavioral-evaluation runner as a spec→eval oracle — was deferred to its own `design-debate` session because deterministic NL→assertion translation has real design surface; it is out of scope here.

`writing-plans` is the external `superpowers` skill (not owned here), so the vertical-slice guidance is injected via the PLAN-phase composition hints in our own config rather than by editing the vendored skill — upgrade-safe, and the injection point we actually control.

## What Changes

1. A `VERTICAL SLICES` hint added to `phase_compositions.PLAN.hints` in **both** `config/default-triggers.json` and `config/fallback-registry.json` (dual-write required by the fallback-drift gate). The hint steers decomposition toward thin end-to-end slices over file-disjoint horizontal layers and toward behavior-sliced tasks for `agent-team-execution`. It is mode-agnostic: the session-start `CARRY SCENARIOS` text-match rewrite for spec-driven mode does not touch it.
2. A `Skeleton first` bullet added to Tier 1 of `skills/unified-context-stack/tiers/internal-truth.md`, plus a matching decision-table row, directing use of `get_symbols_overview` before `Read`-ing whole files to conserve context budget.

## Capabilities

- **Modified:** `skill-routing` (new PLAN-phase composition hint; ADDED requirement form per repo convention)
- **Modified:** `unified-context-stack` (new Internal-Truth Tier 1 skeleton-first directive; ADDED requirement form)

## Impact

- `config/default-triggers.json` + `config/fallback-registry.json` — one additive PLAN hint, identical in both files; no scoring, role-cap, composition-state, or push-gate logic touched.
- `skills/unified-context-stack/tiers/internal-truth.md` — one Tier 1 bullet + one table row; gated under `serena = true`.
- No hook logic, registry shape, or hook-budget change. Purely additive advisory guidance. Full test suite (57 files) green before and after.
