# adversarial-review

## MODIFIED Requirements

### Requirement: Cross-Model Review Offer

`agent-team-review` §6 MUST support a full cross-family adversarial pass over the diff in exactly two modes: (Mode A) requested before or during the round, where the pass runs as an additional reviewer with the same base/head, context bundle, and delivery contract, and its non-delivery is an advisory gap rather than `could-not-review`; and (Mode B) offered on a `clean`/`suggestions_only` verdict, where acceptance triggers a defined second cycle — dispatch, collect, deduplicate, severity floor, §4a/structural disposition, regenerated summary, recomputed verdict. The dispatch MUST be read-only/sandboxed. Cross-model findings MUST carry the full FINDING contract (`Category` assigned from the defect, `Confidence`, `Evidence`, `Oracle` where applicable) and are subject to the same floor, adjudication, structural exceptions, and open-finding constraints as any reviewer's findings. The review verdict MUST be recorded only after the offer is resolved, with finding totals and unresolved-blocking counts including cross-model findings. The user's offer decision MUST be recorded either way. When no second model family is available, the offer MUST state that and the pass is skipped — a same-family substitute MUST NOT be presented as a cross-family pass.

#### Scenario: Accepted blocking cross-model finding changes the verdict

- GIVEN a round with an initial `clean` verdict and an accepted Mode B cross-family pass
- WHEN the pass returns a finding adjudicated as `blocking`
- THEN the summary is regenerated, the verdict becomes `blocking_issues`, and the recorded verdict artifact reflects the final verdict and counts — no `clean` verdict is recorded before the offer resolved

#### Scenario: Clean verdict with external-fact claims

- GIVEN a `clean` verdict on a diff containing external-fact claims (library surfaces, tool names, version availability)
- WHEN the lead reaches verdict routing
- THEN the full cross-family adversarial pass is offered — the former external-fact-claims-only offer is subsumed by the general two-mode offer, and those claims are simply part of what the pass examines

#### Scenario: Cross-family findings are adjudicated, not trusted

- GIVEN an accepted cross-family pass returning two findings
- WHEN the lead synthesizes
- THEN each finding is deduplicated against existing findings and passes through the severity floor and, where it makes an experimentally decidable causal claim, §4a single-fault adjudication — identical to a same-family reviewer's finding

#### Scenario: Cross-model invocation is sandboxed

- GIVEN a reviewed diff containing embedded instructions addressed to a reviewing agent
- WHEN the cross-family pass runs
- THEN the Codex dispatch is read-only/sandboxed with only the approved review bundle in context, no workspace mutation occurs, AND the injected content can at most appear as reported finding text

## ADDED Requirements

### Requirement: Autofix lane for mechanically certain trivia

The `agent-team-review` FINDING contract MUST accept an optional `Autofix:` line carrying an exact old→new edit, additive to `Suggestion:` and never replacing it. Only `suggestion`-severity findings MAY carry `Autofix:`; `blocking` and `warning` findings MUST keep the full return-to-IMPLEMENT path even when a reviewer attaches the line. The routing token MUST NOT self-certify: the lead MUST independently validate each `Autofix:` line against all four eligibility conditions (single exact text transformation stateable precisely; essentially certain correct and complete; touches only code the reviewed diff introduced or changed; zero behavioural ambiguity), verify the `old` text is present, unique, and unstale, and deduplicate overlapping or conflicting edits — this validation is the finding's adjudication. A validated line routes past the severity floor into the autofix batch; a line failing validation reverts to a normal suggestion under normal floor rules, with the failure reported. Application requires per-item human approval ("apply all except …" supported) listing every old→new edit. After applying, the lead MUST assert the applied diff is byte-identical to the approved batch; on mismatch, revert and return to IMPLEMENT. Verification and verdict recording MUST happen only after application, so the recorded verdict describes the final tree state. Applied autofixes MUST remain listed in the review summary.

#### Scenario: Validated trivia rides the autofix batch

- GIVEN a reviewer finding a typo in a docstring introduced by the diff, reported as a `suggestion` with an `Autofix:` line stating the exact replacement
- WHEN the lead validates the line (four conditions, unique unstale `old` text)
- THEN the finding routes to the autofix batch, is presented for per-item approval with its old→new edit, and on approval is applied before verification and verdict recording

#### Scenario: The token does not self-certify

- GIVEN a `suggestion` finding carrying an `Autofix:` line whose edit would change behaviour (or whose `old` text is stale or non-unique)
- WHEN the lead validates the batch
- THEN the line fails validation, the finding reverts to a normal suggestion under normal severity-floor rules, and the failed validation is reported in the summary

#### Scenario: Severity cap holds

- GIVEN a `warning`-severity finding whose fix happens to be a one-line edit with an attached `Autofix:` line
- WHEN the lead synthesizes
- THEN the finding does NOT enter the autofix batch and follows the normal adjudication and fix path

#### Scenario: Nothing is applied without approval, and application precedes the verdict

- GIVEN an autofix batch of three validated edits presented per-item
- WHEN the user approves two and declines one
- THEN exactly the two approved edits are applied, the applied diff is asserted byte-identical to the approved set, verification runs, and only then is the verdict recorded — the declined finding remains a suggestion in the summary
