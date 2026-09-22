
## `regress-fp-*.md` — false positives found in review

Three non-blocking reviews that the first classifier called `blocking`, because
it anchored its section on ANY line containing the phrase rather than on a
section header. Each would have submitted `CHANGES_REQUESTED` on a clean PR —
blocking a human's merge, undeletable, and reported as `findings-open` for a
HEAD that nothing blocked.

- `regress-fp-terse-no-blocking.md` — "No blocking issues. Two non-blocking
  notes:" followed by bullets. This shape is **licensed by the workflow's own
  prompt**: "If nothing blocks and nothing's worth recommending, say so
  tersely… the review can be 4 lines."
- `regress-fp-prose-none-found.md` — "No blocking issues found, though two
  things are worth noting:".
- `regress-fp-non-blocking-phrase.md` — "Two non-blocking issues are worth a
  look:", where the anchor substring appears inside *non-blocking*.

All three must classify `none` or `unknown`, never `blocking`. They are
authored, not observed, and named apart from the `observed-`/`derived-` sets.
