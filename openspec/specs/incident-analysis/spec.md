# Incident Analysis

## Purpose

Structured production-incident investigation. Tiered observability detection (MCP → gcloud CLI → guidance-only), HITL-gated mutations, and canonical postmortem output that survives the session so incident context reaches the next phase and the next responder.
## Requirements
### Requirement: Tiered Tool Detection
The skill SHALL detect available observability tools at runtime and MUST select the best execution tier.

#### Scenario: MCP tools available
Given the session has `list_log_entries` MCP tool available
When the skill detects tools in Stage 1
Then Tier 1 (MCP) is selected for all subsequent queries

#### Scenario: gcloud CLI available, no MCP
Given `gcloud` is installed and authenticated
When the skill detects tools in Stage 1
Then Tier 2 (Bash with temp-file pattern) is selected

#### Scenario: No tools available
Given neither MCP nor gcloud is available
When the skill detects tools in Stage 1
Then Tier 3 (guidance-only) is selected with Cloud Console instructions

### Requirement: HITL Gate for Mutations
The agent MUST halt and present exact commands before executing any mutating action.

#### Scenario: Restart recommended
Given the agent identifies a service restart as the fix
When it reaches the HITL gate in Stage 1
Then it presents the exact restart command and halts until explicit user confirmation

### Requirement: Structured Postmortem Generation
The skill SHALL generate a postmortem document in a consistent format.

#### Scenario: No template file exists
Given the project has no postmortem template
When the skill reaches Stage 3
Then it uses the built-in schema (8 section headers) and writes to `docs/postmortems/YYYY-MM-DD-<kebab-case-summary>.md`

#### Scenario: Project template exists
Given `docs/templates/postmortem.md` exists
When the skill reaches Stage 3
Then it uses the project template instead of the built-in schema

### Requirement: Routing Integration
The skill MUST be routable via the plugin's activation hook.

#### Scenario: Incident keyword triggers skill
Given the user prompt contains "incident" or "postmortem"
When the activation hook scores skills
Then `incident-analysis` appears as a domain skill in DEBUG/SHIP phases

#### Scenario: Phase gating
Given the user prompt contains "incident" but the SDLC phase is DESIGN
When the activation hook scores skills
Then `incident-analysis` does NOT appear (phase-gated to DEBUG/SHIP only)

### Requirement: Session-Start Observability Detection
The session-start hook SHALL detect gcloud CLI availability.

#### Scenario: gcloud installed
Given `gcloud` is on PATH
When the session starts
Then `Observability tools: gcloud=true` is emitted in additionalContext

### Requirement: Autonomous Trace Correlation (v1.1)
The skill SHALL perform bounded one-hop trace correlation when Tier 1 MCP tools are available and explicit failure evidence is present in cross-service span data.

#### Scenario: Clear downstream error span
Given Service A logs contain a trace_id and get_trace reveals Service B with status != OK
When the agent inspects spans in Step 4
Then it MUST query Service B logs scoped to trace_id + resource labels + span time ± 1 minute, synthesize the causal path, and proceed to Step 5

#### Scenario: Timeout cascade
Given Service A failed with timeout/deadline-exceeded and Service B span >= 80% of root span duration and no other non-A span >= 40%
When the agent inspects spans in Step 4
Then it MUST query Service B logs and synthesize the causal path

#### Scenario: Fan-out to multiple services
Given the trace contains failure evidence in 2+ non-Service-A services or 3+ services with any failure signals
When the agent inspects spans in Step 4
Then it MUST present the trace timeline to the user and NOT autonomously choose a service

#### Scenario: No trace field in logs
Given the failing log entries do not contain a trace field
When the agent reaches Step 4
Then it MUST skip Step 4 entirely and proceed to Step 5

#### Scenario: Tier 2 active
Given only gcloud CLI is available (no MCP)
When the agent reaches Step 4
Then it MUST skip Step 4 entirely

### Requirement: Exemplar Trace Selection (v1.1)
The skill MUST select one exemplar trace from the dominant error group when multiple failing requests (>1) are present before entering Step 4.

#### Scenario: Multiple failing requests
Given Stage 2 logs contain more than one failing request with trace fields
When the agent enters Step 4
Then it MUST select one exemplar trace and analyze only that trace

