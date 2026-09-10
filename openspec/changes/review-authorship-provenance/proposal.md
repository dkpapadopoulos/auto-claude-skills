# Record review authorship provenance on the verdict artifact

## Why

`agent-team-review`'s authorship guard asks a context that reviewed its own diff
to withdraw the independence claim, and says plainly that nothing else will
record it. That was accurate: the declaration existed only as prose in a report,
so nothing downstream could tell a dispatched review from a self-review. Issue
#245 item 2, carried over from PR #244.

Live evidence from the session that produced #244: an independent reviewer was
dispatched, returned a blocking finding that changed the code, and the REVIEW
milestone was credited 39 minutes later by the `Skill()` return at a different
sha. Invoking the skill and reading one's own diff produces the same record.
Provenance is the part that is currently unrecoverable.

## What Changes

- `record-review-verdict.sh` gains `--self-authored` and always records an
  `independence` field: `self-authored`, `dispatch-observed`, `pr-review-imported`,
  or `unknown`. Each value is named for what was measured, never for the conclusion a
  reader would like to draw. `dispatch-observed` rests on `reviewer-ran`, which witnesses
  a DISPATCH — never a return, and never that the subagent read this diff — so any
  reviewer dispatched earlier on the branch sets it; calling it `independent` would
  assert of a stale observation exactly what the `unknown` default refuses to assert of
  an absent one. `pr-review-imported` is deliberately NOT folded into it: the import path
  runs `gh pr view` and observes no dispatch at all, and nothing compares the PR
  reviewer's identity against the diff's author, so it shows a review EXISTS rather than
  that it was independent. Both distinctions came from review findings.
- `schema_version` 2 → 3. `predicate_version` is untouched — this describes a
  record, it does not change any fire condition, so existing shadow records stay
  poolable. The active `observed-dispatch-telemetry` delta pinned the literal value 2,
  so this change AMENDS that clause in place rather than narrating a supersession the
  spec corpus does not record — two active deltas asserting different literals for the
  same field is a contradiction `openspec validate` passes straight over (review finding).
- The skill's authorship guard and its verdict-recording rules name the flag, so
  the prose and the mechanism are pinned to each other in both directions.

## Design notes

**Why the artifact and not the branch ledger.** #245 suggested recording
`independence: false` on the ledger entry. Two reasons not to. The ledger
record's content is the documented `<sha> <utc-ts>` pair, read by position
(`branch_ledger_sha` cuts field 1) — #133 chose a sidecar over widening it for
exactly this. More importantly, an ABSENT sidecar is indistinguishable from "the
review was independent", so every miss mode `branch-ledger.sh` already documents
(a review recorded on a task branch and a push made from an integration branch;
detached HEAD, which re-keys on every commit) would read as an independence
claim. On the artifact the field is always present, and a record without it is a
schema-2 record rather than an assertion about the review.

**Why an admission outranks an observation.** `self-authored` wins over an
observed dispatch. A witnessed spawn proves a subagent ran; it cannot show the
subagent reviewed *this* diff from a context that did not write it. Ranking the
telemetry higher would let the one honest declaration the skill asks for be
overwritten by a signal that does not contradict it.

**Why the default is `unknown`, never `independent`.** An absent signal is not
evidence of independence. Defaulting the other way would manufacture, for free,
exactly the claim #197 exists to stop being asserted.

## Impact

- `scripts/record-review-verdict.sh`, `skills/agent-team-review/SKILL.md`.
- `tests/test-review-verdict.sh`, `tests/test-adversarial-governance.sh`.
- No hook change; the push gate does not read the field, and a test asserts it.
- Capability: `pdlc-safety`.
