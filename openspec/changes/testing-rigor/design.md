# Design: testing-rigor sweep

## Architecture

Three parts, two phases.

### Part 1 — Test-adequacy gate (A) [Phase 1, deterministic]

Extends the skill we already own rather than adding a new review lens.

- **Where:** `skills/project-verification/` + `skills/project-verification/scripts/`
  (a new `coverage-adequacy-check.sh` sibling to `gate-gaming-check.sh`).
- **Flow:** after `project-verification` runs the repo's declared test gate, discover
  the coverage artifact the runner already emits — `coverage.xml`/`.coverage`
  (pytest-cov), `lcov.info`/`coverage-final.json` (jest/nyc), `coverage.out`
  (go test -cover), JaCoCo XML — via an ordered probe list. Compute two signals on
  the diff:
  1. **Changed-line coverage:** of lines added/modified in the diff, the fraction
     covered ≥ a floor.
  2. **Coverage regression:** total covered% did not drop vs the base ref.
- **Output contract:** reuse the existing tri-state. `clean` (both signals pass),
  `suspect` (a signal fails — surfaced as blocking evidence like gate-gaming),
  `unverified` (no coverage artifact / unparseable / tool missing → fail-open, never
  blocks). This mirrors the gate-gaming-status contract exactly, so the push-gate and
  evidence plumbing need no new states.
- **Degradation:** repos without coverage tooling see identical behavior to today.

### Part 2 — Rigor Benchmark (B0) [Phase 1, the measurement instrument]

The yardstick that makes B/C objectively decidable without felt pain.

- **Where:** `tests/fixtures/rigor-benchmark/` (corpus) + `scripts/rigor-benchmark.sh`
  (scorer).
- **Case shape:** each case = a self-contained mini-repo diff + a JSON label
  `{class, should_flag, rationale, source}`. Six classes:

  | class | should_flag | who should catch |
  |---|---|---|
  | `untested-new-code` | yes | A (coverage) |
  | `assertion-free-test` | yes | B-effectiveness (A passes it — coverage is green) |
  | `bug-with-green-tests` | yes | B-mutation / C |
  | `weakened-test` | yes | existing gate-gaming (regression floor) |
  | `adequate-clean` | no | nobody (precision control) |
  | `pure-refactor` | no | nobody (FP control) |

- **Splits:** `dev/` (used to tune A) and `held-out/` (used only to score races).
  Held-out cases are sourced from a *different* codebase/agent than A was tuned on,
  to defeat the in-sample lie (a prior detector scored 93% in-sample, 14% held-out).
- **Metrics per mechanism:** recall (`caught / should_flag`), precision
  (`1 − FP on the two control classes`), **incremental recall over the cheapest
  baseline** (does the mechanism catch what A / gate-gaming already miss?),
  token+wall-time cost per change.
- **Never-delete:** benchmark cases are deprecated with a dated rationale, never
  deleted, so the yardstick can't be quietly weakened to pass a favored mechanism.

### Part 3 — Pre-registered races (B/C) [Phase 2]

Each escalation scored against `held-out/` on a rule **frozen before the race is run**;
thresholds `T*/P*/C*/H*/FP*` are calibrated to the held-out set's measured difficulty
at Phase-2 start (per user decision), then frozen. Each race emits a committed verdict
+ the measured numbers. Adopt rules:

- **B-mutation:** incremental recall on `bug-with-green-tests` over A ≥ `T₁`,
  precision on controls ≥ `P₁`, cost ≤ `C₁`. Ships opt-in (slow, language-specific) —
  never a per-commit hard gate.
- **B-testgen:** spec-derived red-first tests catch ≥ `T₂` of seeded bugs **and**
  ≤ `FP₂` of generated tests pass against buggy code (pinning = auto-fail), human
  accept ≥ `H₂`. Generated from openspec `GIVEN/WHEN/THEN` only.
- **C-cross-model:** incremental recall over `A + agent-team-review` ≥ `T₃`, precision
  ≥ `P₃` (must clear the prior refute-gate's FP bar), cost ≤ `C₃`. Precondition:
  passes `agent-safety-review`.

## Trade-offs

- **Extend project-verification vs. new skill.** Extending keeps the tri-state/push-gate
  plumbing and evidence contract intact; a new skill would duplicate discovery + evidence
  wiring. Chosen: extend.
- **Seeded benchmark vs. real-repo mining.** Seeding gives objective ground truth cheaply
  and immediately; mining real repos gives realism but no reliable labels. Chosen: seed
  for the labeled instrument, source held-out from a different real codebase for realism.
- **Coverage as gate vs. advisory.** Changed-line coverage is deterministic enough to gate
  (as `suspect`); total-regression is noisier and starts advisory. Both fail-open on
  missing tooling.
- **Cost of the races.** Phase 2 spends tokens/time up front to buy a durable conclusion —
  which is the explicit goal (pre-empt pain with proof), not a cost to minimize away.

## Dissenting views

- **"Just ship A; skip the benchmark."** Rejected: without the yardstick the B/C
  decisions revert to felt-pain parking — the exact failure mode the user called out.
  The benchmark is load-bearing, not gold-plating.
- **"Bundle C into this sweep as a headline feature."** Rejected as a *headline*: C is
  orthogonal to test quality, carries a live prior rejection, and adds a trifecta leg.
  It earns adoption only by beating its frozen bar on the same benchmark as everything
  else — no special status.
- **"Add code-derived test generation for speed."** Rejected (out-of-scope): tests
  generated from current code pin current behavior and can *lower* rigor. Only
  spec-derived, red-first generation is admissible.

## Decisions

- A and the Rigor Benchmark ship as a Phase-1 pair; the benchmark is what proves A.
- Thresholds calibrated at Phase-2 start against held-out difficulty, then frozen.
- Tri-state evidence contract reused verbatim; no new push-gate states.
- Fail-open preserved everywhere; absent coverage tooling → `unverified`.
- C is gated behind `agent-safety-review` and its frozen precision bar; not shipped by
  this change unless it clears both.

## Out-of-scope

- Wholesale adoption of spartan-ai-toolkit or mattpocock skills (we have equivalents).
- Cross-model peer review as a committed deliverable (it's a Phase-2 race candidate only).
- Code-derived test generation that pins current behavior.
- Rebuilding anything already enforced (TDD mandate, runtime-validation, security-scanner).
- Quantitative coverage % as a universal hard block (changed-line `suspect` is the gate;
  total-regression starts advisory).

## Eval strategy

- **A (deterministic):** standard TDD + the acceptance scenarios in `specs/`. The Rigor
  Benchmark dev split is A's functional test bed.
- **B-testgen and C (probabilistic):** eval *set* with an adversarial/safety subset,
  a pinned judge model+version, never-delete cases, and a pre-registered safety-stop
  (halt if held-out precision falls below the frozen bar; caller = design owner). Safety
  dimensions are hard pass/fail, never averaged into a quality blend.

## Trifecta classification

- **A:** local-only. private_data Absent-relevant, untrusted_input Absent, outbound_action
  Absent. No trifecta.
- **B0/B-mutation/B-testgen:** local-only. No outbound egress. No trifecta.
- **C-cross-model:** `private_data` Present (user code, possibly private repos) +
  `outbound_action` Present (code sent to OpenAI Codex) = 2 legs. MUST pass
  `agent-safety-review` before ship; unmitigated egress is a blocking governance finding.
