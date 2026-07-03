## ADDED Requirements

### Requirement: Test-adequacy gate in project-verification

`project-verification` SHALL, after running the repo's declared test gate, evaluate
whether the change under review is adequately tested by parsing whatever coverage
artifact the test runner already emits. In Phase 1, scope is limited to changed-line
coverage against a floor, expressed through the existing tri-state evidence contract
(`clean` / `suspect` / `unverified`). Coverage regression against the base ref is
explicitly OUT OF SCOPE for Phase 1 and is DEFERRED to Phase 2 — this is a disclosed
deferral, not a silent omission; the base-ref comparison MUST be tracked as a Phase-2
item before any claim of full coverage-regression detection is made. It MUST fail-open:
absent, unparseable, or tool-less coverage MUST resolve to `unverified` and MUST NOT
block. It MUST NOT introduce any new push-gate state.

#### Scenario: New code shipped without covering tests
- **GIVEN** a diff that adds executable logic and a coverage artifact exists
- **WHEN** the adequacy check runs and the added lines fall below the changed-line floor
- **THEN** the evidence status MUST be `suspect` with the uncovered changed lines cited
- **AND** the status MUST surface as blocking evidence in the same manner as gate-gaming `suspect`

#### Scenario: No coverage tooling present
- **GIVEN** a repo whose test runner emits no discoverable coverage artifact
- **WHEN** the adequacy check runs
- **THEN** the status MUST be `unverified`
- **AND** the check MUST NOT block the push gate or alter existing behavior

#### Scenario: Adequately tested change passes
- **GIVEN** a diff whose changed lines are covered above the floor
- **WHEN** the adequacy check runs
- **THEN** the status MUST be `clean`
- **AND** `clean` reflects changed-line coverage only in Phase 1 — it MUST NOT be read as also certifying no coverage regression against the base ref, which is a Phase-2 deferral (see Phase-2 escalation note above)

### Requirement: Rigor Benchmark measurement instrument

The change SHALL provide a committed, labeled Rigor Benchmark of seeded
`(diff, ground-truth-verdict)` cases that supplies objective ground truth for scoring
any testing-rigor mechanism independent of felt production pain. Coverage of the six
case classes (untested-new-code, assertion-free-test, bug-with-green-tests,
weakened-test, adequate-clean, pure-refactor) is PHASED, not all-at-once: Phase 1 MUST
seed the two classes the Phase 1 adequacy mechanism actually discriminates
(untested-new-code, adequate-clean); the remaining four (assertion-free-test,
bug-with-green-tests, weakened-test, pure-refactor) are DEFERRED to Phase 2 and MUST be
seeded alongside the Phase-2 mechanisms (mutation testing, spec-derived test generation,
cross-model review) that are able to catch them. This phasing MUST be disclosed in the
benchmark's own documentation, not left as a silent reduction in scope. The benchmark
MUST be split into a `dev` set and a blind `held-out` set with the held-out set sourced
from a different codebase than the gate was tuned on, and MUST report recall, control-set
precision, incremental recall over the cheapest baseline, and cost per mechanism.
Benchmark cases MUST NOT be deleted; they MUST be deprecated with a dated rationale.

#### Scenario: Scoring a mechanism against held-out ground truth
- **GIVEN** a rigor mechanism (the adequacy gate, mutation, test-gen, or cross-model review)
- **WHEN** it is run over the held-out benchmark split
- **THEN** the scorer MUST emit recall, precision on the two control classes, incremental recall over the cheapest baseline, and token+time cost
- **AND** the two control classes (adequate-clean, pure-refactor) MUST count any flag as a false positive

#### Scenario: Benchmark integrity is preserved
- **WHEN** a benchmark case is retired
- **THEN** it MUST be marked deprecated with a dated rationale rather than deleted
- **AND** the held-out split MUST remain sourced independently from the gate's tuning corpus

### Requirement: Frozen-criteria race protocol for escalations

The change SHALL adopt or reject each Phase-2 escalation — mutation testing,
spec-derived test generation, and cross-model peer review — only by scoring it against
the held-out Rigor Benchmark under a decision rule whose numeric thresholds are
calibrated to the held-out set's measured difficulty at the start of Phase 2 and then
FROZEN before the race is run. Each race MUST emit a committed verdict alongside its
measured numbers. Cross-model peer
review MUST additionally pass `agent-safety-review` before it may ship, because it sends
potentially private code to an external model (`private_data` + `outbound_action`).
Spec-derived test generation MUST treat any generated test that passes against the
seeded-buggy code as an automatic failure (behavior-pinning), and MUST NOT generate tests
from existing code.

#### Scenario: An escalation that fails its frozen bar is rejected with evidence
- **GIVEN** a Phase-2 escalation scored on the held-out benchmark
- **WHEN** it does not meet its frozen incremental-recall, precision, or cost threshold
- **THEN** it MUST be recorded as rejected with the measured numbers
- **AND** it MUST NOT ship

#### Scenario: Cross-model review is blocked pending safety review
- **GIVEN** the cross-model peer-review escalation has cleared its benchmark bar
- **WHEN** adoption is considered
- **THEN** it MUST NOT ship until `agent-safety-review` clears the code-egress data flow
- **AND** unmitigated, unacknowledged egress MUST be treated as a blocking governance finding

#### Scenario: Thresholds cannot be set after seeing results
- **WHEN** a race is run
- **THEN** its thresholds MUST have been frozen at Phase-2 start before results were observed
