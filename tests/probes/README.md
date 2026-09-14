# Composition probes — ported from the SDLC audit

**Provenance: audit commit `8c027b9` on `codex/sdlc-composition-audit`, ported
2026-09-14 onto `main` at `f0ccf9c`.** That branch is deliberately **not merged**; its
publication and integration is a separate decision. Only the minimum needed to detect
regression on the four measured defects was carried over.

## What these are, and what they are not

They are **frozen observations and non-regression detectors**. They are **not**
acceptance gates for the fixes in flight, and their skill-name assertions must not be
promoted into one. Two reasons, both concrete:

- Both probes assert `expect_absent: panel` for a second-opinion request. A *correct*
  one-participant panel would still fail that assertion.
- The native cases assert the *name* `synthesize` succeeds. A correct new
  composed-flow skill could deliver the right merge and still fail.

Behavioural acceptance for the approved contracts is specified separately, with
held-out paraphrases — the thirteen prompts in `intent-routing/cases.json` are now
development data, because any fix will be written while looking at them.

## What is wired into the suite, and what is not

| Probe | Cost | Wired? |
|---|---|---|
| `intent-routing/intent_probe.py` | deterministic, free, no model call | **yes** — via `tests/test-routing-probe-regression.sh` |
| `native-contracts/conformance.py` | **paid and non-deterministic** — launches a real model against a budget | **no, deliberately** |
| instrument tests for both classifiers | deterministic, free, provider stubbed | **yes** — via `tests/test-probe-instrument-tests.sh` |

The native runner is explicitly invoked, with a budget and retained evidence. Its
results can move without any product change, so it must never gate the normal suite:

```sh
python3 tests/probes/native-contracts/conformance.py --out /absolute/new/dir --live
```

## The baseline

`intent-routing/baseline.json` freezes how routing behaves today, recorded on `main`
at `f0ccf9c` and verified byte-identical to the audit's own observation. Five cases
are recorded as **violated** — those are the known open defects D1, D2 and D3. The
gate asserts no case gets worse; a case improving is the *point* of the work and is
reported, not failed.

Current: 4 satisfied, 5 violated, 4 vacuously satisfied of 13 in the controlled arm.
The `shipped-fallback` arm selects nothing for all 13, so none of its rows carries
information about intent separation — the probe reports that separately rather than
counting it as conformance.

## Ported dependencies that are not obvious

Carried over because the runners and tests need them, and porting the scripts alone
would have broken them silently:

- `intent-routing/cases.json` and `native-contracts/cases.json` — each runner reads
  the case file adjacent to itself.
- `fixtures/hooks-recovered/routing.json` — recovered real hook output, used as the
  real-producer fixture by five of the fifteen instrument tests. A hand-written
  fixture would only prove the classifier agrees with the test author.
- `fixtures/intent-routing-observation-2026-09-13.json` — the audit's own run, kept so
  the baseline's equivalence to it stays checkable.

**Repository-root resolution was rewritten.** The originals counted parent directories
(`parents[4]`, `parents[3]`). At this location one resolved to the wrong directory and
the other was *coincidentally* right — which would have kept working until someone
moved the file again. Both now walk up to the root by marker.

## Instrument tests

```sh
cd tests/probes/intent-routing   && python3 -m unittest test_intent_probe  # 15 tests
cd tests/probes/native-contracts && python3 -m unittest test_conformance   # 29 tests
```

Both run in the suite via `tests/test-probe-instrument-tests.sh`. The conformance
tests replace `subprocess.Popen` module-wide and assert that stub is in place, so they
cannot launch a paid run; the paid runner itself stays unwired.

`conformance.py`'s classifier previously had no tests — the gap this section used to
record. Writing them surfaced four live defects, now fixed and pinned: a truncated
provider run was scored as clean; a second call to the same skill was invisible
because outcomes are keyed by name; an absence whose precondition never held counted
as conformance; and the runner exited 0 after reporting violations. Fixture
provenance is in `native-contracts/fixtures/PROVENANCE.md`.
