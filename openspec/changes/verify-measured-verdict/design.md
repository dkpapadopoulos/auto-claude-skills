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

### Implementation readings — fixed 2026-10-02, at zero records

Each of these was underdetermined by the text above. They are written down
before the corpus holds a single record, so none was chosen after seeing data.
None changes a registered number.

1. **`n` counts every recorded episode, `cannot_check` included.** Clause 3 is
   only non-redundant under that reading: if `n` counted would-blocks alone,
   `n >= 5` with zero `unexplained` would already imply five `explained_ladder`.
   `cannot_check` still never counts as `unexplained`.
2. **No verdict at all is `unexplained`** (reason `absent`), per "the leg would
   block for any other reason". Consequence, stated rather than hidden: the
   case the leg exists to catch — invoke the skill, execute nothing — is itself
   an `unexplained` episode and holds the flip. The rule as registered therefore
   flips only on a corpus where every would-block was a hand-authored rung. That
   is the registered rule; changing it is the owner's call and needs a
   `predicate_version` bump.
3. **`explained_ladder` rungs** are `claude-md-commands`, `contributing-md` and
   `heuristic:<manifest>` — the third is a rung `discovery-ladder.md` names and
   the baseline table happened not to contain. Any other value the writer does
   not emit is `unexplained` (reason `unrecognised-source`).
4. **Readability is decided before coverage.** An artifact that omits
   `discovery_source` is `cannot_check` whatever its `sha` says.
5. **Population (predicate_version 1):** the composition-chain VERIFY leg only,
   milestone in the chain and already credited, `git push` only (the spec's
   scenarios say push; a merge's subject is the PR, not a branch-local commit),
   content-bearing (a pure ref deletion ships nothing). `material_source` is
   RECORDED on each record and is not a fire condition. The global no-chain
   gate is not instrumented.
6. **An episode's class is worst-wins:** any `unexplained` record, else any
   `explained_ladder`, else `cannot_check`. Arrival order never decides.
7. **The backstop counts episodes whose first record is on or before
   2026-12-31**, so later episodes cannot reopen a closed window.
8. `would_block` is `false` on a `cannot_check` record: the leg is fail-open and
   would not block on a verdict it could not read even after a flip.

### Prerequisite settled by driving the producer (2026-10-02)

`scripts/verify-and-record.sh` was RUN, not read, in a scratch repo with an
isolated `HOME`:

| Repo state | Arguments | Result |
|---|---|---|
| no `.verify.yml` | `--name tests --run true` | verdict written, `discovery_source: explicit` |
| no `.verify.yml` | none | exit 1, no verdict |
| no `.verify.yml` | `--run false` / missing command | recorded as `failed` / `could_not_verify` |
| `.verify.yml`, `substrate: local` | none | verdict written, `discovery_source: verify-yml` |
| `.verify.yml`, any substrate | `--name/--run` | exit 1, refused (declared gate wins) |
| `.verify.yml`, `substrate: ci` | none | exit 1, unsupported substrate |

So a repo with no declared gate CAN reach a measured verdict, which is what
accepting `explicit` assumed. **One population cannot:** a repo whose
`.verify.yml` declares a non-local substrate is refused on both routes, so its
only verdict is hand-authored and it would be an `explained_ladder` would-block
on every push. No such repo is known on the measured install. It is a predicted
cost to weigh at the flip, not a reason to widen the predicate.

### What is NOT open

The classification vocabulary, the `unexplained`-only rule, the n>=5 floor, the
positive-control clause, the 2-repo diversity requirement, and the backstop date. A
change to the leg's fire condition requires a `predicate_version` bump and makes earlier
records unpoolable.
