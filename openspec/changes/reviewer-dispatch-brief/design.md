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

## "Runs in CI" is not "blocks merge"

The gate is a `done-gates.yml` step, so it runs on every PR. It **hard-blocks** only once
"Done Gates" is marked Required in GitHub branch protection — a manual repo setting outside
this tree, exactly as `docs/CI.md` and that workflow's own header already state for the two
pre-existing gates. Do not upgrade the wording to "blocks merge" without checking that
setting.

## Why the deterministic gate is content-only

The gate asserts that the clauses are present, not that reviewers obey them. That is the
same deliberate presence-not-quality bar the repo's other skill-content gates take
(`tests/test-skill-content-coverage.sh`). Behavioural conformance is the A/B contract's
other leg, pinned in `tests/fixtures/agent-team-review/dispatch-brief/pinned-range.txt`.

## Non-vacuity

Six ways this test could pass while proving nothing. The first is the one the initial
cut got wrong, and it is the reason there are two authorities rather than one:

1. **A shrinking fixture silently deletes its own assertions.** With the fixture as sole
   authority and only a count floor, review demonstrated a **fully green 49/49 run that
   inverted issue #204's clauses 1 and 2**: delete two needles from `required-clauses.txt`
   (9 → 7, exactly the old floor) and reword the matching clauses in all four prompts to
   say the opposite. A count floor cannot notice this, because the deleted needle takes
   its assertion with it. Fixed by hardcoding the #204 clause anchors in the *test* and
   asserting the fixture still contains each of them (`grep -Fx`, whole-line). The fixture
   may be extended; it may not shrink.
2. **Empty/unreadable/wholly-commented fixture** ⇒ the per-lens loop iterates zero needles.
   The anchor control above trips first; the count floor remains as a second net.
3. **Moved anchors** ⇒ an unmatched `name: "<lens>"` yields an empty block and every clause
   assertion for that lens vanishes. Empty extraction is an explicit failure.
4. **Last block running to EOF** ⇒ `adversarial-reviewer` is the final prompt, so a range
   terminating only on the next `name: "` would absorb Red Flags and Verification, and a
   clause misplaced there would false-pass. The range also stops at the next top-level
   `## ` heading (mutation-verified: moving a clause from the adversarial prompt into
   `## Red Flags` fails).
5. **A hardcoded lens list exempts a fifth lens.** Review demonstrated appending a
   `perf-reviewer` template carrying none of the clauses: green. The population is now
   derived from `SKILL.md` inside `## Reviewer Spawn Templates`, with a floor of 4.
6. **A needle satisfied by a pre-existing fallback pins nothing.** `could-not-review`
   already occurred once at the base commit in `## Record the Review Verdict`, so the
   assertion labelled "undelivered reviewer downgrades the verdict" passed with the entire
   new Protocol §3 paragraph deleted. Lead-side assertions are now scoped to the §3 block
   and anchored on new text. The same class hit `git status` (generic) and the
   `## Verification` mechanism lines (unasserted entirely — the diff's headline claim).

**The anchor set must track the FIXTURE, not the issue.** The first cut of control 1
anchored issue #204's own clauses only, while the fixture grew past them during review, and
the floor was set to the *anchor* count rather than the *fixture* count. All three reviewers
independently found the resulting gap: deleting the three unanchored needles (`mktemp -d`,
the subject-confirmation rule, the VERIFIED/INFERRED rule) landed exactly on the floor and
ran **82/82 green** — a green run that reinstated the fixed-path worktree collision in all
four prompts, i.e. deleted a fix this very change had just made. Every needle is anchored
now and the floor equals the fixture size, so the two controls are independent rather than
one duplicating the other (the mutation now fails 4 assertions: 3 anchors + the floor).

Measured at the current tip, with a green control before and after each: **14 needles, 14
anchors, 102 assertions**; single-lens clause strip ⇒ 1 fail scoped to that lens; emptied
fixture ⇒ 46 run / 15 fail; renamed lens anchor ⇒ block-extraction fail; clause relocated
into `## Red Flags` ⇒ that lens fails; lead-side row deleted ⇒ fail. Counts are
data-dependent (needles × lenses), so treat them as measurements to re-run, never as
constants to pin.

**Duplication has one cost — drift — and it is now pinned.** Nothing previously asserted
that the four Delivery Contract blocks were identical, so a reworded copy still carrying
every needle passed. The blocks are extracted and compared byte-for-byte against the first.

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
