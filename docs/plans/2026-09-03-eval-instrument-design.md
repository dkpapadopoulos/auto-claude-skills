# Behavioral-eval instrument: root cause and design (#94)

## Root cause

Every repo-side input is byte-identical to the one that produced the baseline:
SKILL.md (2026-07-03), pack (2026-07-04), baseline (`generated_utc`
2026-07-03), `run-eval-pack.sh` / `run-behavioral-evals.sh` (2026-07-04),
workflow incl. CLI pin `2.1.198` and `--model claude-sonnet-5` (2026-07-04,
one commit). Plugin injection does NOT reach the subject: the runner builds
the prompt from the SKILL.md body plus the scenario, the workflow passes no
`--directive-file`, the repo has no `.claude/settings.json`, and CI never
installs the plugin. So #221 and friends cannot touch it.

Yet two consecutive weekly runs reported 5 and 8 regressions with **one**
overlapping assertion, which itself changed class in the opposite direction.

**Mechanism.** Regressions are detected by a *label transition*, where the
label comes from `int(n*0.9)` / `int(n*0.5)`. At the production n=3 that is
2 and 1, so 2-or-3 passes = "stable", exactly 1 = "flaky", 0 = "broken", and
every transition is a one- or two-sample flip. The false-regression rate is
not a flat 5%: it ranges from 0.03% at true p=0.99 to ~30% at p=0.5, and
several baseline assertions already carry "flaky" labels — precisely the
regime that yields 6–30% spurious regressions per assertion per week.

**Confirming statistic.** Expected overlap between two independent noise
draws of size 5 and 8 over 61 assertions is 61 x (5/61) x (8/61) ~= 0.66.
Observed overlap is 1. The two reports are indistinguishable from noise.

## Decisions

1. **n=3 admits no significant result at all.** Exact Fisher: the most
   extreme table (3/3 vs 0/3) gives p = 0.10. Minimum equal-n to detect
   100%->50% is n=9; 100%->67% is n=14; with Bonferroni over 61 assertions,
   n=20 and n=29. A statistical criterion at n=3 could never fire, so adding
   one without raising n would replace noisy output with silent output.
2. **Persistence beats significance at current cost.** Requiring the same
   assertion to degrade in two consecutive runs costs zero extra LLM calls
   and would have suppressed both observed reports outright.
3. **Provenance is a hard skip, not a warning.** A better-powered test does
   not fix a floating model alias: at n=29 an alias revision would produce a
   large, stable, well-replicated "regression" every week forever. On a
   provenance mismatch the diff must not run at all.
4. **Raising n is deferred, not rejected.** The scenario loop is sequential
   inside a 45-minute job timeout; n=20-29 likely exceeds it. Parallelising
   the loop (scenarios share no state) is the enabling change and is its own
   piece of work.

## Open question, high impact

Iteration artifacts from the 2026-08-24 CI run record
`model: claude-haiku-4-5-20251001` for all 42 iterations, though the
workflow requests `--model claude-sonnet-5` and that flag *is* correctly
forwarded to the inner `claude -p`. Locally, a single-model run reports one
`modelUsage` key equal to the requested model. The stored artifact keeps
only the extracted string, so it cannot distinguish "CI evaluated Haiku"
from "modelUsage held several keys and `keys[0]` picked Haiku
alphabetically". Recording the full `modelUsage` map answers this on the
next run. Until then, no conclusion about *which model these evals measure*
is safe.

## Out of scope

Raising variance; parallelising the scenario loop; re-baselining; any change
to `skills/incident-analysis/SKILL.md` (it did not regress).

## Residual risk after this change (measured, not eliminated)

Adversarial review established that the persistence filter **reduces** the
false-regression rate; it does not remove it. Assuming each week's draw is
independent conditional on a fixed true rate, the reported probability is the
single-week probability squared:

| true pass rate | single week | after persistence |
|---|---|---|
| 0.90-0.99 (near-ceiling) | 0.03%-2.8% | 0.00003%-0.08% — effectively solved |
| 0.50-0.70 (already "flaky" at baseline) | 21.6%-50% | **4.7%-25%** |

With several flaky-baseline assertions among the pack's 61, expect on the order
of 0.3-1 false REGRESSED reports per run. That is a large improvement on the
observed 5-8, but it is **not zero**, and a REGRESSED on an assertion whose
baseline class is already `flaky` deserves continued scepticism.

Two options were deliberately NOT taken, and both remain open:
- requiring three consecutive runs (rather than two) for assertions whose
  baseline class is `flaky` — cheap, but trades detection latency for quiet;
- raising the variance, which is the only route to real statistical power and
  is blocked by the sequential scenario loop inside the 45-minute job timeout.

## Defects found in review and fixed before merge

1. **The baseline writer never received the classification fix.** `classify()`
   was corrected to compare the rate, but the `--update-baseline` writer kept a
   second copy of the truncated-count rule, and the compare path read the
   stored label rather than recomputing. A 17/19 (89%) assertion was stored
   "stable" and compared as "flaky", manufacturing a permanent REGRESSED for a
   rate that never moved — the exact failure this work exists to remove. Fixed
   by making the compare path recompute from the stored counts, so `classify()`
   is the single authority and the two cannot diverge again.
2. **A watch-only run closed the tracking issue with "Clean run".** Suppressing
   first-occurrence degradations made those runs exit 0, and the workflow closes
   the issue on exit 0. A real, sustained regression whose weekly draw happened
   to look fine could therefore flap between `watch` and closed-as-clean
   indefinitely, with no issue ever saying "still watching". Fixed with a
   `## Watching` report section that the workflow checks before closing.

## Second review round — findings and disposition

A second reviewer found one Critical the first round missed, plus four
Important and several Minor. Fixed: N1-N8, N11, N12. Two were deliberately
left, and are recorded here rather than silently dropped:

- **N9** `pack-measured.json` is written unconditionally to `dirname(REPORT)`,
  so two runs sharing a report directory clobber each other. Harmless today —
  the workflow serialises via `concurrency` — but it is shared mutable state
  with no run identity, and a second consumer would need one.
- **N10** the recalibration table interpolates `subject_models` / `cli_version`
  into markdown without escaping `|`, unlike assertion descriptions, and that
  table is embedded in the issue body. These strings are CLI metadata rather
  than subject output, so the structured-only guarantee (never relay model text
  outbound) is not weakened; but the canary tests do not cover the new fields.

**N1 is the finding worth remembering.** The fix for "an exit-0 run can carry an
unresolved degradation" guarded the issue-close with a report HEADING. The
recalibration path emits no watch rows, so the loudest state in the design was
invisible to that guard and closed the issue announcing "Clean run" over a
comparison it had explicitly declined to perform. The lesson is not "add the
other heading": a workflow that branches on prose is one rewording away from
silently reverting. Status is now written as DATA (`pack-status.txt`) and the
close happens only on `clean`.

**N3/N4 share one root cause worth stating plainly.** The deterministic mock can
only produce 0/n and n/n — exactly the rates where the truncated-count rule and
the rate rule AGREE. So no end-to-end test in this change could distinguish
them, and reverting either classifier left its suite green. That blind spot is
why the original bug shipped at all. `mock-claude-cycle.sh` now produces an
intermediate rate (2/3), and both classifiers are pinned at it.
