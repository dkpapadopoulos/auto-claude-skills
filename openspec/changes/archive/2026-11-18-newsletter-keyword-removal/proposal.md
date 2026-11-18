# Remove the `newsletter` keyword from authorial-judgment

## Why

Issue #410. The keyword path admits a skill on a plain substring match, independently of its triggers (#310). None of the four `authorial-judgment` triggers that name a newsletter admits the bare word: three require a writing verb or a topic marker beside it and one a make/keep/help verb with a quality phrase. The keyword `newsletter` admitted any prompt holding the word. The keyword ledger had classed it `gap` since 2026-10-08 with no field observation.

There is one now. On 2026-10-27 a prompt ending "what other improvements did we gather from the AI newsletter emails?" selected `authorial-judgment` through the keyword alone: a question about a digest, not a writing task. Run through the real hook with the shipped entry before this change, the audit reports that prompt as selected via `keywords`; no trigger matches it.

The owner decided to delete the keyword (2026-11-18). This is a precision-for-recall trade, and the recall given up is real. The triggers accept write, draft, author, compose, rewrite, revise and punch up; they do not accept edit, polish, proofread, improve, tighten, review or rework. So these, which the keyword used to admit, now match nothing (checked against the shipped triggers and remaining keywords): "edit my newsletter", "polish my newsletter", "rework my newsletter", and "Give this newsletter issue an editorial pass and return the revised text." (the control prompt of the skill's own 2026-10-27 eval fixture). No `should_trigger` eval query and no fixture `MATCH` line lost its only route. Measured use, 2026-10-27: the router rendered 12 mandates for this skill, all wrong, and every real use named the skill. Widening a trigger to the editing verbs is a separate decision and is not made here.

## What Changes

- `newsletter` is removed from the `keywords` of `authorial-judgment` in `config/default-triggers.json` and `config/fallback-registry.json`. The triggers are unchanged.
- The observed prompt becomes a `NO_MATCH` line of the skill's routing fixture, so the keyword-path audit runs it through the real hook on every run.
- The ledger row for the keyword is removed (a deleted keyword has no row).
- `tests/test-keyword-path-audit.sh` pins both config files and shows that putting the keyword back fails the audit with the observed prompt.

## Impact

- Affected spec: `skill-routing` (one requirement added).
- Affected code: the two config files; no hook changes.
- Still selected, measured through the hook: "punch up this newsletter draft so it sounds human" (the fixture's `MATCH` line).
- No longer selected: newsletter requests in editing-verb wording, listed under Why.
