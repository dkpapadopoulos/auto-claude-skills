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