### Requirement: Postmortem Permalink Formatting (v1.2)
The skill SHALL format trace IDs and commit hashes as clickable Markdown links in generated postmortem documents.

#### Scenario: Trace ID in postmortem
Given the postmortem references a trace_id and project_id from Stage 2
When the agent generates the postmortem document
Then the trace reference MUST be formatted as `[Trace TRACE_ID](https://console.cloud.google.com/traces/list?project=PROJECT_ID&tid=TRACE_ID)`

#### Scenario: Cross-project trace references
Given Stage 2 Step 4 correlated Service A and Service B in different projects
When the postmortem references traces from both services
Then Service A trace links MUST use Service A's project_id and Service B trace links MUST use Service B's project_id

#### Scenario: Git commit in postmortem (GitHub-hosted)
Given the postmortem references a deployment commit hash and the remote is GitHub-hosted
When the agent formats the commit reference
Then it MUST format as `[Commit SHORT_HASH](https://github.com/ORG/REPO/commit/FULL_HASH)`

#### Scenario: Non-GitHub remote or command failure
Given `git remote get-url origin` returns a non-GitHub URL or fails
When the agent formats a commit reference
Then it MUST use the raw commit hash without a link

### Requirement: Playbook Discovery and Loading (v1.3)
The skill SHALL discover and load playbooks from bundled and repo-local directories.

#### Scenario: Bundled playbooks loaded
Given the skill enters the CLASSIFY stage
When it discovers playbooks
Then it loads all YAML files from skills/incident-analysis/playbooks/

#### Scenario: Repo-local override
Given a repo-local playbook at playbooks/incident-analysis/custom.yaml exists with the same id as a bundled playbook
When the skill loads playbooks
Then the repo-local definition replaces the bundled one

### Requirement: Confidence-Gated Classification (v1.3)
The skill SHALL classify incidents against loaded playbooks using a deterministic scoring engine.

#### Scenario: High confidence proposal
Given a single playbook scores >= 85 confidence with all eligibility conditions met
When the CLASSIFY stage completes
Then the agent presents a high-confidence decision record with command, supporting signals, contradictory signals, state fingerprint, and validation plan

#### Scenario: Medium confidence investigation
Given the top playbook scores 60-84
When the CLASSIFY stage completes
Then the agent presents a medium-confidence investigation summary with suggested follow-up queries and no command block

#### Scenario: Low confidence deep investigation
Given no playbook scores above 60
When the CLASSIFY stage completes
Then the agent transitions to INVESTIGATE Steps 1-5 only and feeds findings back to CLASSIFY

### Requirement: Three-Tier Eligibility (v1.3)
The scoring engine SHALL use three tiers for different purposes.

#### Scenario: Proposal eligibility
Given a playbook is commandable with no veto signals, coverage >= 0.70, params resolved, and pre_conditions passed
When the winner selection runs
Then the playbook is proposal_eligible and can reach the HITL gate

#### Scenario: Classification credibility
Given a non-commandable playbook with no veto signals, coverage >= 0.70, and confidence >= 60
When contradiction collapse is evaluated
Then the playbook participates as classification_credible

### Requirement: Contradiction Collapse (v1.3)
The scoring engine SHALL collapse to investigate when incompatible categories both score >= 60.

#### Scenario: Incompatible high scorers
Given two classification_credible candidates with categories in incompatible_pairs both score >= 60
When contradiction collapse is evaluated
Then all candidates collapse to the investigate path

### Requirement: State Fingerprint Recheck (v1.3)
The agent MUST recheck the state fingerprint after approval and before execution.

#### Scenario: No drift
Given the user approves a mitigation proposal and the fingerprint has not changed
When the agent rechecks the fingerprint
Then execution proceeds

#### Scenario: Drift detected
Given the user approves a mitigation proposal but the fingerprint has changed
When the agent rechecks the fingerprint
Then the command is invalidated and the flow returns to CLASSIFY

### Requirement: Post-Execution Validation (v1.3)
The agent SHALL validate the mitigation outcome in two phases.

