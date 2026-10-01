# Design: VERIFY requires a measured verdict

## Architecture

`verdict_is_measured` reads the verdict's existing `discovery_source` field. Nothing in
`hooks/` or `scripts/` reads that field today, so this adds a reader over data already
populated on every artifact — no schema change, no producer change.

Accepted (emitted by `scripts/verify-and-record.sh`, so real exit codes were captured):
`verify-yml` (line 131), `explicit` (line 138).
Rejected (hand-authored by the model on `project-verification`'s lower rungs):
`claude-md-commands`, `contributing-md`, and any absent/unrecognised value.

The leg sits with the existing VERIFY status check, **advisory-only**: it appends to the
advisory text and never sets `permissionDecision`. It cannot bypass a deny below it.

## Trade-offs

Requiring a measured verdict closes the accidental path (invoke, execute nothing) but
does **not** close the class. `verify-and-record.sh --name tests --run true` was measured
2026-09-28 in a scratch repo and produced a fully clean verdict
(`passed:["tests"], failed:[], gate_gaming_status:"clean"`) having executed `true`.

That is accepted, not overlooked. Authoring `--name x --run true` is a **deliberate** act,
which puts it in #295's tier (needs intent), not #301's (needs only distraction). The
achievement is moving the accidental path into the deliberate tier. Claiming closure
would be the over-report this repo has repeatedly settled as worse than silence.

`explicit` is therefore accepted despite being model-chosen: it still captures real exit
codes, and rejecting it would false-block every repo without a `.verify.yml`.

## Dissenting views

**"Reject `explicit` too."** It is model-chosen, so accepting it leaves the `--run true`
hole. Rejected because it false-blocks every repo lacking a declared gate — a far larger
population than the hole, and the hole needs intent.

**"Fix the ladder first, then narrow the gate."** This was the recommendation when the
ladder looked like ~50% of verdicts. Measurement (below) put it at 8.5% and falling, so
the prerequisite is disproportionate to the population it protects.

**"Skip the shadow and flip straight to deny."** Rejected: the leg narrows the gate, so
the risk is a false block, and the affected population is measured on ONE install only.

## Decisions

1. Accept `verify-yml` and `explicit`; reject hand-authored rungs.
2. Advisory-first with a shadow corpus, and **the reader ships in the same change**.
3. Gate the flip on **unexplained** would-blocks, not on the total rate — see below.
4. No change to the artifact schema, the producer, or any existing deny leg.

## Pre-registration (decision rule for the deny-flip)

Registered 2026-09-28. `predicate_version: 1`, `schema_version: 1`.

### Measured baseline (state the scope, it is not universal)

47 verdict artifacts spanning 2026-08-02 → 2026-09-28 (57 days) on **one install**:

| `discovery_source` | n | share |
|---|---|---|
| `verify-yml` | 42 | |
| `explicit` | 1 | |
| **measured subtotal** | **43** | **91.5%** |
| `claude-md-commands` | 3 | |
| `contributing-md` | 1 | |
| **hand-authored subtotal** | **4** | **8.5%** |

Newest hand-authored verdict: 2026-09-17. Newest verdict overall: 2026-09-28 — so the
last 11 days produced zero. **Scope caveat, load-bearing:** this measures one machine's
habits. A repo with no `.verify.yml` would produce hand-authored verdicts at ~100%, and
those installs are invisible from here. The 8.5% is an install-scoped figure and must
not be quoted as a population rate.

### Why this is NOT a rate floor, and why copying n=29 would be a mistake

Hand-authored verdicts accrue at **4 / 57 days = 0.070/day**. Reaching the IMPLEMENT
leg's n=29 floor would take **413 days (1.1 years)**. Registering that floor would
repeat #199 and #239 exactly: a pre-registration whose corpus cannot reach its own bar.

More importantly, the false-block **source is already known and enumerable**. A
would-block explained by a hand-authored `discovery_source` is a *predicted cost*, not a
discovery. So the quantity worth measuring is the **unexplained** would-block.

### Classification (every shadow record carries exactly one)

- `explained_ladder` — a clean verdict covers HEAD, `discovery_source` is a hand-authored rung.
- `unexplained` — the leg would block for any other reason.
- `cannot_check` — the verdict exists but does not parse, or omits `discovery_source`.
  Never counted as `unexplained` (that direction biases toward clearing the flip).

### Decision rule

Flip to deny when **all** hold:
1. **n >= 5** shadow episodes recorded (feasible: ~71 days at the measured rate).
2. **Zero `unexplained`** episodes among them.
3. **At least one `explained_ladder`** episode observed — otherwise the instrument has
   not demonstrated it can classify the case it was built for, and a zero count is
   indistinguishable from a leg that never fired.
4. Episodes span **>= 2 distinct repos**, keyed on origin URL (not worktree path — the
   review-shadow instrument was satisfiable by two worktrees of one repo).

Do NOT flip on (1)+(2) alone: zero unexplained with n=5 and no explained case is a
positive control failure, not evidence.

### Episode definition

Collapse `(repo, branch, session_token)` within 30 minutes, **anchored at the episode's
first record** (a rolling gap chains a whole day into one episode).

### Starvation backstop

If **n < 3** by **2026-12-31**, this window closes as a permanent **null result** and the
leg stays advisory by decision, not by inertia. No re-dating off the observed rate — that
is the discretion #239 exists to refuse.

### Adjudicator and cadence — named, because #239 failed here

The corpus is reviewed by the **repo owner** at a **fortnightly** cadence, starting
2026-10-12. `scripts/verify-shadow-adjudicate.sh` **ships in the same change as the
writer** and prints n, the classification split, accrual/day, repo diversity, and which
decision-rule clauses are unmet. #239's REVIEW corpus reached its floor on 2026-09-03
and nobody could see it for three weeks because no reader existed; that is the specific
failure this clause prevents.

### What is NOT open

The classification vocabulary, the `unexplained`-only rule, the n>=5 floor, the
positive-control clause, the 2-repo diversity requirement, and the backstop date. A
change to the leg's fire condition requires a `predicate_version` bump and makes earlier
records unpoolable.
