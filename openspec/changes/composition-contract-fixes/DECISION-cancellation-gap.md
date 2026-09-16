# Decision: the cancellation gap is pinned, not fixed

**Status: decided, deliberately not fixed. Pinned by
`tests/test-push-gate-consultation-bypass.sh`.**

## What it is

A bare pure-cancel prompt — `cancel`, `stop`, `nevermind` — deletes
`~/.claude/.skill-composition-state-<token>`. `hooks/openspec-guard.sh` gates its entire
composition-chain block on that file existing, so with no file, `deny:chain-review` and
`deny:chain-verify` do not run. The same mechanism as the C3 bypass fixed in `9e80b20`,
reached by a different route.

Longer cancellations do NOT do this: `cancel that workflow` and `actually never mind,
forget the whole thing` fail the whole-prompt-anchored pattern, so state survives.

## It is pre-existing

Measured on the tree predating any consultation work: identical behaviour. An earlier
comparison in this session suggested otherwise and was a **probe artifact** — the harness
never `cd`'d, so the guard measured one worktree's HEAD against another worktree's
seeded verdict, and routing-governance denied for that unrelated reason.

## Measured severity: 1 of 8 states

Across all combinations of (review evidence present, clean verdict present, cancelled),
cancelling changes the push decision in exactly one cell — where **both** are already
present:

| review | verdict | cancelled | push |
|---|---|---|---|
| no | no | no / yes | deny / deny |
| yes | no | no / yes | deny / deny |
| no | yes | no / yes | deny / deny |
| yes | yes | no | deny |
| yes | yes | **yes** | **allow** |

So it is not "type cancel to skip the gates". It downgrades chain-VERIFY to
verdict-VERIFY: the chain check was denying because the VERIFY *milestone* was absent
from `.completed`, while the global gate accepts a clean `project-verification` verdict
covering HEAD. This repo holds those to be different things
(`project-verification-alone-does-not-unblock-push`), which is why it is a gap at all.

## Why it is not fixed here

1. **It is outside these four contracts.** C1–C4 concern consultation routing and merge
   evidence. Cancellation semantics are a different subsystem with different users.
2. **The obvious fix false-blocks.** Preserving state on cancel means a user who
   genuinely abandoned a workflow, genuinely reviewed, and genuinely verified is still
   denied by the abandoned chain's milestones. That is a real workflow, and trading a
   1-in-8 downgrade for a new class of false block is not obviously correct.
3. **The right fix is a semantic decision, not a patch.** It requires answering "does
   abandoning a workflow waive its shipping gates?" — which is a product question about
   what cancellation means, and it should be decided deliberately rather than absorbed
   into a routing change.

## What guards it meanwhile

Three cells in `tests/test-push-gate-consultation-bypass.sh` assert that cancelling does
NOT help without full evidence — `none`, `review-only`, `verdict-only` all still deny.
They fail if the gap ever **widens**, i.e. if cancelling starts helping in a state where
it does not help today. They do not assert the 1-in-8 cell, because that is the behaviour
being accepted, not a property being defended.

## If someone picks this up

The decision to revisit is "what does cancellation mean for shipping obligations", and
the cheap instrument already exists: the eight-cell matrix above, reproducible against
the real guard. Start by deciding the semantics, then measure the matrix again.
