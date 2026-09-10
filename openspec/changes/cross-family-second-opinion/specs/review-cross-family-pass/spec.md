# review-cross-family-pass

## MODIFIED Requirements

### Requirement: Cross-Model Offer covers a full adversarial pass in two modes

`agent-team-review` §6 MUST support a full cross-family adversarial pass over the diff in exactly two modes: (Mode A) requested before or during the round, where the pass runs as an additional reviewer with the same base/head, context bundle, and delivery contract, and its non-delivery is an advisory gap rather than `could-not-review`; and (Mode B) offered on a `clean`/`suggestions_only` verdict, where acceptance triggers a defined second cycle — dispatch, collect, deduplicate, severity floor, §4a/structural disposition, regenerated summary, recomputed verdict. The dispatch MUST be read-only/sandboxed. Cross-model findings MUST carry the full FINDING contract (`Category` assigned from the defect, `Confidence`, `Evidence`, `Oracle` where applicable) and are subject to the same floor, adjudication, structural exceptions, and open-finding constraints as any reviewer's findings. The review verdict MUST be recorded only after the offer is resolved, with finding totals and unresolved-blocking counts including cross-model findings. The user's offer decision MUST be recorded either way. When no second model family is available, the offer MUST state that and the pass is skipped — a same-family substitute MUST NOT be presented as a cross-family pass.

#### Scenario: Accepted blocking cross-model finding changes the verdict

- GIVEN a round with an initial `clean` verdict and an accepted Mode B cross-family pass
- WHEN the pass returns a finding adjudicated as `blocking`
- THEN the summary is regenerated, the verdict becomes `blocking_issues`, and the recorded verdict artifact reflects the final verdict and counts — no `clean` verdict is recorded before the offer resolved

#### Scenario: Cross-family findings are adjudicated, not trusted

- GIVEN an accepted cross-family pass returning two findings
- WHEN the lead synthesizes
- THEN each finding is deduplicated against existing findings and passes through the severity floor and, where it makes an experimentally decidable causal claim, §4a single-fault adjudication — identical to a same-family reviewer's finding

#### Scenario: Injected instructions in the diff cannot act

- GIVEN a reviewed diff containing embedded instructions addressed to a reviewing agent
- WHEN the cross-family pass runs
- THEN the Codex dispatch is read-only/sandboxed with only the approved review bundle in context, no workspace mutation occurs, AND the injected content can at most appear as reported finding text
