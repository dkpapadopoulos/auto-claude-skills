# Deliver the reviewer-facing scope rule to the reviewer

## Why

PR #244 added a two-category do-not-flag table to `agent-team-review` §3,
introduced as *"scope rules for what a reviewer raises"*. §3 is protocol prose
that the **lead** reads. A spawned reviewer sees only its own prompt block under
`## Reviewer Spawn Templates`, and none of the four lens prompts carried the
rule — so the half that constrains the lead (never demote a delivered finding on
provenance grounds) was enforced, while the half addressed to reviewers was
claimed and delivered to nobody. Filed as issue #245 item 1.

The issue offered two options: duplicate the rule into each lens prompt, or
reword §3 to stop claiming reviewer-facing scope. The second is cheaper but
retracts a rule that the `adversarial-review` spec already states as a reviewer
obligation ("A reviewer lens MUST NOT raise…"), which would leave the spec
demanding behaviour no prompt asks for.

## What Changes

- Every lens prompt gains an identical `## Scope` block carrying the same two
  categories, their "raise it anyway" exceptions, and the ownership-not-size
  rule. Duplication is the only delivery mechanism a subagent prompt has — the
  same reasoning that already duplicates the Delivery Contract into all four.
- §3 keeps the lead's copy and gains a PAIRED note naming where the reviewer's
  copy lives and which gates pin the two together.
- Three mechanical pins, so the copies cannot drift: per-lens needles in the
  existing `required-clauses.txt` fixture; a block-identity control across the
  four prompts; and a category-SET equality check between §3's table and the
  prompt block. The two-category ceiling is asserted separately on the delivered
  copy in `tests/test-adversarial-governance.sh`, because a third category added
  to both copies satisfies set equality.

## Impact

- `skills/agent-team-review/SKILL.md` — prose only, no routing or config change.
- `tests/test-reviewer-dispatch-brief.sh`, `tests/test-adversarial-governance.sh`,
  `tests/fixtures/agent-team-review/dispatch-brief/required-clauses.txt`.
- Capability: `adversarial-review`.
