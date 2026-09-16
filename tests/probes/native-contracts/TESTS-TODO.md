# Prerequisite: instrument tests for `conformance.py`

> **Status: done.** Implemented as `test_conformance.py` (29 tests), with fixture
> derivation recorded in `fixtures/PROVENANCE.md` and the suite wiring in
> `tests/test-probe-instrument-tests.sh`. The six cases below produced four real
> classifier fixes; the two *Also assert* items are covered by
> `AbsenceWithoutPreconditionTest` and `ExitCodeTest`. One deviation is recorded
> below. This file is retained as the contract those tests pin.

**Bounded prerequisite, not another instrument audit.** It was done before extending
the runner. `conformance.py` shipped with **no tests**; its classifier was corrected
twice during the audit by reading traces, which is how both defects were found and is
not a repeatable method.

## Rule

**Every fixture is derived from a retained real trace. None is hand-written.** A
hand-written fixture only proves the classifier agrees with the test author's idea of
the format — that is precisely how the audit's earlier probe shipped a vacuous
validity control. Excerpt the real stream JSON, sanitise paths, and commit the excerpt.

**Stub the provider.** These tests must be incapable of launching a paid run: no test
may reach `subprocess.Popen` with the CLI. Assert that too — a test that *could* spend
money is a defect regardless of whether it does.

## Cases, and the trace that supplies each

All source traces are retained on `codex/sdlc-composition-audit` at `8c027b9`, raw
under `.audit-private/`, with published observations under
`docs/research/2026-09-11-sdlc-composition/native-contracts/evidence/`.

| Case | Must classify as | Source trace |
|---|---|---|
| successful invocation | `succeeded` | `B3-synthesis-with-dispatch` — `panel` returned real results |
| **attempted but refused** | `refused_disable_model_invocation`, **never** `succeeded` | `B3` — `synthesize` carries `cannot be used with Skill tool due to disable-model-invocation`. This is the defect that briefly reported the blocked composed path as working |
| vacuous success | `satisfied` AND `vacuous` | `A3-control-no-consultation` — nothing invoked, absence-only criterion |
| provider truncation | unscored disposition, never pooled as clean | `minus-specialist/r4` of the catalog round — `returncode 1`, `is_error true`, provider session limit. A different runner, the same classification failure |
| missing result | `no_result`, distinct from `succeeded` | construct by truncating a real trace after a `tool_use` with no matching `tool_result` |
| duplicate results | inconclusive, never a pass | the audit's `native/paired-v2` work recorded duplicate successful calls producing a false negative-pair conclusion |

## Also assert

- **Absence with no precondition is not informative.** `A2` and `B2` recorded "did not
  synthesize" while no panel results existed to synthesize. The runner must not score
  such an absence as conformance.
- **Exit code.** `conformance.py` currently exits 0 after reporting violations. If it
  is ever wired to a gate it needs a meaningful failure exit — and it should not be
  wired, because it is paid and non-deterministic.

## Deviation: the duplicate-results fixture

No retained trace contains a duplicate call — every `stdout.jsonl` under
`.audit-private/` and every `.jsonl` under the audit's research tree was scanned for a
repeated `Skill` invocation or a repeated `tool_result` per `tool_use_id`. The defect
was an independent-review finding recorded in `progress-2026-09-12.md`, not a trace
observation, and the audit's own test for it (`native/test_native.py`) hand-writes its
rows — which is what the rule above forbids, so those tests were not ported.

The fixture is therefore **constructed by duplicating a real pair** from the B3 trace
under distinct tool-use ids. Every byte is still sourced from a retained stream, and
the construction is the same class as the truncation specified for the missing-result
case. Recorded in `fixtures/PROVENANCE.md`.

## Porting note

The fixtures do not exist on this branch. Porting them means excerpting from the audit
branch's retained traces — the same lesson as the probe port itself: carrying the
runner without its fixtures leaves the tests broken or, worse, silently vacuous.
