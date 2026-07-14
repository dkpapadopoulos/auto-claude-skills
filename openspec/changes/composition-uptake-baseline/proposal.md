# Proposal: Committed composition-directive uptake baseline (audit F6)

## Why

The 2026-07-14 enforcement audit established that this plugin's phase flow is
~90% advisory context text with exactly one deterministic choke point (the
push gate). Whether the model actually OBEYS the advisory layer — the
composition [CURRENT]/MUST-INVOKE directives — has been measured only
ad-hoc: the repeated 0/5 advisory-hint uptake findings and the 5/5
precondition-step-text result live in auto-memory and PR notes, not in a
committed, re-runnable artifact. F6's agreed remedy: commit an uptake eval
pack plus an informational baseline, so directive effectiveness is a tested
number that future routing changes can be compared against — explicitly NOT
a CI gate (variance is unknown; small-n gating lies).

## What Changes

- **Eval pack** `tests/fixtures/composition-uptake/evals/behavioral.json`
  (top-level array, judge assertions, self-contained prompts embedding
  production-shaped activation-hook context), four arms:
  1. `review-step-uptake` — [CURRENT] Step 4 REVIEW context, implementation
     just finished: first action must be requesting-code-review.
  2. `ship-pressure-no-skip` — same context, user says "just push and open
     the PR": must route through review/verification, not comply directly.
  3. `continuation-directive` — Step 5 CURRENT after clean review: must
     continue to verification-before-completion, not stop or jump to PR.
  4. `completed-chain-no-overfire` (control) — all steps DONE: must proceed
     to finishing without redundantly re-running review/verify.
- **README** documenting scope: measures uptake in the plugin's real context
  (repo cwd, CLAUDE.md visible — deliberately the deployed environment, not
  a clean-room), judge model pinned, never-delete cases policy, and the
  explicit NOT-a-CI-gate status with a revival criterion for gating.
- **Structure test** `tests/test-composition-uptake-pack.sh` (deterministic,
  CI-running): pack parses, is a top-level array, ids unique, every
  assertion is a pinned judge with non-empty criteria, every prompt embeds
  the composition markers it claims to test ([CURRENT], `Composition:`).
- **Baseline** `tests/baselines/composition-uptake.baseline.json` — measured
  pass rates (5 reps/arm via the existing opt-in runner, smoke-first),
  recorded with judge model, date, and per-arm counts. Informational.

## Capabilities

- **Modified: behavioral-evaluation** — committed uptake measurement for
  composition directives.
- Touched: `tests/fixtures/composition-uptake/evals/`,
  `tests/test-composition-uptake-pack.sh`, `tests/baselines/`, CHANGELOG.

## Impact

- Closes audit F6: the advisory layer's effectiveness becomes a committed,
  re-runnable measurement with a recorded baseline instead of memory lore.
- No runtime/hook changes; zero effect on routing or gating. The only
  CI-running piece is the deterministic structure test.
- Cost boundary: the behavioral run is opt-in (~40 subject+judge calls per
  full run); CI never pays it.
