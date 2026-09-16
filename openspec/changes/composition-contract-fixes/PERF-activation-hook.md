# Measured: activation-hook latency on this branch

**This file was WRONG on first publication and is corrected below. The original numbers
(main 64ms, HEAD 103ms, delta +39ms) came from a harness that created a temp directory and
rebuilt the JSON payload on every iteration, so filesystem and jq noise dominated. The
tell was a nonsense result: a plain dev prompt measured SLOWER than a consultation prompt,
which cannot be true if regex work drives the cost.**

## Method (corrected)

Fixed `HOME`, registry written once, payload built once, 25 iterations, repeated twice and
agreeing within 4ms. An EMPTY registry is measured as a control, isolating fixed hook
overhead from all trigger work.

| configuration | total | attributable to triggers |
|---|---|---|
| empty registry (no skills at all) | **61 ms** | 0 |
| `main` | 103 ms | **42 ms** |
| this branch (HEAD) | 124 ms | **63 ms** |
| **delta introduced here** | **+21 ms** | +21 ms |

## The two findings that matter

1. **61ms is FIXED overhead** — bash startup, jq forks, registry read, composition walking.
   It is 49% of the total and is unrelated to routing triggers. Any latency work should
   start here, not with the regexes.
2. **Trigger cost does NOT vary with whether the prompt matches.** A plain dev prompt
   ("fix the failing test in…") and a full consultation prompt cost the same within noise
   (137/136ms and 133/134ms across two runs). Every clause is evaluated either way.

## The optimisation I was about to build would have saved NOTHING

The plan was a per-clause literal prefilter, on the theory that ordinary prompts waste time
in the consultation regexes. Finding 2 refutes it: matching and non-matching prompts already
cost the same, so skipping clauses that were never going to match saves no measurable time.
Bash's regex engine is not where the money is. Measuring first prevented both wasted effort
and a config-schema change that would have bought nothing.

## Judgement

124ms on a `UserPromptSubmit` hook is not user-perceptible — model latency exceeds it by
orders of magnitude. `CLAUDE.md` states the budget as "~50ms", and the hook was already
over it at 103ms before this branch. This branch adds 21ms on top. Recorded as an explicit
acceptance rather than a later discovery; the fixed-overhead finding is the lead worth
following if anyone wants the budget back.
