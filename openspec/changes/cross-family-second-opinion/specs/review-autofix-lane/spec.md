# review-autofix-lane

## MODIFIED Requirements

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
