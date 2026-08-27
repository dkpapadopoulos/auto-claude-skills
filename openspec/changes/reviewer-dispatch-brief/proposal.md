# Proposal: give the reviewer dispatch brief a delivery contract, and the lead an idle-recovery protocol

## Why

Issue #204. From a single push-gate review round, recorded in
`memory/background-reviewers-need-explicit-report-request.md`:

- four reviewers dispatched; **three went idle with no findings attached** and produced
  full reports only when explicitly asked;
- **one errored with a request timeout** and produced nothing at all;
- one reviewer performing mutation testing **edited the shared working tree** while a
  12-minute suite run was in progress against it, invalidating the run.

The unprompted delivery rate for that round was **0/4**.

At the issue's verified sha, each of the four lens prompts in
`skills/agent-team-review/SKILL.md` said only:

```
- Read-only: do NOT modify any files
- Send all findings to the lead via SendMessage
```

That brief is silent on every condition the observed failures turned on. And the skill's
`Verification` section already asserts the *outcome* — "Every spawned reviewer returned a
finding set this session -- no reviewer silently dropped" — while supplying **no mechanism
by which that outcome is reached**. It is an unenforced assertion, which is why the round
above could produce 0/4 delivery and still pass the skill as written.

Two facts make the reviewer-side clauses load-bearing rather than decorative:

1. A background `Agent` in this harness signals idle with a `summary` at best. **An agent's
   final text is its return value, not a message to the lead** — nothing routes it to the
   main conversation unless the agent calls `SendMessage` to `main`, which it often does
   not do unprompted.
2. The read-only rule covers editing *for review purposes*. It does not cover a reviewer
   told to mutation-test, which is exactly the case that corrupted the shared tree.

## What Changes

1. **A `## Delivery Contract (read this first)` block in every one of the four lens
   prompts**, placed ahead of the lens itself so it is read before the review starts:
   time-box + report-even-if-incomplete; deliver unprompted (idle loses the review);
   "Silence is not a pass"; and "say plainly if you find nothing — do not manufacture
   findings", which keeps the delivery metric from being gamed by fabrication.

2. **An own-worktree rule in every lens's `## Rules`** — any reviewer that RUNS or MUTATES
   anything (tests, builds, mutation testing) must `git worktree add --detach` into a
   `mktemp -d` path first and never write to the shared tree. The path must be unique per
   invocation: lens names are constants, so a fixed `/tmp/review-<lens>` fails with
   `fatal: already exists` the moment the lead re-dispatches a timed-out reviewer, which
   the lead-side protocol mandates. The reviewer must also confirm its worktree matches the
   subject — a detached worktree does not carry the shared tree's uncommitted changes, so
   running against it and reporting VERIFIED would name a different tree. Paired with a
   verified-vs-inferred labelling rule.

   The clauses live **in each prompt, not in the protocol prose**, because a reviewer
   subagent only ever sees its own prompt.

3. **A lead-side collection protocol** in Protocol §3, as a state table: idle is not a
   report; chase at least twice; a timeout is not a pass and is never counted toward
   coverage; **check `git status`/`git log` before re-dispatching**, because subagents here
   routinely finish the work and stall before reporting, leaving it uncommitted in the tree
   — re-dispatching without looking duplicates work already done. A lens that never
   delivers makes the verdict `could-not-review`, not `clean`. A **silent drop** red flag
   names the failure of reporting a round complete without one of its lenses.

4. **The `Verification` outcome is tied to that mechanism** rather than left as a bare
   assertion.

5. **Pinned eval set** `tests/fixtures/agent-team-review/dispatch-brief/` (never delete):
   `required-clauses.txt` (the literal needles) and `pinned-range.txt` (the sha-bound
   subject and pre-registered metric for the behavioral leg).

6. **Deterministic gate** `tests/test-reviewer-dispatch-brief.sh` — asserts every clause in
   **every** lens block, scoped per block so a clause stated once cannot satisfy four
   reviewers, plus the lead-side protocol (scoped to Protocol §3) and the no-regression
   clauses. The gate is a **second authority**, not a fixture reader: it hardcodes the #204
   clause anchors and asserts the fixture still carries them, because with the fixture as
   sole authority a deleted needle silently deletes its own assertion. It derives the lens
   population from the skill rather than hardcoding four, and compares the four Delivery
   Contract blocks byte-for-byte, since drift is duplication's one cost.

7. **Registered in CI** — added to `.github/workflows/done-gates.yml` and pinned by
   `tests/test-done-gate-ci.sh`. This was a claim before it was true: `.verify.yml` is
   `substrate: local` and is read by no workflow, so a test reachable only through
   `tests/run-tests.sh` is not a CI check.

## Capabilities

### Modified Capabilities
- `pdlc-safety`: the multi-lens review dispatch brief gains a delivery contract and a
  worktree-isolation rule per lens, and the lead gains a defined recovery protocol for
  idle and errored reviewers.

## Impact

- `skills/agent-team-review/SKILL.md` — delivery contract + worktree rule in all four lens
  prompts; lead-side collection protocol; Verification tied to mechanism.
- `tests/fixtures/agent-team-review/dispatch-brief/` — **new**, pinned eval set.
- `tests/test-reviewer-dispatch-brief.sh` — **new**, deterministic content gate.

## Sequencing: why the behavioral leg is not a merge precondition

The A/B contract in #204 has two legs. The deterministic leg (every lens prompt carries
every clause) is cheap and lands with the prompt edit — and is registered as a
`done-gates.yml` step so that "runs in CI" is a fact rather than a claim. The behavioral leg
(dispatch the 4-lens team over the pinned range and measure unprompted delivery ≥ 3/4 with
zero main-tree mutations) requires live multi-agent dispatch: slow, nondeterministic, and
explicitly optional evidence per the issue. Its subject is pinned in `pinned-range.txt` so a
later run stays comparable to the baseline.

## Out-of-Scope

- The reviewer-ran push-gate evidence leg (`openspec/changes/reviewer-dispatch-and-evidence`,
  PR #212, parked pending reconciliation with #197). This change makes reviewers deliver;
  it does not change what the push gate credits.
- The `Task tool (general-purpose)` label in the prompt headers. This harness names the
  subagent tool `Agent`; correcting that is tracked with the `^Task$` → `^(Task|Agent)$`
  matcher work, not here.
