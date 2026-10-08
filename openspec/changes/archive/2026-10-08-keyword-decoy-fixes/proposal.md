## Why

The keyword-path audit (`keyword-path-audit`, #310) found two prompts that skills' own routing fixtures list as `NO_MATCH` and that the activation hook selects anyway, each through one keyword:

- `authorial-judgment` on "make this error message less generic so users understand what went wrong", through the keyword `less generic`. The trigger was tightened earlier to require a piece of writing before that phrase, and `skills/authorial-judgment/evals/heldout-triggering.md` records the false positive as fixed. The fix was measured on the regex. The keyword kept selecting the prompt.
- `improvement-miner` on "determine improvements to the onboarding flow", through the keyword `mine improvements`, which is a substring of "deter**mine improvements**". The trigger carries a left word boundary for this case and the fixture's comment says so. The keyword path has no word boundary.

## What Changes

- **`less generic` is removed from `authorial-judgment`'s keywords.** The trigger that names the phrase still admits it after a piece of writing ("make this piece less generic").
- **`mine improvements` is removed from `improvement-miner`'s keywords.** The trigger admits the bare phrase at a word boundary, so the keyword added nothing except the match inside a longer word.
- Both in `config/default-triggers.json` and `config/fallback-registry.json`.
- The decision row for `less generic` and both known-decoy rows are removed, which the audit requires in the same change.

## Capabilities

### Modified Capabilities
- `skill-routing`: one requirement added, naming the two prompts and the prompts that must keep routing.

## Impact

`config/default-triggers.json`, `config/fallback-registry.json`, `tests/fixtures/keyword-path/decisions.tsv`, `tests/fixtures/keyword-path/known-decoy-selections.tsv`, `tests/test-keyword-path-audit.sh`.

Measured against a copy of the installed registry (49 available skills), replaying through the real hook with and without the two keywords:

- 53 fixture lines of the two skills: the selection differs on exactly the two decoys. Every `MATCH` line keeps the selection it had.
- 598 distinct typed prompts from one owner's transcripts (2026-09-05 to 2026-10-07): the selection differs on none. None contains either phrase.

A prompt that matched a trigger and one of these keywords scores 20 less. In the replay that changed no selection.

On the sticky-repeat experiment (#333): a removed domain or workflow match can leave a process mandate as the only skill in a block, which is what that experiment's rule counts. The replay above shows no typed prompt affected. Whether to merge before stage A closes is the owner's decision; nothing here needs it sooner.
