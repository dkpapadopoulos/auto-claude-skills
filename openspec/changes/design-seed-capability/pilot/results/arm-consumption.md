# Arm consumption — Task 8 Step 5

Both arms launched 2026-09-20T09:49:27Z, concurrently, from one command each, same model.

| | arm C (control) | arm S (seeded) |
|---|---|---|
| stop reason | completed | completed |
| tool calls | 44 / 60 | 24 / 60 |
| wall clock | 853s / 2700s | 1058s / 2700s |
| skill invocations | 0 | 0 |
| model | `claude-opus-5` (pinned, identical) | `claude-opus-5` (pinned, identical) |
| prompt sha256 | `a3676d07…` | `d38a2e58…` |

Neither arm hit a cap, so neither submitted work-in-progress: the stopping rule did not
bind and both outputs are what the arm considered finished.

**Skill invocations are the OBSERVED value, not the pre-launch measurement.** Review
required this: "0 invocations" in a probe is one draw from a stochastic process. The
observed value matches the probe in both arms.

**Prompt shas differ only by the worktree path.** Asserted mechanically before launch:
normalising `/private/tmp/pilot-arm-{c,s}` to a common token makes the two files
byte-identical (`diff` empty).

## Adoption / implementation split (arm S)

Not separable from the stream: arm S interleaved reading `design/` with building rather
than doing a distinct adoption phase. Recorded as unseparated rather than estimated.
The seed was adopted by the harness BEFORE the clock started (commit `1714a14`), which
is the handicap the design intended — arm S's 24 calls are implementation, and it still
read the styleguide within them.

## Process gates (scored separately from the screens, per outcome 5)

**(b) Freeze boundary — PASS.** `design/` committed at `1714a14` before the arm started;
`git status --porcelain design/` is empty afterwards, so no `design/` edit followed.

**(a) Adaptation — NOT SATISFIED, and the criterion is at fault, not the arm.** Arm S
recorded neither an adaptation nor an explicit "no justified adaptation needed". It could
not have: the brief is framing-free by design and never mentions adaptation, and the only
other channel — the `ADOPT.md` pointer line in `CLAUDE.md` — is the standard adopter
pointer, which says nothing about recording adaptation decisions. **Criterion (a) is
uncommunicable to an arm without breaking the framing-free requirement.** That is a
defect in the pre-registration, discovered by running it, and it is recorded here rather
than scored against arm S.

## Gate status, both arms

Both arms hit the same 5 failures in
`tests/design_seed_pilot/test_arm_capability_boundary.py::TestNormalSessionIsUntouched`.
That class sets `NORMAL_DIR = cwd` and asserts the deny hook stays inert there, but the
hook identifies an arm by any path component matching `pilot-arm-*` — and the arms' cwd
IS `/private/tmp/pilot-arm-{c,s}`. The class cannot pass from inside an arm worktree, by
construction. Symmetric, environmental, and caused by the harness (the worktree naming
comes from the plan), not by either arm's work.

Arm C additionally reported that its `pytest` lane had not finished when it hit its
budget, and declined to claim a green gate it had not seen — the correct call. It also
self-reported that `bash scripts/ci.sh | tail -40` returns *tail's* exit status, so an
earlier "exit 0" of its own was false.
