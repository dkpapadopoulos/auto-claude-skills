## Why

The REVIEW gate credits a review only when one of four skills returns through the Skill tool. Three ways of actually reviewing therefore earn nothing, and the push is denied:

- **A typed slash command.** `/superpowers:requesting-code-review` or `/code-review` typed by the owner expands the skill into the conversation without a Skill tool call, so `PostToolUse(Skill)` never fires (measured on Claude Code 2.1.308: `UserPromptSubmit` carries the raw `/name args`, and no Skill hook fires). The routing hook exits on a leading `/` before writing anything.
- **Equivalent review skills.** A model-invoked `code-review`, `pr-review-toolkit:review-pr` or `security-review` is not on the credit list.
- **A reviewer agent that actually ran.** `reviewer-returned` is already written to the branch ledger when a dispatched reviewer's completion is observed, with the commit it reviewed. No gate reads it.

Separately, the panel adjudicator was closed INCONCLUSIVE on 2026-10-25 because the evidence it needed was gone by the time anyone could judge it (archive `2026-10-25-shadow-panel-adjudication`). The owner chose a successor that captures evidence when it happens and computes a mechanical rate instead of using judges. The REVIEW shadow record is the natural carrier: at push time the guard already knows which review evidence exists and which commit it covers.

## What Changes

- **Typed slash credit.** The routing hook, before its early exit on `/`, recognises a typed command naming a credited skill and records it through the existing completion hook, so typed and tool-invoked skills leave identical evidence.
- **Equivalent review skills** credit REVIEW: `code-review`, `review-pr`, `security-review`, alongside today's four.
- **A returned reviewer whose reviewed commit covers the pushed changes** credits REVIEW status.
- **Shadow records are stamped at push time** with the payload `session_id`, the push `tool_use_id`, the Claude Code and plugin versions; the REVIEW record also gets `review_coverage` and `review_witness`. A schema bump, not a predicate bump.
- **The REVIEW reader reports an evidence-miss rate**: the share of would-block episodes in which covering review evidence existed. Diagnostic only.

## Capabilities

### Modified Capabilities

- `pdlc-safety`: "Gating milestones enter composition state only through invocation evidence" gains a third path, a typed slash command naming the skill. Three requirements are added: typed and equivalent review commands credit REVIEW; a returned reviewer covering the push credits REVIEW; shadow records carry harness ids, versions and review coverage, and the reader's evidence-miss rate is diagnostic.

## Impact

- `hooks/skill-activation-hook.sh`, `hooks/skill-completion-hook.sh`, `hooks/openspec-guard.sh`, `hooks/lib/review-shadow.sh`, `hooks/lib/implement-shadow.sh`, `hooks/lib/verify-shadow.sh`, `scripts/review-shadow-adjudicate.sh`, their tests, `docs/enforcement-map.md`, `CHANGELOG.md`.
- The allow path widens only for events at least as costly as today's Skill invocation; the decision rules, the shadow predicates and the registered definitions do not change.
