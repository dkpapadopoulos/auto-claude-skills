# Measured: activation-hook latency on this branch

Measured 2026-09-16, 10 invocations each, identical harness, same machine.
Harness overhead (mktemp + jq + cp, hook replaced by `true`) measured separately at 11ms
and subtracted.

| | hook time |
|---|---|
| `main` | **64 ms** |
| this branch (HEAD) | **103 ms** |
| delta introduced here | **+39 ms (+61%)** |

`CLAUDE.md` states the activation hook budget as "~50ms".

## Two separate facts, and conflating them would be wrong

1. **The hook was ALREADY over budget before this branch** — 64ms against a stated ~50ms.
   That is pre-existing and not caused by the consultation work.
2. **This branch adds 39ms on top.** That IS caused by this work: `panel`, `second-opinion`,
   `design-debate` and `synthesize` went from 1+7+1+0 = 9 trigger clauses to 6+9+5+2 = 22,
   several of them long (panel clause 5 is 1499 chars, design-debate clause 4 is 685).

## Why it costs linearly

`hooks/skill-activation-hook.sh::_score_skills` evaluates EVERY trigger regex against the
prompt. There is no short-circuit on first match, and correctly so: `trigger_score`
accumulates across all matching clauses, so stopping early would change scoring.

## Deliberately NOT optimised here

Two obvious fixes were considered and rejected as end-of-session changes:

- **short-circuit on first match** — changes scoring semantics for every skill in the
  registry, not just these four;
- **a cheap per-trigger prefilter** (e.g. a literal substring that must be present before
  the regex runs) — needs a config-schema field and a migration in both
  `default-triggers.json` and `fallback-registry.json`.

Either could be right. Neither should be written quickly and unmeasured at the end of a
long session — that is the shape of most defects this branch had to fix.

## Judgement

103ms on a `UserPromptSubmit` hook is not user-perceptible (model latency dominates by
orders of magnitude), so this is a budget overrun rather than a live problem. But the
budget exists because this is a hot path, and a 61% increase should be a deliberate
acceptance, not a silent one. Recorded here so it is a decision rather than a discovery.
