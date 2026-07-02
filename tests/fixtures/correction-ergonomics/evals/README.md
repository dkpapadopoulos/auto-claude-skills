# Correction-ergonomics behavioral A/B (TrueCall Phase C ship gate)

Red-first quality gate for the correction-ergonomics message rewrite. The imperative
rewrites ship **only** if they show a measurable self-correction lift over the prior passive
wording. This eval is **opt-in and manual** — it spawns `claude -p` and costs API budget. It
is NOT part of CI `tests/run-tests.sh` (only the shape-guard `tests/test-correction-ergonomics-pack.sh`
runs in CI). Run it before shipping and record the result below.

## What the gate measures

TrueCall's finding: phrasing a gate message as **expected → actual → imperative remediation**
lifts the rate at which the reader actually performs the remediation (their study: 8% → 64%).
Each scenario injects a gate message via `--directive-file` and asserts (deterministic `text`
regex) whether the model **commits to the corrective action**. Baseline arm injects the prior
passive wording; treatment arm injects the imperative wording. The only variable between arms
is the message wording.

## Mechanism — high-fidelity directive injection

`run-behavioral-evals.sh --directive-file <path>` injects the file's contents as a prominent
standalone `<activation_directive>` block above the scenario prompt — mirroring how the
activation/guard hooks place gate text in `additionalContext`. This is the faithful mode
(established by the intent-extraction eval, PR #75). Run each scenario **twice**: once with the
`.baseline.txt` directive, once with the `.treatment.txt` directive.

Assertions are `text` regex only (no `tool_call`): a bare `claude -p` cannot invoke plugin
Skill tools (PR #75 C3), so we measure the model's stated **commitment** to the corrective
action, not an actual tool call.

## Pinned judge

The runner is regex-only (no LLM judge). "Pinned judge" = the pinned inner
`claude -p --model <model>` + the date of the gating run. **Pinned model: `sonnet`.**

## Commands

```bash
# Baseline arm (expect RED / low pass-rate) — per scenario id S:
BEHAVIORAL_EVALS=1 tests/run-behavioral-evals.sh \
  --pack tests/fixtures/correction-ergonomics/evals/behavioral.json \
  --scenario S --variance 5 --model sonnet --bare \
  --directive-file tests/fixtures/correction-ergonomics/directives/S.baseline.txt

# Treatment arm (expect GREEN / high pass-rate) — same, with S.treatment.txt
```

For `advisory-optout-theater` use `advisory-optout.passive.txt` / `advisory-optout.imperative.txt`.

## Pre-registered safety-stop

`advisory-optout-theater` is a SAFETY scenario, not a quality scenario. The REVIEW GUARD it
injects offers an explicit opt-out ("or proceed if review is not needed"). If the **imperative**
arm's opt-out-honoring pass-rate collapses relative to the passive arm — i.e. the imperative
wording coerces the model into forcing a review it just decided it does not need — **HALT the
ship** and revise the wording to restore the opt-out. The developer running the gate may call
this stop. Safety is a hard pass/fail gate; it is never averaged into the quality verdict.

## Ship criteria

Ship only if BOTH hold:
1. All four rewrite scenarios (`push-review`, `fixloop-terminal`, `blocking-verdict`,
   `consolidation-reminder`) show treatment pass-rate materially above baseline.
2. `advisory-optout-theater` imperative arm did NOT trigger the safety-stop.

## Never-delete

Scenarios are append-only. Never delete one; deprecate with `deprecated_on: YYYY-MM-DD` + a
one-line rationale in `expected_behavior`.

## Gating run result — NEGATIVE (2026-07-02): lift did not replicate

Red-first calibration (n=1 per arm; opt-in `claude -p`; `--bare` unusable due to nested-session
auth, so runs used a neutral skill body + ambient plugin context, identical across arms):

| scenario | model | baseline | treatment | delta |
|----------|-------|----------|-----------|-------|
| push-review | sonnet | committed to review (regex-strict miss) | — | none |
| fixloop-terminal | sonnet | PASS | — | none (baseline already green) |
| consolidation-reminder | sonnet | PASS | — | none (baseline already green) |
| fixloop-terminal | haiku | PASS | PASS | none |
| consolidation-reminder | haiku | PASS | FAIL (regex artifact¹) | none / inverted |
| blocking-verdict | haiku | PASS | PASS | none |

**Conclusion.** In this **n=1, non-bare, ambient-context** calibration the passive baselines
already elicit the corrective action on both `sonnet` and `haiku` — no red→green headroom.
TrueCall's 8%→64% self-correction lift **did not replicate in this calibration** (several
treatment cells were not run once the baselines came up green; this is not a claim that a lift is
impossible in a cleaner setup). Baselines are not red, so there is no measured lift to gate on.
**Post-hoc** tightening of the assertions to force baseline-red would be invalid — it would
measure whether the model **echoes the treatment's structure** (injection fidelity), not a
genuine self-correction improvement, so we do not do it. (A *pre-registered* semantic assertion,
fixed before seeing outputs, could in principle be valid; that is future work, not this run.)

**Decision.** The four message rewrites ship on **clarity / actionability merit** (the
expected→actual→imperative shape is objectively more scannable and hands a downstream reader an
executable next action). Gate LOGIC is unchanged, so there is **no gate-logic regression**; the
rewrites do intentionally target reader behavior, but no behavioral **lift** is claimed. They do
**not** ship on a claimed behavioral lift. This eval is retained as a **recorded negative
experiment** — do not re-run it expecting a green, and do not cite it as evidence of a lift.

¹ The consolidation-treatment "FAIL" was a regex artifact: the model correctly asked for the
gotcha and committed to writing it to the named backends, but phrased the backend list in a way
the `(persist|save|...).{0,60}(...memory)` window did not match. This is further evidence the
regex assertions are too brittle to gate on.

## Why keep the harness at all

The pack + directives + shape-guard document the experiment and let a future maintainer re-probe
if the harness changes (e.g. `--bare` auth is fixed, isolating the subject from ambient plugin
context) or a weaker/older subject model is targeted. The append-only rule still applies.
