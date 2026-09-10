## Purpose

Always-on governance review lens that treats every code review as adversarial. Provides a checklist, a specialist reviewer agent, and regression tests that catch HITL bypass, scope expansion, safety-gate weakening, and hook/config drift before merge.
## Requirements
### Requirement: Always-On Adversarial Checklist
The REVIEW phase composition MUST include an always-on adversarial checklist hint with governance checks for HITL bypass, scope expansion, safety gate weakening, bypass patterns, and hook/config changes. The checklist MUST fire on every code review, not only pattern-matched reviews.

#### Scenario: Checklist reaches code-reviewer
- **WHEN** the REVIEW composition fires requesting-code-review
- **THEN** the code-reviewer's context includes the ADVERSARIAL REVIEW checklist

### Requirement: Adversarial-Reviewer Specialist
agent-team-review MUST include an adversarial-reviewer template as a 4th specialist alongside security-reviewer, quality-reviewer, and spec-reviewer. The adversarial-reviewer MUST use the same FINDING communication contract with a `governance` category.

#### Scenario: Governance reviewer spawned for large changes
- **WHEN** agent-team-review fires for a 5+ file change
- **THEN** an adversarial-reviewer is spawned with governance-focused instructions

### Requirement: Governance Regression Tests
The test suite MUST include content assertions verifying that key skills contain their governance constraints. The scenario eval suite MUST include adversarial routing fixtures testing that governance-sensitive prompts route through safety skills.

#### Scenario: Constraint removal detected
- **WHEN** a developer removes "lethal trifecta" from agent-safety-review
- **THEN** test-adversarial-governance.sh fails

### Requirement: Claim-Withheld Reviewer Dispatch
agent-team-review reviewer prompts MUST contain only the artifact (diff, files changed) and the contract (design doc, plan, acceptance spec). The implementer's self-summary, claims of correctness, or completion notes MUST NOT be passed to reviewers.

#### Scenario: Reviewer receives artifact and contract only
- **GIVEN** an implementation is complete and agent-team-review is preparing reviewer spawns
- **WHEN** the lead assembles a reviewer prompt
- **THEN** the prompt includes the diff and design doc but no implementer conclusions or self-assessment

### Requirement: Doubt-Theater Detection
The agent-team-review lead MUST treat the following pattern as a red flag and surface it to the user: across 2 or more review rounds, reviewers surfaced substantive findings and zero were classified as actionable. This indicates the lead is validating rather than reviewing.

#### Scenario: All findings dismissed across rounds
- **GIVEN** two consecutive review rounds each produced substantive findings
- **WHEN** the lead has classified zero of those findings as actionable
- **THEN** the lead stops and reports the dismissal pattern to the user instead of proceeding to SHIP

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

### Requirement: Sensitive-Path Fan-Out Override
The agent-team-review sizing rule MUST spawn the reviewer team regardless of file count when the change touches authentication, secrets, permissions, hooks, or CI configuration. At minimum the security-reviewer and adversarial-reviewer MUST be spawned for such changes.

#### Scenario: Small hook change still gets team review
- **GIVEN** a change modifying 2 files including `hooks/openspec-guard.sh`
- **WHEN** the sizing rule is evaluated
- **THEN** the reviewer team is spawned despite the change being under the 5-file threshold

### Requirement: Evidence-Based Finding Discipline

`agent-team-review` MUST apply evidence-based discipline to findings to curb false-positive nit accretion without suppressing real findings.

Each FINDING MUST carry a `Confidence` field (`high|medium|low`) and an `Evidence` field. A finding MAY be classified `blocking` only if its `Evidence` describes an observable failure path — a concrete input, call, or sequence that produces the failure. The `Confidence` field MUST be advisory-only and MUST NOT gate, filter, or demote findings.