#### Scenario: Stabilization grace period
Given a mitigation command has been executed
When the VALIDATE stage begins
Then only hard_stop_conditions are evaluated during stabilization_delay_seconds

#### Scenario: Observation window
Given the stabilization grace period has expired without hard stops
When the observation window begins
Then both hard_stop_conditions and stop_conditions are evaluated, and post_conditions are sampled every sample_interval_seconds for validation_window_seconds

#### Scenario: Validation success
Given all post_conditions are met after the observation window
Then the agent transitions to POSTMORTEM with verification_status: verified

#### Scenario: Validation failure
Given post_conditions are not met or a stop_condition triggers
Then the agent escalates to INVESTIGATE

#### Scenario: Validation inconclusive
Given post_conditions are partially met after the observation window
Then the agent presents the user with choices: extend observation, escalate, or accept as mitigated but unverified

### Requirement: Evidence Sanitization and Persistence (v1.3)
All evidence payloads MUST be sanitized before persistence.

#### Scenario: Evidence redaction
Given the agent captures evidence for an evidence bundle
When the evidence is written to disk
Then all payloads have passed through redact-evidence.sh and no unsanitized data is persisted

#### Scenario: Destructive action pre-capture
Given a playbook has requires_pre_execution_evidence: true
When the agent reaches the HITL gate
Then pre.json must include the sanitized final log window before the command is proposed

### Requirement: Decision Record Format (v1.3)
The agent MUST use compact, structured decision records at the HITL gate.

#### Scenario: High confidence record
Given a proposal passes all eligibility checks
When the agent presents the mitigation proposal
Then the output includes: playbook ID, confidence band, coverage ratio, margin, evidence age, supporting signals with weights, contradictory signals, veto signals, unknown/unavailable signals, state fingerprint, command, explanation, and validation plan

### Requirement: CAST Mental-Model-Gap Articulation in Synthesis

Step 7 synthesis MUST emit a `Mental model gaps` section. For each controller (human role or automation component) relevant to the incident, the section SHALL record one entry of the shape `<controller> believed <X>; actual was <Y>`. If the incident has a single controller whose model was correct, the section MAY be `N/A — <reason>` with the reason stated explicitly.

#### Scenario: Multi-controller incident
- **WHEN** an investigation attributes the root cause across two or more controllers (e.g., backend service + deployment automation + shared database)
- **THEN** Step 7 synthesis output contains a `Mental model gaps` block with at least one entry per relevant controller in the `<controller> believed <X>; actual was <Y>` shape

#### Scenario: Single-controller incident with correct model
- **WHEN** the incident involves a single controller whose prior model of the system was accurate and the failure was external (e.g., upstream vendor outage)
- **THEN** the `Mental model gaps` block MAY be `N/A — <reason>` with a non-empty reason stated
- **AND** the reason SHALL explain why no model correction is required

#### Scenario: Action item without identified belief
- **WHEN** the postmortem proposes an action item (runbook update, training, dashboard redesign)
- **THEN** the action item implies a controller's prior belief was wrong
- **AND** Step 7 synthesis SHALL name that controller and the belief explicitly in the `Mental model gaps` block

### Requirement: CAST Systemic-Factor Coverage Across Five Categories

Step 7 synthesis MUST emit a `Systemic factors` section covering all five CAST categories: Safety Culture, Communication/Coordination, Management of Change, Safety Information System, and Environmental Change. Each category SHALL contain either a non-empty observation paragraph OR `N/A — <reason>` (equivalently `not_applicable — <reason>`). A bare `N/A`, bare `not_applicable`, or any token without a non-empty reason SHALL block the completeness gate.

#### Scenario: Complex multi-team incident
- **WHEN** the investigation spans multiple services and teams
- **THEN** each of the five CAST categories in Step 7 output has a non-empty observation paragraph

#### Scenario: Simple config-typo incident
- **WHEN** the incident is resolved in under 5 minutes by a single engineer via rollback
- **THEN** categories that genuinely do not apply MAY be `N/A — <reason>` with the reason stated (e.g., "single engineer, no cross-team handoff involved")
- **AND** the completeness gate SHALL accept the output

