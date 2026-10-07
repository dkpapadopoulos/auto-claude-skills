## Why

The activation hook admits a skill two ways: a trigger regex matches, or one of the skill's `keywords` is a substring of the prompt. The two paths are independent. A precision constraint written into a trigger is absent from the keyword path. Only `prototype-lab`'s shipped keywords were tested against its trigger; for the other 13 keyword-carrying skills `tests/test-regex-fixtures.sh` evaluates the regex alone.

PR #309 met this once. It narrowed `prototype-lab`'s side-by-side trigger, measured the regex, and fixed one of six false dispatches; the other five kept arriving through the `side by side` keyword with the suite green. Issue #310 asked for the general check.

Measured on 2026-10-08 through the real hook, 110 shipped keywords across 14 skills:

- 68 are covered: a trigger admits the skill on the bare keyword anyway.
- 30 admit the skill on their own, across 10 skills, four of them process skills.
- 12 can never fire: 3 are under the hook's six-character floor and 9 hold a capital letter, which a lowercased prompt never matches.
- 2 `NO_MATCH` lines that skills' own routing fixtures list as decoys are selected through a keyword: `authorial-judgment` by `less generic`, and `improvement-miner` by `mine improvements` matching inside "determine improvements".

The issue counted seven exposed skills by the shape of their trigger regex. Keyed on what the hook does, two of those seven have no keyword that admits alone, and five skills outside the seven do.

## What Changes

- **A script measures the keyword path through the hook.** `scripts/keyword-path-audit.sh` classifies every keyword as `covered`, `keyword-only` or `inert`, and runs every `MATCH` and `NO_MATCH` line of a keyword-carrying skill's routing fixture through the hook with the skill's shipped entry.
- **Two ledgers hold what was decided.** `tests/fixtures/keyword-path/decisions.tsv` has one row for each keyword that is not covered, with a decision (`recall`, `gap`, `open`) and a reason. `tests/fixtures/keyword-path/known-decoy-selections.tsv` lists the fixture decoys the hook selects today.
- **The audit fails in both directions.** An unrecorded keyword, a row whose class is no longer true, a row for a keyword that is gone, a newly selected decoy, a known decoy that is no longer selected, and a `MATCH` line the hook does not select each fail it. So narrowing a trigger past a keyword fails until someone decides, and a fix has to give its rows back.
- **Could not measure is its own exit status**, never clean and never a finding.

No routing behaviour changes. No keyword, trigger or hook line is edited. The two selected decoys stay selected and are listed as known.

## Capabilities

### Modified Capabilities
- `skill-routing`: two requirements added, for the keyword-path classes and for fixture lines read through the hook.

## Impact

New: `scripts/keyword-path-audit.sh`, `tests/test-keyword-path-audit.sh`, `tests/fixtures/keyword-path/`. Edited: `.claude/rules/routing-state.md` (one bullet), `CLAUDE.md` (a Commands row and a clause in the scoring line), `tests/test-claude-md-rule-split.sh` (the instruction-size ratchet, raised by the bytes just named). The suite gains one file of about a minute.

Not in this change: narrowing or deleting any keyword. The 5 `gap` rows, the 17 `open` rows and the 2 known decoys are the list of what a later change would act on. Removing a domain match can leave a process mandate as the only skill in a block, which is the condition the sticky-repeat experiment (#333) counts, so that change should not land while its stage A is collecting unless the owner chooses to.
