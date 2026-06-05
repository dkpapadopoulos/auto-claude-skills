# Capability: incident-analysis

## ADDED Requirements

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
