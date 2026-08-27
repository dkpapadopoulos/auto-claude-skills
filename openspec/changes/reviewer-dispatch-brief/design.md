# Design: reviewer dispatch brief — delivery contract and idle recovery

## Architecture

Two surfaces, split by who reads them.

### Reviewer-side: the clause must be in the prompt

A reviewer subagent sees exactly one thing: its own `prompt`. Protocol prose in
`SKILL.md` is read by the **lead**, never by the reviewer. So every clause that governs
reviewer behaviour is duplicated into all four lens prompts, and the test asserts it
**per block**. A whole-file needle would pass with the clause in one prompt and absent
from the other three — which is the exact failure shape observed (a correction reached
one reviewer after it had already mutated the shared tree).

Placement is deliberate: the `## Delivery Contract` block sits **before** `## Your Lens`.
The memory this issue derives from says to state it "up front"; a reviewer that runs out
of budget mid-review has already read a contract that tells it to send what it has.

| Clause | Failure it addresses |
|--------|----------------------|
| Time-box 15 min, `REPORT EVEN IF INCOMPLETE` | one reviewer timed out and delivered nothing |
| `Deliver unprompted` + send to `main` | three reviewers went idle holding complete reports |
| `Silence is not a pass` | idle read as "done, nothing found" |
| `do not manufacture findings` | keeps the delivery metric ungameable (issue #204 safety clause) |
| `git worktree add --detach` | one reviewer ran 8 mutations in the shared tree during a 12-min suite run |
| VERIFIED-vs-INFERRED labelling | pairs with the existing `Evidence: observable failure path` contract |

### Lead-side: a mechanism, not an assertion

`Verification` already claimed the outcome. Issue #204's finding is that nothing produced
it. Protocol §3 now carries a reviewer-state table, so each state has a defined action
instead of leaving "idle" to be read as success.

The ordering inside that table is the non-obvious part. **The first move on a quiet agent
is `git status`/`git log`, not re-dispatch.** Confirmed across a 6-task branch: of five
stalled subagents, three had the completed work sitting uncommitted in the tree. A
re-dispatch-first protocol duplicates real work — this was observed four separate times.

**Chase twice.** Two reviewers had to be nudged twice before delivering, and both were
holding substantive findings; one caught a dead-agent reference the lead's own scan
missed. A single-nudge write-off loses real findings, so the floor is two.

**Undelivered ≠ clean.** The verdict writer already has `could-not-review`. Wiring the
uncovered-lens case to it keeps "we could not review" distinguishable from "we reviewed
and found nothing" — the same distinction the anti-fabrication clause protects on the
reviewer side.

## Why the deterministic gate is content-only

The gate asserts that the clauses are present, not that reviewers obey them. That is the
same deliberate presence-not-quality bar the repo's other skill-content gates take
(`tests/test-skill-content-coverage.sh`). Behavioural conformance is the A/B contract's
other leg, pinned in `tests/fixtures/agent-team-review/dispatch-brief/pinned-range.txt`.

## Non-vacuity

Three ways this test could pass while proving nothing, each pinned:

1. **Empty/unreadable fixture** ⇒ the per-lens loop iterates zero needles. A floor of 7
   needles is asserted before the loop (mutation-verified: emptying the fixture drops the
   run count 55 → 19 and fails that one control).
2. **Moved anchors** ⇒ an unmatched `name: "<lens>"` yields an empty block and every
   clause assertion for that lens vanishes. Empty extraction is an explicit failure.
3. **Last block running to EOF** ⇒ `adversarial-reviewer` is the final prompt, so a range
   terminating only on the next `name: "` would absorb Red Flags and Verification, and a
   clause misplaced there would false-pass. The range also stops at the next top-level
   `## ` heading (mutation-verified: moving a clause from the adversarial prompt into
   `## Red Flags` fails).

All four mutations plus the M1 single-lens strip were run and each failed exactly the
assertion it should, with a green control before and after.

## Alternatives rejected

- **State the contract once in Protocol §2 and reference it from the prompts.** The
  reviewer never reads Protocol §2. This is precisely the bug.
- **A shared `references/dispatch-brief.md` interpolated at dispatch time.** The prompts
  are literal templates a model copies; there is no interpolation step to hook. It would
  add an indirection the model must resolve at exactly the moment it is under budget
  pressure.
- **Make undelivered reviewers a hard block on SHIP.** Out of proportion and untested;
  the repo's documented discipline is warn-first-and-measure (deny variants shipped
  without a backtest ran 56–94% false-block). The verdict downgrade to `could-not-review`
  already records the state without blocking.
