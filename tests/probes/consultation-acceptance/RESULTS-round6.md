# Round 6 acceptance — measured 2026-09-16

Set: `cases-round6.json`, sha256 `ca9c8bac1e0abc0a082ae5e20636f539ed6e0f207598a300e98c4b49642ef73d`
(hashed before measuring). 48 prompts, 6 per contract, 4 of 6 vendor-free in each of the
three contracts the relaxation introduced.

## Result

| | as measured | after fixing the one false dispatch |
|---|---|---|
| Precision | **17/18** | **18/18** |
| Recall | **14/30 (46%)** | 14/30 (unchanged) |

Per contract: models_interact 5/6, second_opinion 3/6, standalone_panel 3/6,
answer_critique 2/6, synthesized_plan 1/6.

## This is the best-controlled set of the six, by some distance

The author was told about round 5's contamination and treated the leaked vocabulary as a
BLOCKLIST rather than a source. Verified independently, not taken on trust: **none** of
`independent`, `merge`, `synthesi*` or `panel` appears in ANY consultation prompt — the
four words the triggers most rely on. Zero verbatim overlap with the 554 strings already
in fixtures and probes.

It also found a leak nobody had accounted for: **the git-status block in the environment
preamble**, which printed recent commit subjects naming the feature under test
("cross-family second opinion (panel/synthesize…)"). That cannot be suppressed by
instruction; it is a standing limit on how clean any in-session held-out set can be.

## The one false dispatch was real, and of the class this branch exists to prevent

`pd-1` — "the review panel on the right collapses whenever the sidebar animates in, and
the two columns stop sitting side by side under 1200px" — routed to `panel`, which
dispatches repository content to an external vendor. Cause: the vendor-free clause
required TWO co-occurring signals, and *"the two"* + *"side by side"* satisfies both in
pure CSS vocabulary. **Two signals are not enough when both are ordinary UI words.**

Fixed by additionally requiring an ANSWER-noun near the delivery word — the contract is
about answers delivered raw, not about layout. Verified: precision 18/18, recall
unchanged, and still exactly 8 hits across the 206-prompt accumulated negative corpus.

## Recall, honestly

46% against a set that deliberately avoided the trigger vocabulary, versus 43% on round 5
which did not. The vendor-free half remains the hard part: 7 of 16 misses name no vendor
at all, and their only signals are ordinary English.

## Status

SPENT for the `pd-1` diagnosis. The other 15 misses were not tuned against and stand as
the honest figure.
