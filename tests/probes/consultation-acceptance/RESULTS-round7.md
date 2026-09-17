# Round 7 acceptance — measured 2026-09-17

Set: `cases-round7.json`, sha256 `e1fd27419dcf2207663ca61f25e0c07b4ca2b950a382d489d737437b9f7d9f5b`.
It was frozen in commit `627c696` before any measurement. The set has 48 prompts, 6 per
contract. In each of `standalone_panel`, `models_interact` and `synthesized_plan`, 4 of
the 6 prompts name no vendor.

Measured on `main` at `3367e49` with the round 5/6
scoring script, unchanged: synthetic HOME, the real hook, no model call. Raw output is in
`RESULTS-round7.txt`. Between `0f86729` (round 6) and `3367e49`, `config/` and the
activation hook did not change; the only other routing-path change is a cleanup line in
`session-start-hook.sh`.

## Result

| | round 7 | round 6 (as measured) |
|---|---|---|
| Precision | **16/18** | 17/18 |
| Recall | **12/30 (40%)** | 14/30 (46%) |

Recall by contract: `answer_critique` 4/6, `second_opinion` 3/6, `models_interact` 3/6,
`standalone_panel` 1/6, `synthesized_plan` 1/6.

Non-consultation contracts: `vendor_as_subject` 6/6, `asks_me` 6/6, `plain_dev` 4/6.

**Nothing was tuned against this set. These figures are the result.**

## How the set was controlled

The author was a subagent given the contract definitions only.

- **Tool use.** Its transcript shows exactly two tool calls, both `Write` to its two output
  files.
- **Blocklisted vocabulary.** The author was given the vocabulary earlier rounds found
  leaking and treated it as a blocklist. That vocabulary covers skill names, description
  phrases, words the triggers rely on, and feature names from commit subjects.
  Independently verified: none of `independent`, `merge`, `synthesi*`, `panel`,
  `consult*`, `cross-family`, `cross-model`, `two-mode`, `roster`, `egress`, `dispatch`,
  `second opinion`, `multiple models` or `perspectives` appears in any of the 30
  consultation prompts. These words appear only in the non-consultation prompts, in
  ordinary senses, as the brief required.
- **Overlap.** No prompt appears verbatim in the text under `tests/fixtures/` or
  `tests/probes/`.
- **Leaks that could not be removed.** The git-status preamble and the skill listing still
  leaked. The author's account of that is in `round7-provenance.txt`. It also names
  "reconcile", "combine", "fold" and "stitch" as near-synonyms of `merge` that it used.

## The two false dispatches: open, not fixed

- **`pd-5` routed to `panel`.** The prompt was "hr tool: interview panel page should show
  each one of the reviewers' raw answers verbatim before the hiring manager sees scores".
  - **Cause.** The vendor-free panel clause matched. Round 6 added a requirement for an
    answer-noun near the delivery word, and "raw answers" is one. Human reviewers and AI
    participants use the same words, so the lexical rule has reached its limit here.
  - **Impact.** This is the external-vendor class. Since PR #255 the dispatcher refuses to
    send without the user's approval of the exact package, so the harm is now an
    unwanted consent question, not an unapproved send.
- **`pd-3` routed to `design-debate`.** The prompt was "education app: the debate timer
  doesnt reset between the opening and rebuttal rounds, find the bug".
  - **Cause.** The bare word `debate` in design-debate's first trigger clause matched.
  - **Impact.** That skill stays local.

Fixing either one narrows a trigger and therefore costs recall. That is a product
decision, so it was escalated rather than tuned against this set. Both prompts were
added to the negative corpus (`tests/probes/negative-corpus/`) as known, open lines, so
a future fix has a regression target.

## Misses

- **Total.** 18 misses.
- **No vendor named.** 10 of the 18 name no vendor. As in earlier rounds, the vendor-free
  half is the hard part.
- **Wrong contract.** 3 misses routed to a consultation skill, but not the right one:
  - `sp-2` routed to `second-opinion` instead of `panel`.
  - `sy-1` routed to `panel` instead of `synthesize`.
  - `sy-3` routed to `second-opinion` and `panel` instead of `synthesize`.

  Each still sends to an outside vendor through a skill whose send requires the user's
  approval.

## Status

**SPENT.** The two false dispatches were inspected to diagnose them. The 18 misses were
looked at only as the per-contract and vendor-free counts above, not prompt by prompt.
A round 8 needs a new author.
