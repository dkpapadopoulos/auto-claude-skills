# Spec delta: pdlc-safety — review-lead adjudication control

## ADDED Requirements

### Requirement: A review lead decides a finding only against a single-fault paired control

A review lead MUST NOT classify an individual finding as real or as rejected
without first reproducing it twice — once with the claimed cause present and once
with it absent, changing one causal variable and holding every other precondition
equal — and reading the oracle the finding names.

Three outcomes are possible and only two of them decide anything. Runs that
disagree MUST be read as the claim holding. Runs that agree MUST NOT be read as
the claim being false unless a **comparable positive control** — same subject,
same oracle, same preconditions — disagrees in the same harness; absent that
control, the lead MUST report the claim as untested rather than as refuted.

The requirement binds in BOTH directions. A finding that "failed to reproduce"
MUST NOT be rejected without the paired control; absent it the lead has failed to
trigger the finding, which is not a refutation and MUST be reported as such. A
finding MUST NOT be accepted without the paired control either.

Scope is limited to findings making an experimentally decidable causal claim. A
structural `security` or `governance` finding blocking on the criterion the
finding contract already allows — a change that removes or weakens an existing
safety constraint — MUST NOT require a paired control, and MUST be adjudicated by
reading what the change removes.

When the paired control cannot be obtained, the lead MUST record the finding as
`could-not-reproduce` with the reason, MUST preserve the severity the finding
carries after the severity floor, and MUST route it to the user as open rather
than resolved. An open finding at blocking severity MUST NOT yield a `clean` or
`suggestions_only` verdict.

Every reproduction MUST run in a detached worktree, and no reviewer or lead may
write to the shared working tree while adjudicating. Where the reviewed change is
uncommitted, the delta carried into that worktree MUST be taken against the
checked-out head rather than against the review base, since the base-to-head
range is already present in the checked-out commit.

Each finding adjudicated by pairing MUST carry a recorded pairing — what was
changed, what each configuration decided, and on a rejection the positive control
— so that an unexamined verdict is distinguishable from an examined one. A
structural finding decided by reading MUST record the constraint it removes
instead, and MUST NOT report a pairing it does not have.

A pinned set of seeded findings MUST be maintained, containing both
real-but-confounded and genuinely false cases, and each case MUST record the
measurement it was derived from rather than an assertion about the code.

#### Scenario: a real finding survives a confounded first attempt

- **GIVEN** a finding that removing one library removes a denial, and a harness
  in which a second, unrelated fault is also active
- **WHEN** the lead reproduces with only the named library removed and every
  other gate independently satisfied
- **THEN** the two configurations MUST decide differently
- **AND** the finding MUST be classified real

#### Scenario: a finding is rejected only against a positive control

- **GIVEN** a finding that removing an advisory-only library removes a denial
- **WHEN** the lead runs the paired control, and a comparable positive control
  disagrees in the same harness
- **THEN** both configurations for the claim MUST decide the same
- **AND** the finding MUST be rejected, citing the pairing and the positive
  control

#### Scenario: a non-flip with no positive control is untested, not refuted

- **GIVEN** a finding whose paired configurations decide identically
- **WHEN** no comparable positive control has been shown to disagree in that
  harness
- **THEN** the lead MUST NOT record the finding as refuted
- **AND** the finding MUST be reported as untested

#### Scenario: a structural governance finding needs no pair

- **GIVEN** a `governance` finding that a change removes an existing safety
  constraint, with no runnable failure path
- **WHEN** the lead adjudicates it
- **THEN** a paired control MUST NOT be required
- **AND** the disposition MUST record the constraint the change removes

#### Scenario: an unobtainable control is escalated, not silently demoted

- **GIVEN** a finding whose reproduction requires credentials the lead does not
  have
- **WHEN** the lead cannot construct the paired control
- **THEN** the finding MUST be recorded as `could-not-reproduce` with the reason
- **AND** its severity MUST be unchanged from the severity it carries after the
  floor
- **AND** it MUST be presented to the user as an open question
- **AND** a blocking-severity open finding MUST NOT yield a `clean` verdict
