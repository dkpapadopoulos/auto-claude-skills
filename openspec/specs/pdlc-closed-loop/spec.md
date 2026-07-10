# PDLC Closed-Loop

## Purpose

Closes the product development lifecycle by routing DISCOVER-intent prompts to product-discovery and LEARN-intent prompts to outcome-review, with composition chaining and PostHog/Jira detection so learnings from one cycle feed the next discovery.
## Requirements
### Requirement: DISCOVER Phase Routing
The routing engine MUST detect discovery-intent prompts and select the product-discovery skill. Two-tier trigger patterns: strong signals (discover, user.problem, pain.point, what.to.build, what.should.we, which.issue) and weak signals (backlog, sprint.plan, prioriti, triage, next.sprint, roadmap). Priority 35, role process.

#### Scenario: Strong discovery trigger
Given a prompt "what should we build for the next sprint"
When the activation hook scores skills
Then product-discovery is selected with label "Discover"

#### Scenario: Disambiguation against DESIGN
Given a prompt "build a new auth service"
When the activation hook scores skills
Then brainstorming is selected, not product-discovery

### Requirement: LEARN Phase Routing
The routing engine MUST detect outcome-review-intent prompts and select the outcome-review skill. Triggers: how.did.*(perform|do|go|work), outcome, adoption, funnel, cohort, experiment.result, feature.impact, post.launch, post.ship, measure, did.it.work. Keywords handle ambiguous terms (learn, metric, result). Priority 30, role process.

#### Scenario: LEARN trigger
Given a prompt "how did the auth feature perform after launch"
When the activation hook scores skills
Then outcome-review is selected with label "Learn / Measure"

#### Scenario: False positive guard
Given a prompt "show me the test results"
When the activation hook scores skills
Then outcome-review is NOT selected

### Requirement: Composition Chain Integration
The routing engine MUST wire `product-discovery.precedes = ["brainstorming"]` (DISCOVER → DESIGN) and `outcome-review.precedes = ["product-discovery"]` (LEARN → DISCOVER loop). The SHIP composition MUST include an advisory LEARN reminder hint.

#### Scenario: DISCOVER precedes DESIGN
- **WHEN** the composition chain is computed for a DISCOVER-then-DESIGN flow
- **THEN** `product-discovery` appears before `brainstorming` in the chain

#### Scenario: LEARN loop routes back to DISCOVER
- **WHEN** outcome-review fires and the loop reopens
- **THEN** the next-cycle precedence routes through product-discovery

### Requirement: PostHog MCP Detection
The session-start hook MUST detect PostHog MCP via `~/.claude.json` `mcpServers` and MUST set the posthog plugin available flag, following the established Serena/Forgetful pattern.

#### Scenario: PostHog MCP present
- **WHEN** `~/.claude.json` contains a PostHog entry under `mcpServers`
- **THEN** the registry cache records `posthog=true`

### Requirement: Graceful Degradation
Both DISCOVER and LEARN skills MUST detect MCP availability at invocation: Tier 1 uses MCP tools when available; Tier 2 prompts the user for manual context; neither skill MUST hard-fail on missing MCPs.

#### Scenario: MCP missing
- **WHEN** product-discovery or outcome-review is invoked and the relevant MCP is unavailable
- **THEN** the skill MUST prompt the user for manual context instead of failing

### Requirement: Red Flags
The skills MUST enforce phase red-flag guardrails. In DISCOVER: no code writing, no skipping Jira context, no jumping to design without a discovery brief. In LEARN: no Jira ticket creation without approval, no skipping metrics analysis, no code editing.

#### Scenario: DISCOVER red flag tripped
- **WHEN** product-discovery is invoked and the user asks to begin coding before the brief is approved
- **THEN** the skill MUST halt and require brief approval before transition

#### Scenario: LEARN red flag tripped
- **WHEN** outcome-review is invoked and the user requests creating Jira tickets without review
- **THEN** the skill MUST require explicit approval before `createJiraIssue`

### Requirement: deploy-gate fails closed on absent or broken CI

The `deploy-gate` CI check MUST distinguish three states — green, red, and **absent-or-broken** — and MUST treat absent-or-broken as a FAILURE, not a pass. Specifically, an empty `gh pr checks` result combined with an empty `gh run list` conclusion (no CI runs reported), or a CI run that concluded with zero completed steps, MUST cause the CI check to fail closed. The gate MUST NOT interpret "no checks reported" as "nothing blocking → ship". This is the design's only model-independent hard signal and MUST key on the external CI conclusion rather than on any artifact the gated agent can write.