#### Scenario: Unresolved category blocks closure
- **WHEN** any of the five categories in Step 7 output is bare `N/A`, bare `not_applicable`, or has an empty reason
- **THEN** Step 8 completeness gate Q12 SHALL block transition to POSTMORTEM
- **AND** the investigation SHALL return to Step 7 to resolve the category

### Requirement: Hindsight-Bias Self-Check in Synthesis

Step 7 synthesis MUST include a self-check that scans the synthesis prose the operator produces for hindsight-bias language and replaces flagged phrases with evidence-grounded framing. The self-check SHALL cover at minimum the phrases `should have`, `failed to`, `could have easily`, `obviously`, and `it was clear that`. Replacement patterns SHALL be documented in `references/cast-framing.md`.

#### Scenario: Phrase flagged during synthesis
- **WHEN** a draft of Step 7 synthesis prose contains the phrase "the on-call engineer should have checked dashboards first"
- **THEN** the self-check SHALL flag the phrase
- **AND** guidance SHALL point to `references/cast-framing.md` for the evidence-grounded replacement shape (e.g., "the on-call engineer's model at T was <Y>; evidence that would have prompted dashboard check was <where it lived / why it wasn't visible>")

#### Scenario: Insufficient evidence to replace
- **WHEN** the hindsight-bias check flags a phrase but the supporting evidence for the replacement is missing
- **THEN** the claim SHALL be moved to the `open_questions` section instead of being rewritten with speculation

#### Scenario: Self-check scope
- **WHEN** the self-check is performed
- **THEN** it SHALL apply only to synthesis prose the operator produces, not to the SKILL.md file itself or any other reference material (e.g., SKILL.md Step 8 Q7 legitimately mentions `should have` in "which alerts should have fired but didn't" — this is documentation, not synthesis prose)

### Requirement: Completeness Gate Question 12 (CAST Systemic Factors)

Step 8 completeness gate MUST include Question 12 covering CAST systemic-factor coverage. Q12 SHALL require an observation or `not_applicable — <reason>` (equivalently `N/A — <reason>`) for each of the five categories. Q12 SHALL follow the existing Q4-Q12 resolution rule (evidence-backed answer, `not_applicable` with reason, `unavailable` with reason, or `not_captured` with reason — bare "not assessed" blocks closure).

#### Scenario: Fully populated Q12
- **WHEN** Step 7 synthesis has a non-empty entry or `N/A — <reason>` for each of the five CAST categories
- **THEN** Q12 is resolved
- **AND** transition to POSTMORTEM is allowed if all other gate questions are also resolved

#### Scenario: Missing category blocks closure
- **WHEN** one or more of the five CAST categories is empty, bare `N/A`, bare `not_applicable`, or `N/A —` with no reason
- **THEN** Q12 is unresolved
- **AND** Step 8 SHALL block transition to POSTMORTEM until the category is resolved

#### Scenario: Existing Q4-Q11 resolution vocabulary applies to Q12
- **WHEN** an author uses `not_applicable — <reason>`, `unavailable — <reason>`, or `not_captured — <reason>` for a CAST category
- **THEN** Q12 SHALL accept the resolution
- **AND** the vocabulary is equivalent to the Q12 row's `N/A — <reason>` shape

### Requirement: Postmortem Template Sub-Blocks for CAST

The built-in postmortem template (`references/postmortem-template.md`) MUST include:
- Section 6 (Contributing Factors) SHALL contain a `Systemic factors` sub-block listing all five CAST categories.
- Section 7 (Lessons Learned) SHALL contain a `Mental model gaps` sub-block and a `Hindsight-bias check` paragraph pointing at the hindsight-language replacement patterns.

#### Scenario: Template copy-paste by postmortem author
- **WHEN** an author copies the built-in template into a new postmortem
- **THEN** §6 contains the five CAST category bullets as placeholders
- **AND** §7 contains the `Mental model gaps` bullet list placeholder and the `Hindsight-bias check` paragraph

#### Scenario: CAST reference pointer present
- **WHEN** a reviewer or author opens the template
- **THEN** both §6 and §7 new sub-blocks reference `references/cast-framing.md` for definitions and replacement patterns

### Requirement: Optional CAST Fields in Investigation Summary Schema

