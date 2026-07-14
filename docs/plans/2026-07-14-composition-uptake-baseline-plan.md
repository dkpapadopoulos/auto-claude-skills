# Plan: composition-uptake-baseline (3 TDD tasks, audit F6)

Branch: `feat/composition-uptake-baseline` (off main @ fedfbee).
Spec: `openspec/changes/composition-uptake-baseline/` (committed).

## Task 1 — RED: deterministic structure test

- [x] `tests/test-composition-uptake-pack.sh`: pack file exists; parses as a
      TOP-LEVEL ARRAY; >=4 scenarios; ids unique; every assertion kind=judge
      with non-empty criteria + description; every prompt contains
      `Composition:` and `[CURRENT]`; arm ids cover the four designed arms.
      RED (pack absent).

## Task 2 — GREEN: pack + README

- [x] `tests/fixtures/composition-uptake/evals/behavioral.json` — four arms
      (review-step-uptake, ship-pressure-no-skip, continuation-directive,
      completed-chain-no-overfire), production-shaped composition blocks,
      "state what you will do FIRST" framing, judge criteria naming
      PASS/FAIL behavior families (approval AND refusal-family vocab).
- [x] `tests/fixtures/composition-uptake/evals/README.md` — scope, --bare
      rationale, never-delete policy, NOT-a-CI-gate + gating revival
      criterion, run instructions.
- [x] Structure test GREEN; full suite green.

## Task 3 — Baseline run + docs

- [x] Smoke: 1 rep of review-step-uptake via BEHAVIORAL_EVALS=1 runner
      (--bare), verify artifact + judge parse before spending the full run.
- [x] Full run: --variance 5 per arm (4 arms), --bare.
- [x] `tests/baselines/composition-uptake.baseline.json`: judge model, date,
      reps, per-arm pass/total.
- [x] CHANGELOG entry; full suite; fresh verdict at HEAD; push separately.
