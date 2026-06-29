# pdlc-closed-loop — Outcome failure-cause classification (delta)

## ADDED Requirements

### Requirement: Outcome-review classifies failure cause before recommending

When a shipped hypothesis is non-`Confirmed`, `outcome-review` SHALL classify the failure cause
before issuing a recommendation, choosing one of: `instrumentation-broken` (the metric pipeline is
wrong, not the feature), `adoption-gap` (the feature works but is under-exposed/undiscovered),
`product-miss` (fully exposed and correctly measured, users do not convert), or `inconclusive-data`.
The recommendation SHALL follow from the diagnosed cause — in particular, an `instrumentation-broken`
or `adoption-gap` cause MUST NOT recommend reverting or discarding the feature on the metric alone.

#### Scenario: Broken instrumentation does not trigger a feature rollback

- **GIVEN** a non-`Confirmed` hypothesis whose metric reads zero while manual QA confirms the feature works
- **WHEN** outcome-review assesses the hypothesis
- **THEN** the Cause MUST be `instrumentation-broken`
- **AND** the recommendation MUST be to fix tracking and re-measure, not to change or roll back the feature

#### Scenario: Under-exposed feature is not judged on overall metric

- **GIVEN** a non-`Confirmed` hypothesis where the feature is rolled out to a small fraction but performs well within the exposed cohort
- **WHEN** outcome-review assesses the hypothesis
- **THEN** the Cause MUST be `adoption-gap`
- **AND** the recommendation MUST be to expand rollout and re-measure before judging the feature
