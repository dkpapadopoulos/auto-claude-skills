# Testing-rigor sweep: adequacy gate + a benchmark that proves the escalations

## Why

A verified inventory of our PDLC (Explore agent, 2026-07-01) shows the testing
stack is **deep on the left, shallow on the right**: we heavily enforce *does code
get reviewed/verified* (TDD mandate, `requesting-code-review`, `agent-team-review`,
`security-scanner`, `runtime-validation`, `implementation-drift-check`, push-gate)
but barely touch *are the tests any good*. `gate-gaming-check.sh` catches tests
getting **weaker** (removed asserts, skip/xfail); nothing catches new code shipping
**untested** or tests that assert nothing.

Three external repos were evaluated as priors, not sources:
- `spartan-stratos/spartan-ai-toolkit` — a competing PDLC; ~90% redundant with ours.
- `mattpocock/skills` — `tdd`/`diagnosing-bugs`/two-axis `code-review`/`to-issues`; we
  already have an equivalent for each.
- `jcputney/agent-peer-review` — the one novel mechanism: **cross-model (Claude vs
  Codex) blind-pass + deterministic reconciliation**. Orthogonal to test *quality*
  (it hardens *review*), and it carries a live prior rejection (the multi-agent
  refute-gate killed on false-positive grounds).

None of the three fill the real gap. So the strongest rigor improvement is one we
**build** by extending code we own — and, per user direction, the higher-ambition
escalations (mutation/effectiveness, spec→test generation, cross-model review) must
reach an **objective, measured** adopt/reject conclusion rather than be parked on
"no felt pain." The mechanism that makes that possible is a **seeded-defect Rigor
Benchmark** that supplies objective ground truth independent of felt pain — so the
pain is pre-empted by proof.

## What Changes

Two phases. Phase 1 is committed; Phase 2 races are committed to *run* (frozen
adopt/reject criteria), not to *ship any particular escalation*.

**Phase 1 — the gate + the yardstick (ship together):**
- **A. Test-adequacy gate.** Extend `project-verification` + `gate-gaming-check.sh`
  from "detect test weakening" → "detect test *inadequacy*." After the declared test
  gate runs, parse coverage the runner already emits and assert (i) changed lines
  covered above a floor, (ii) no coverage regression vs base. Folds into the existing
  tri-state evidence (`clean`/`suspect`/`unverified`); missing coverage tooling →
  `unverified`, fail-open. Deterministic; push-gate-compatible.
- **B0. Rigor Benchmark harness.** A committed labeled corpus of seeded
  `(diff, ground-truth-verdict)` cases across six classes (untested-new-code,
  assertion-free-test, bug-with-green-tests, weakened-test, adequate-clean,
  pure-refactor), split **dev** (tune A) vs **blind held-out** (score the races),
  held-out sourced from a *different* codebase than A was tuned on. Metrics: recall,
  precision on controls, incremental recall over the cheapest baseline, token/time
  cost. This is the measurement instrument for everything downstream.

**Phase 2 — the pre-registered races (frozen criteria calibrated at Phase-2 start):**
- **B-mutation** — real mutation testing (Stryker/mutmut/PIT) as an opt-in REVIEW audit.
- **B-testgen** — spec→acceptance-test generation seeded from openspec `GIVEN/WHEN/THEN`,
  **red-first from intent, never from code** (a generated test that passes against the
  seeded-buggy code is an automatic fail).
- **C-cross-model** — adopt `agent-peer-review`'s Claude-vs-Codex blind-debate as a
  REVIEW upgrade. Precision bar must specifically clear the prior refute-gate's FP
  failure. `private_data` + `outbound_action` (code → OpenAI Codex) ⇒ MUST pass
  `agent-safety-review` before it could ship.

Each race emits a committed verdict + measured numbers on the held-out benchmark.

## Capabilities

### Added
- **testing-rigor** — the test-adequacy gate, the Rigor Benchmark instrument, and the
  frozen-criteria race protocol that governs whether B/C escalations are adopted.

### Modified
- **project-verification** — gains changed-line coverage + coverage-regression checks,
  surfaced through its existing tri-state evidence contract.

## Impact

- Users get a deterministic signal when new code ships under-tested — the biggest
  verified gap — without new felt-pain dependence.
- Escalations (mutation, test-gen, cross-model review) get an objective yardstick, so
  each is adopted or rejected on recorded evidence, not vibes.
- Fail-open preserved end-to-end: absent coverage tooling degrades to `unverified`,
  never a false block.
- Out of scope (see design.md): wholesale adoption of the three external PDLCs;
  code-derived test generation that pins current behavior; shipping any Phase-2
  escalation before it clears its frozen bar.
