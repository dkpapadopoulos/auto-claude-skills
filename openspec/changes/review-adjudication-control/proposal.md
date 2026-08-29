# Proposal: a review lead must isolate one fault before deciding a finding (#205)

## Why

`skills/agent-team-review/SKILL.md` tells the lead how to *filter* findings (the
severity floor) and how to detect *aggregate* dismissal (`doubt theater`, across
two or more rounds). It says nothing about how to decide **one** finding.

The gap has a measured cost. On 2026-08-12 a reviewer reported that without
`hooks/lib/git-command.sh` the mutate-then-push check stops firing. The
reproduction harness had several faults active at once, an unrelated fail-closed
leg produced the same visible verdict either way, and the finding read as
refuted. Re-run with that one lib removed and every other gate satisfied, the
effect appeared exactly as reported — it is now a documented invariant in
`CLAUDE.md`.

The mechanism is general: **an upstream fail-closed gate masks a downstream
fall-open one**, so until every other gate is independently satisfied the
variable under test contributes nothing observable. A harness with more than one
fault active measures their combination, not the variable — and the same holds in
reverse, so a finding *accepted* without a control that flips is a guess with a
file:line attached, and the test it motivates asserts nothing.

## What Changes

- A new `§4a Adjudicating one finding: isolate exactly one fault` in
  `skills/agent-team-review/SKILL.md`, reached from step 4 of Lead Synthesis:
  reproduce with the claimed cause present and absent, holding everything else
  fixed, and require the two runs to **disagree** before rejecting or accepting.
- An explicit escalation for when the pair cannot be obtained
  (`could-not-reproduce`, severity preserved, routed to the user as open).
- Isolation: every reproduction runs in a detached worktree, never in the shared
  working tree — adjudication injects faults on purpose.
- A recorded pairing per adjudicated finding, so an unexamined verdict is
  distinguishable from an examined one.
- `tests/fixtures/agent-team-review/adjudication/seeded-findings.md`: six
  findings — three real-but-confounded, three false — every one of them
  **measured against the real `hooks/openspec-guard.sh`**, with the fault
  injected, the subject command, the control command, and both decisions.
- `tests/test-review-adjudication.sh`: the deterministic gate, with two
  independent authorities and a count floor, mutation-verified.

## Out of scope

- Any change to the severity floor, the finding contract, or doubt-theater
  detection.
- Granting a reviewer or lead write access to the shared tree.
- A model-graded behavioural eval over the seeded set; the corpus is committed so
  one can be built, but this change ships the deterministic leg only.
