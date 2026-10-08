# Design: two keywords that selected their own skills' decoys

## Architecture

No code changes. Two strings are deleted from two `keywords` arrays, in the shipped config and its fallback mirror. The keyword-path audit holds the result for admission: with no known-decoy rows left, any `NO_MATCH` line of a keyword-carrying skill that the hook selects fails it, and every `MATCH` line must still be selected. It does not hold ranking, which the replay in the proposal measured instead.

## Trade-offs

- **Deleting rather than narrowing.** A keyword is a plain substring. A leading space would keep `mine improvements` out of "determine improvements"; nothing comparable separates an error message from a piece of writing for `less generic`. Both skills already carry the trigger form, so a narrowed keyword would add only 20 points to prompts the trigger admits anyway.
- **Prompts that reach the skill only through the keyword are lost.** For `less generic` those are prompts that ask for something less generic without naming a piece of writing, which is what the fixture decoy and the skill's eval notes say must not route. For `mine improvements` they are prompts where the phrase is the tail of a longer word.
- **A matching prompt scores 20 less.** No selection changed in the replay of fixture lines and typed prompts against the installed registry.

## Dissenting views

- **Leave `more human` in.** It goes around the same trigger alternative as `less generic`. Kept, because no fixture line or field observation says what should happen to it; it stays a `gap` row for the owner.
- **Give the keyword path a word boundary instead.** That would fix `mine improvements` and every future case of its kind. It changes the hook's scoring for all 108 keywords and is a different change, with its own measurement.

## Decisions

1. Fix only what a fixture already rules on. The other `gap` and `open` rows are precision and recall choices for the owner.
2. Remove the ledger rows in the same commit, as the audit demands.
3. Keep the cells that prove the audit sees each defect, by putting each keyword back on a copy of the config.
