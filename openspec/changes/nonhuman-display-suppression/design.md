# Design: non-human display suppression

## Architecture

The activation hook already extracts the prompt and a `kind` in one jq fork. This change appends a second definition, `acs_nonhuman`, to that program and derives a third kind:

```
lib kind == "notification"            -> exit, as before (no routing, no state)
lib kind == "prompt" and acs_nonhuman -> kind "nonhuman": _DISPLAY_SUPPRESS is set, everything else runs
otherwise                             -> a prompt, as before
```

`_format_output` builds the block as usual and then skips only the `printf` when `_DISPLAY_SUPPRESS` is set. The last-invoked signal and the composition-state write sit below that print and still run. The "no registry" early path, which prints a phase checkpoint, is suppressed the same way.

## The rule this follows

The hook already documents, for consultation prompts, that suppressing the chain WALK is a push-gate bypass and that the fix is to suppress what is displayed and never what is written. This change is a second user of that rule. A third user must also go through `_DISPLAY_SUPPRESS`.

## What counts as non-human

- A peer message: after an optional fixed intro line, an `<agent-message from="…">` opening tag, exactly one closing tag, and after it nothing or one line that opens like one of the two harness paragraphs and ends "permission laundering.". "One line" excludes every vertical-space character, not only LF.
- A notice with a reminder: what the shared classifier calls a notification, followed only by `<system-reminder>` blocks.

Anything else is the user: leading text, text on a line after the block, two blocks, an empty `from`, a reminder with no notification before it. A text shape is not authenticated provenance; a user who pastes one of these verbatim gets no routing display for that prompt and nothing else changes.

## Cost

The prompt is cut with `split()` and every regex is anchored at the start of its input; `contains` runs first, so a prompt with neither closing tag costs no regex. The first cut used an unanchored `sub` that was quadratic (50k spaces took 4.6 s) and was replaced after review. A timing cell bounds the regression; it is not a proof of linearity.

## Failure modes

- Either jq definition fails to compile: retried giving up one definition at a time, ending with both replaced by null classifiers. A user prompt is routed in every case.
- The classifier raises on an input: `try … catch false`, so the input is the user.

## Verification

- State identity: 652 human prompts and 745 non-human inputs replayed through the baseline and this change, each in a fresh HOME. Every `.skill-*` state file is byte-identical on all 1,397; a baseline-against-baseline control differs on 0 and the early-exit version on 136.
- Gate decision: `tests/test-push-gate-display-suppression.sh` drives the real `openspec-guard.sh` after each suppressed input. Restoring the early exit fails 12 of its 22 cells.
- On human prompts, mandates and block headers are identical to the baseline on all 652.