#### Scenario: Zero CI checks fails the gate
- **GIVEN** a branch/PR for which `gh pr checks` reports no checks and `gh run list` reports no conclusion
- **WHEN** the deploy-gate CI check runs
- **THEN** the check MUST report FAIL with an explicit "absent ≠ green" message
- **AND** deploy-gate MUST NOT proceed to `openspec-ship`

#### Scenario: Zero-step CI job fails the gate
- **GIVEN** a CI run that concluded almost immediately having executed zero steps (e.g. a billing-blocked runner)
- **WHEN** the deploy-gate CI check runs
- **THEN** the check MUST report FAIL rather than reading the run as a pass

### Requirement: deploy-gate accepts a fresh local verification as the verification of record

When hosted CI is absent, the deploy-gate CI check MUST be able to accept a fresh `~/.claude/.skill-project-verified-<token>` evidence artifact with no entries in `failed` as the local verification of record, recording that verification occurred on substrate `local`. This acceptance is for surfacing local-vs-hosted provenance to the human; it MUST NOT be presented as a non-bypassable enforcement gate, since the artifact is model-writable.

#### Scenario: Local verification evidence surfaces when CI is absent
- **GIVEN** no hosted CI is configured AND a fresh `~/.claude/.skill-project-verified-<token>` exists with an empty `failed` list
- **WHEN** the deploy-gate CI check runs
- **THEN** the gate MUST report the verification as performed on substrate `local` with provenance noted
- **AND** the gate MUST still surface that hosted CI was absent rather than claiming hosted-CI green

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

### Requirement: Assumption Audit in the discovery brief

The DISCOVER-phase discovery brief MUST include an `## Assumption Ledger`
section reconstructing the initiative's logic chain as explicit assumptions,
each row carrying: belief, category, importance (H/M/L), `evidence_kind`
(direct_metric | direct_observation | analogous | expert_judgment | none),
`source_ref`, `observed_at`, `claimed_grade` (A-F), and — for fragile
assumptions (high-importance, grade C or below, top-3 by materiality) — a
kill-shot test with a pre-declared kill/validate `kill_threshold`. The brief
MUST tag findings as fact, inference, or unknown, and MUST present an option
set containing at least a do-nothing baseline with a conditional
recommendation (proceed / proceed-with-conditions naming a hard-number
condition / hold). The stage MUST be skippable only by explicit declaration
for small/obvious work, never silently.

#### Scenario: Ledger produced for a real initiative
- **GIVEN** a discovery session for a new feature with market/value uncertainty
- **WHEN** the discovery brief is synthesized
- **THEN** the brief MUST contain an `## Assumption Ledger` section with graded
  assumptions, at least one fragile assumption carrying a pre-declared
  kill/validate threshold, and an option set including do-nothing

#### Scenario: Evidence ceiling blocks grade inflation
- **GIVEN** a discovery doc whose ledger claims grade A on an assumption whose
  `evidence_kind` is `expert_judgment`
- **WHEN** `scripts/assumption-audit-check.sh` runs against the doc
- **THEN** the checker MUST exit non-zero naming the evidence-ceiling violation
  (expert_judgment caps at D), and a compliant ledger MUST pass with exit 0

### Requirement: Two-step active-choice validation

Discovery validation MUST be an active-choice interaction, not a yes/no
approval. Step one: decision criteria and weights are presented for user
confirmation BEFORE any option scores are shown. Step two: scored options and
the fragile-assumption quadrant are presented, and the user is asked to grade
or veto specific assumptions, choose which kill-shot test runs first, and
confirm or override the conditional recommendation. When the model judges the
work declared small/obvious, validation MAY collapse to a single step, stated
explicitly in chat.

#### Scenario: Weights confirmed before scores exist
- **GIVEN** a discovery session with a genuine option set
- **WHEN** validation begins
- **THEN** the user MUST be shown criteria and weights for confirmation before
  any per-option scores appear in the conversation

#### Scenario: Fragile assumption surfaced against user push
- **GIVEN** a user who asks to proceed on a plan resting on a D-grade belief
- **WHEN** the skill responds
- **THEN** it MUST surface the fragile assumption and its missing evidence
  before agreeing, offering proceed-with-conditions or a kill-shot test (it
  MUST NOT silently proceed)

