# Remove the `newsletter` keyword from authorial-judgment

## Why

Issue #410. The keyword path admits a skill on a plain substring match, independently of its triggers (#310). All four `authorial-judgment` triggers that name a newsletter require a writing verb or a topic marker beside it; the keyword `newsletter` admitted any prompt holding the word. The keyword ledger had classed it `gap` since 2026-10-08 with no field observation.

There is one now. On 2026-10-27 a prompt ending "what other improvements did we gather from the AI newsletter emails?" selected `authorial-judgment` through the keyword alone: a question about a digest, not a writing task. Run through the real hook with the shipped entry before this change, the audit reports that prompt as selected via `keywords`; no trigger matches it.

The owner decided to delete the keyword (2026-11-18). This is a precision-for-recall trade: a prompt that mentions a newsletter with no writing verb, topic marker or other keyword no longer selects the skill.

## What Changes

- `newsletter` is removed from the `keywords` of `authorial-judgment` in `config/default-triggers.json` and `config/fallback-registry.json`. The triggers are unchanged.
- The observed prompt becomes a `NO_MATCH` line of the skill's routing fixture, so the keyword-path audit runs it through the real hook on every run.
- The ledger row for the keyword is removed (a deleted keyword has no row).
- `tests/test-keyword-path-audit.sh` pins both config files and shows that putting the keyword back fails the audit with the observed prompt.

## Impact

- Affected spec: `skill-routing` (one requirement added).
- Affected code: the two config files; no hook changes.
- Still selected, measured through the hook: "punch up this newsletter draft so it sounds human" (the fixture's `MATCH` line).