During Lead Synthesis the system MUST apply a severity floor to `quality`- and `spec`-category findings: drop `suggestion`-severity findings unmapped to a design-doc capability, and demote `blocking` findings whose `Evidence` lacks an observable failure path to `warning`. The system MUST NOT drop or demote `security` or `governance` findings on these bases — those MAY be `blocking` on structural grounds (removing or weakening an existing safety constraint) without a runnable proof-of-concept. Floored findings MUST remain visible in the review summary so the doubt-theater signal stays detectable.

#### Scenario: Theoretical quality concern is demoted

- **WHEN** a reviewer reports a `quality` finding as `blocking` whose `Evidence` names no observable failure path
- **THEN** Lead Synthesis demotes it to `warning` rather than blocking the merge

#### Scenario: Structural security finding blocks without a PoC

- **WHEN** a reviewer reports a `security` or `governance` finding that removes or weakens an existing safety constraint but provides no runnable proof-of-concept
- **THEN** the finding remains `blocking` and is neither dropped nor demoted

#### Scenario: Unmapped quality suggestion is dropped but visible

- **WHEN** a `quality` `suggestion` does not map to any capability named in the design doc
- **THEN** it is dropped from the active findings AND reported under "Dropped (below severity floor)" with a one-line reason

#### Scenario: Confidence never gates synthesis

- **WHEN** a finding carries `Confidence: low`
- **THEN** synthesis MUST NOT drop or demote it on the basis of confidence alone; only the evidence and severity-floor rules apply

### Requirement: The quality-reviewer lens asks whether a change fixes the root cause or routes around it

The `quality-reviewer` brief in `skills/agent-team-review/SKILL.md` MUST ask whether the diff is proportional to the defect and whether each added conditional corrects the root cause or routes around one that stays unfixed. The question SHALL treat "the root cause is still unfixed and this survives it" as the finding, and SHALL NOT treat the existence of a compensating layer as a finding in itself: a bridge, fallback, or sidecar is legitimate when the root cause is also fixed and the residual gap it closes is stated.

The question SHALL require the reviewer to name the input that still fails. That is the observable failure path the severity floor already demands of `quality`-category findings, so a real finding survives triage while a speculative one is correctly floored. The severity floor MUST NOT be given a carve-out for this question, because exempting it would reopen the nit accretion the floor exists to prevent.

This requirement is deliberately narrower than the external rubric it derives from. The full rubric rejects guards, fallbacks, retries, fail-open modes, watchdogs, truncation, and new state files on sight, which is incompatible with this project's deliberately fail-open hook architecture.

#### Scenario: a compensating layer with a fixed root cause is not a finding

- **WHEN** a diff adds a bridge or sidecar, the underlying root cause is also fixed, and the residual gap the layer closes is stated
- **THEN** the reviewer does not raise it as a proportionality finding

#### Scenario: a routed-around root cause is a finding with a named failing input

- **WHEN** a diff adds a conditional that survives a defect whose root cause remains unfixed
- **THEN** the reviewer raises it and names the input that still fails

### Requirement: The proportionality question is pinned to the quality lens specifically

`tests/test-adversarial-governance.sh` MUST assert the question is present in the `quality-reviewer` block specifically, not merely somewhere in the skill file, because the same words under a different lens are a different contract. The extraction SHALL bound the block at the next reviewer header generically rather than at a named sibling, since a third reviewer block sits between `quality-reviewer` and `adversarial-reviewer` and terminating on the latter silently includes the former's neighbour.

The header pattern MUST be anchored so that the adjacent `team_name:` key, which contains the header key as a substring, cannot terminate the range early. When the extracted block is empty the test SHALL fail explicitly rather than letting the content assertions decide.

#### Scenario: the question is moved to a different reviewer lens

- **WHEN** the question is relocated into any other reviewer block, including one positioned between quality-reviewer and the next header
- **THEN** the assertions fail

#### Scenario: the block anchors move

- **WHEN** the `quality-reviewer` header is renamed so the range cannot be extracted
- **THEN** the test reports an explicit extraction failure

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