The canonical YAML schema for `investigation_summary` (`references/investigation-schema.md`) MUST document optional `mental_model_gaps` (a list of `{controller, believed, actual}` objects) and `systemic_factors` (a map with keys `safety_culture`, `communication_coordination`, `management_of_change`, `safety_information_system`, `environmental_change`) fields. Both fields SHALL be optional and purely additive; consumers that do not need CAST framing MUST be able to ignore them without error.

#### Scenario: Schema consumer without CAST awareness
- **WHEN** a consumer parses `investigation_summary` YAML that includes `mental_model_gaps` and `systemic_factors` fields
- **THEN** the consumer SHALL be able to ignore those fields without schema-level validation errors

#### Scenario: CAST-aware synthesis emits structured fields
- **WHEN** Step 7 synthesis is emitted with CAST framing
- **THEN** the YAML MAY populate `mental_model_gaps` and `systemic_factors` in the structure documented in the schema file

#### Scenario: Schema enforcement
- **WHEN** the change is shipped
- **THEN** no validator, hook, or CI check SHALL enforce presence of the CAST fields in emitted YAML (prose-only enforcement via Step 7 and Q12 is the sole mechanism)

### Requirement: Action-Item Phase Classification

The postmortem Action Items section MUST classify every action item with a `Type` field whose value is one of `Detect`, `Prevent`, or `Mitigate`. The field MUST be present in both the built-in schema path and the project-template path so behavior is identical regardless of whether a repo-local template exists. The classification is in addition to — not a replacement for — the existing priority/action/current-state/owner/due/status fields.

#### Scenario: Action item is typed

- **GIVEN** an incident investigation has reached the POSTMORTEM stage with at least one action item
- **WHEN** the skill emits the Action Items section
- **THEN** each action item MUST carry a `Type` field
- **AND** each `Type` value MUST be exactly one of `Detect`, `Prevent`, or `Mitigate`

#### Scenario: Detection-gap action is classified Detect

- **GIVEN** a postmortem whose root cause went undetected by monitoring (a time-to-detection gap)
- **WHEN** the agent proposes an action item that adds an alert or SLO for that failure class
- **THEN** that action item's `Type` MUST be `Detect`

#### Scenario: No repo-local template exists

- **GIVEN** the project has no postmortem template file
- **WHEN** the skill generates the postmortem from the built-in schema
- **THEN** the Action Items section MUST still include the `Type` field for every item

### Requirement: Per-Command Risk Label for Destructive Actions

Before presenting a destructive or mutating command at the HITL gate, the agent MUST prefix the command with a single-line risk label beginning with the ASCII token `RISK:`. The label MUST classify the action as `HIGH` (irreversible, data-loss, or wide blast radius) or `MEDIUM` (temporary disruption or reversible) and MUST include a short reason. Read-only investigation queries MUST NOT carry a risk label. The label MUST NOT rely on an emoji as its sole marker; the ASCII `RISK:` token MUST always be present.

#### Scenario: Destructive command carries a HIGH risk label

- **GIVEN** the agent recommends an irreversible mitigation (for example a resource deletion or node drain)
- **WHEN** it presents the exact command at the HITL gate
- **THEN** the command MUST be immediately preceded by a line matching `RISK: HIGH — <reason>`
- **AND** the agent MUST halt for explicit user confirmation before execution

#### Scenario: Reversible mutation carries a MEDIUM risk label

- **GIVEN** the agent recommends a reversible disruption (for example a workload restart or rollout)
- **WHEN** it presents the exact command at the HITL gate
- **THEN** the command MUST be immediately preceded by a line matching `RISK: MEDIUM — <reason>`

#### Scenario: Read-only query is not labeled

- **GIVEN** the agent runs a read-only investigation query (for example reading logs or listing resources)
- **WHEN** it presents or executes that query
- **THEN** the query MUST NOT be prefixed with a `RISK:` label

#### Scenario: Label is ASCII-assertable

- **GIVEN** any destructive command presented at the HITL gate
- **WHEN** the behavioral-evaluation runner greps the output with a fixed-string match for `RISK:`
- **THEN** the match MUST succeed without depending on emoji codepoints

