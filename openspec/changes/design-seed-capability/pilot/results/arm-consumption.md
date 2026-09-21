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

**(a) Adaptation — NOT SATISFIED.** Arm S supplied neither required form: no adaptation
record, and no explicit "no justified adaptation needed". The protocol gave it no
instruction to produce either. The gate therefore fails, and **this observation does not
distinguish absent adaptation reasoning from absent reporting** — arm S may have
considered adaptation and rejected it, never considered it, or considered it without
writing it down. Substantive engagement with the seed does not separate those.

Two readings of the criterion are available and the frozen wording does not settle which
was intended:

1. **An obligation to document**, which the protocol then failed to communicate — the
   brief is framing-free and never mentions adaptation, and the only other channel is the
   seed's standard adopter pointer, which says nothing about recording such a decision.
2. **A test of whether documentation emerges spontaneously** under ordinary adoption
   instructions — in which case arm S simply failed it, and explicitly requesting the
   behaviour would have measured something different.

An earlier draft of this file asserted reading (1) and concluded the arm "could not have"
satisfied (a). **That was too strong and is withdrawn.** Unrequested is not impossible: a
criterion may legitimately measure unprompted behaviour, and choosing the more charitable
reading *after* observing the failure — for an instrument this author wrote — is not a
defensible move. Both readings are recorded; the gate is recorded as failed either way.

What this does invalidate: any claim that this run assessed adaptation reasoning, or
satisfied the full process protocol. What it does not invalidate: the screen comparison,
whose separate reporting and retention were registered in advance.

One wording correction while here: the arms were **not** treated identically, and the
record should not say so. Arm S received the seed and its pointer — that is the intended
treatment. The accurate claim is that brief, fixture, model, cap and tool access were
matched, with the seed package as the sole intended difference.

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
