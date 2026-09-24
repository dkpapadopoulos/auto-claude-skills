# Decide whether the chain-block VERIFY gate may accept the verification verdict

## Why

`hooks/openspec-guard.sh` asks "did VERIFY happen?" in two places, and the two
answer it from different evidence.

**Check 2, the chain-block leg** (`deny:chain-verify`) fires when a composition
chain is active and contains `verification-before-completion`. It accepts four
sources — composition-state `.completed`, `_ledger_has`, `_invoc_ok`,
`_bridge_has` — and every one of them reduces to *a `Skill` tool returned*.
Fifty lines above it, in the same function, the REVIEW verdict leg states the
opposite about that same class of evidence: "a Skill return is not evidence a
review ran (#197)".

**The global fail-closed leg** (`deny:global-failclosed`) asks the same question
and additionally accepts a clean verification verdict covering the subject
commit. Its own comment:

> A clean verification verdict covering HEAD is stronger (SHA-bound) evidence of
> VERIFY than the status milestone, so it also satisfies the verify leg.

Check 2 runs first. So whenever a chain is active, the deny fires before the leg
that would have accepted the stronger evidence ever executes. Issue #254 defect
2 reports this as an inconsistency and proposes that Check 2 read the verdict
too.

Measured population (posted to #254 on 2026-09-23, not re-derived here): **2 of
26** `deny:chain-verify` records in the most recent window of
`~/.claude/.push-gate-invocation-log` had a clean covering verdict at deny time
— 11.5% by record, 7.7% by episode. That figure is a lower bound (the log
rotates 1000 -> 500) and both hits predate plugin 3.84.

#291 already shipped the advisory that names this situation in the deny text, so
the silent-failure half is closed. What remains is only whether the flip should
happen.

## What Changes

**This change ships the decision procedure, and the rules are committed before
anything is measured.** The code change, if any, is determined by the procedure's
outcome and is authored afterwards in this same change.

1. **Pre-register a structural falsifier bar** (`design.md`) — an operational
   contract defining what "meaningfully covered" requires (seven boundaries),
   the sixteen enumerated states in which the acceptance predicate holds while
   at least one boundary fails, and the three-outcome decision rule. All frozen
   before measurement. The enumeration is recorded as known-possibly-incomplete
   rather than as a proof: it went from 8 entries to 16 under one adversarial
   review pass, which is the evidence for that label.
2. **Discharge the bar** — measure enumerated falsifiers for reachability
   against the real guard **until the decision rule terminates**, which it does
   on the first reachable falsifier no named tightening closes. Each measurement
   is paired (present/absent, everything else fixed, the two runs must disagree)
   with a positive control in the same harness, per the #205 adjudication
   discipline. In the event that was **F5 alone**; the rest are enumerated and
   unmeasured, and `design.md` says which.
3. **Apply whichever outcome the rule returns** — WIDEN, NARROW, or
   REFUSE-AND-REPAIR. All three are real terminal states of this change. The
   rule deliberately separates *adding* an acceptance path to Check 2 from
   *repairing* the shared infrastructure behind that evidence; a finding about
   the second never licenses the first.

### Why not the repo's usual instrument

Every prior pre-registration here — IMPLEMENT (`implement-shadow-event`), REVIEW
(`review-verdict`) — was **advisory -> deny**, where the risk is a *false block*.
A false block is observable: the deny leaves a record and a human can adjudicate
it. That is why those registrations are rate-shaped (n, repo diversity, exact
Clopper-Pearson bands).

This flip is **deny -> allow**, where the risk is a *false allow* — a push that
should have been stopped and was not. That event leaves **no gate record at
all**, so a shadow corpus cannot observe the thing that would falsify the
change. Importing the rate instrument here would produce a third corpus that
measures the wrong quantity.

The repo's own record splits on that same line. Rate-style registrations are 0
for 3: #239 closed as a null result never instrumented; the IMPLEMENT corpus was
reset to n=0 five times by predicate bumps; the REVIEW corpus passed its floor
three weeks unseen for want of a labeller. Enumerate-the-falsifiers is 2 for 2:
#229 and #231 were both settled decisively by building the shape corpus and
measuring each shape. A structural bar is also decidable in a single session,
which is precisely the failure mode `preregistration-needs-a-reader-and-a-labeller`
records.

## Capabilities

- **MODIFIED** `pdlc-safety` — the conditions under which the chain-block VERIFY
  gate may accept SHA-bound verdict evidence, and the bar that must be
  discharged before any such widening ships.

## Impact

- `openspec/changes/chain-verify-verdict-acceptance/` — the pre-registration.
- `hooks/openspec-guard.sh` — Check 2's **acceptance predicate** only if the bar
  returns WIDEN or NARROW. The bar returned REFUSE, so the predicate is
  unchanged. What the outcome does change is the **advisory text and the
  comments around it**: the #291 note told the reader the global leg treats the
  verdict as "stronger evidence ... than this status milestone", which reads as
  a concession that this leg is mistaken. Measurement says the opposite — the
  verdict is easier to supply, not harder — so a reader acting on that wording
  would widen the gate in the wrong direction. Corrected, with a pointer to the
  provenance defect.
- `tests/test-chain-verify-verdict-note.sh` — the stale header prose (which
  asserted the refuted "stronger evidence" framing) is replaced with the
  discharge outcome, and a cell pins that the message does not disparage this
  leg. Mutation-verified: reverting only the guard's wording fails 5 cells.

No new skill, so neither done-gate binds on anything new. No `predicate_version`
bump: this change does not alter when the IMPLEMENT or REVIEW shadow legs fire,
so neither corpus is reset.

## Out of scope

- Re-deriving the 2-of-26 population figure before the rules are committed.
- Any rate-style shadow corpus for this leg.
- Demoting the REVIEW chain gate — that is the separate default-demote
  commitment dated 2026-10-07 in `push-gate-evidence-supply`.
- Changing the global fail-closed leg's acceptance predicate **in this change**.
  Under REFUSE-AND-REPAIR the defects are filed against the **shared
  components** — token selection, non-atomic reads, subject resolution, writer
  provenance — because `routing-governance` and `verify-hardening` consume the
  same predicates, so a fix scoped to one leg leaves the others exposed. Each
  gets its own change and its own argument.
- Establishing "meaningful commit coverage" as a gate-wide invariant. Global
  VERIFY is an OR over five evidence sources; narrowing the verdict disjunct
  while unbound status alternatives remain cannot deliver that property.
