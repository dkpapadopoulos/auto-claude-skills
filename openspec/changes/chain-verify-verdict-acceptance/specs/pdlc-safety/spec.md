# pdlc-safety: chain-block VERIFY evidence acceptance

## MODIFIED Requirements

### Requirement: The chain-block VERIFY gate's evidence set may widen only against a discharged structural bar

The push gate's chain-block VERIFY check (`deny:chain-verify`) MUST NOT be
widened to accept verification-verdict evidence until a structural falsifier bar
has been registered and discharged.

The registration MUST be committed **before** any measurement of the population
the widening would newly allow, and MUST fix, in advance: the claim under test,
an **operational contract** defining what it means for verification to have
covered a commit, the enumerated falsifiers organised as failure transitions
across that contract's boundaries, the operational meaning of "reachable", the
permitted tightenings, and a decision rule whose outcomes include refusing the
widening. The contract MUST be fixed before the enumeration, because an
enumeration against an undefined predicate cannot be evaluated for
completeness.

A falsifier is **reachable** only on an executed sequence against the real guard
that, in a state where the chain-block check currently denies, the widening
turns into a **guard-level allow** with every remaining deny passing. An argument
that such a sequence exists MUST NOT be recorded as reachability, and a predicate
evaluated in isolation MUST NOT be recorded as reachability either — the guard's
other legs still run, so a falsified predicate is not yet a false allow. Each reachability determination MUST be paired — the
falsifier present and absent, all else held fixed, the two runs disagreeing —
and MUST be accompanied by a positive control in the same harness. A pair that
fails to disagree MUST be recorded with which of claim-false,
intervention-incomplete, or preconditions-unmet applies, and MUST NOT be
recorded as refutation without that attribution.

If the widening ships, Check 2's acceptance predicate MUST use the same verdict
predicate, the same token resolution, and the same command subject
(`_SUBJ_ROOT`/`_SUBJ_REV`) as the global fail-closed leg, so that the two legs
cannot diverge in what they accept. Any tightening applied to Check 2 beyond
that MUST be one named in the registration, or a dated amendment explaining why
the registration's list was incomplete.

The registration MUST record its enumeration as possibly incomplete rather than
as a proof.

The decision rule MUST separate adding an acceptance path to the chain-block
check from repairing the shared components that produce or resolve the evidence.
A finding that shared infrastructure is defective MUST NOT be recorded as
licensing the widening. Where a reachable falsifier originates in a component
also consumed by other gate legs, the resulting defect MUST be filed against
that component rather than against a single leg.

#### Scenario: The widening does not ship on an undischarged bar

- GIVEN a registered structural bar for the chain-block VERIFY widening
- AND the bar's reachability measurements have not been run
- WHEN a change proposes that Check 2 accept a clean covering verdict
- THEN that change is not merged
- AND Check 2 continues to deny on a chain whose VERIFY milestone has no status evidence

#### Scenario: A reachable, unclosable falsifier refuses the widening

- GIVEN the bar has been discharged
- AND at least one enumerated falsifier is reachable by an executed sequence against the real guard
- AND no tightening named in the registration closes it
- WHEN the decision rule is applied
- THEN Check 2's acceptance predicate is left unchanged
- AND if that falsifier is also reachable on the global fail-closed leg, a defect is filed against the global leg rather than against Check 2

#### Scenario: A shipped widening cannot accept more than the global leg

- GIVEN the bar returned WIDEN or NARROW and the widening has shipped
- WHEN a push is evaluated for which the global fail-closed leg would not accept the verdict as VERIFY evidence
- THEN Check 2 does not accept that verdict either

#### Scenario: An argued falsifier is not a measured one

- GIVEN a candidate falsifier for which no executed guard sequence producing an allow has been recorded
- WHEN the decision rule is applied
- THEN that candidate is not counted as reachable
- AND the registration records it as unmeasured rather than as closed
