# Design: routing progress truth

Retrospective: written after PR #338 merged.

## Architecture

The composition state file becomes `{chain, current_index, completed, assumed, updated_at}`.

- Writer of `.completed`: `hooks/skill-completion-hook.sh` only (unchanged code). The walker carries the on-disk list forward when the chain is unchanged.
- Writer of `.assumed`: the walker in `hooks/skill-activation-hook.sh`. It is the union of the computed prefix with the on-disk list, in chain order, less anything confirmed.
- Readers: sticky composition and `_comp_active` count chain steps present in either list. The chain display renders `[DONE]` from `.completed` alone. The push guard is unchanged.

## Decisions & Trade-offs

- **Split the lists, keep the schedule.** The alternative, stopping a bare reply from advancing the walk at all, was preferred by a cross-family review (six acknowledgements are no evidence that anything ran). It changes which step is mandated, with an unmeasured effect on whether review and verification still get invoked, so it is left as an owner decision.
- **All walker inference is assumed**, including the steps before a prompt whose own words anchor later. A prompt can authorise skipping a step; it does not establish that the step ran.
- **The current step stays a count.** A first-gap computation would be more correct when a step is invoked out of order, and would change the schedule in those states. Old hook against new through the real guard is identical turn for turn on eleven multi-turn sessions, apart from the turns after a cancel.
- **`_comp_active` had to follow.** It compared the chain against `.completed` alone. Left as it was, a chain walked to its end stayed live for ever and a four-letter prompt was routed instead of dropped. Found in review, after the first commit.

## Known limits

- A state file written by an older build keeps the inferred names it already held in `.completed` until its chain changes.
- A Skill that returned before any chain was armed renders `[DONE?]`: not confirmed, which is not the same as not done.
