# openspec-ship — artifact templates

Read at SKILL.md Step 3 before writing `proposal.md`, `design.md`, a delta `spec.md` or `tasks.md` yourself (always on the no-CLI fallback path). Moved verbatim from SKILL.md; the checkpoint-stamping rule and its validator stay there.

**proposal.md** (must match openspec's expected headers exactly):
```
## Why
Why we built this. (Synthesized from SP brainstorming spec if available.)

## What Changes
High-level summary of what was actually built.

## Capabilities

### New Capabilities
- `<capability-name>`: Brief description of what this capability covers

### Modified Capabilities
- `<existing-name>`: What requirement changed

## Impact
Affected code, APIs, dependencies, systems.
```

**design.md:**
```
# Design: <Feature Name>

## Architecture
Data flow, component breakdown, system diagrams reflecting the as-built state.

## Dependencies
New packages, APIs, or database changes introduced.

## Decisions & Trade-offs
Why Path A over Path B. Rejected alternatives and rationale.
(Synthesized from Superpowers brainstorming spec if available.)
```

**specs/<capability>/spec.md** (delta spec, one per capability):

Use RFC 2119 keywords in UPPERCASE: MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT, MAY. Never write these as lowercase when they express requirements.

```
## ADDED Requirements

### Requirement: <Name>
<Description using RFC 2119 keywords in UPPERCASE, e.g. "The system MUST ...">

#### Scenario: <Name>
- **WHEN** <condition>
- **THEN** <expected outcome>
```

**tasks.md** (when `plan_path` is provided):
```
# Tasks: <Feature Name>

> Checkpoints reference branch commits. After squash-merge they are typically
> recoverable only via the feature's GitHub PR (`gh pr view <N> --json commits`)
> — plain clones and forks do not fetch PR refs.

## Completed

- [x] 1.1 <task description> (from SP execution plan) [checkpoint: <sha7>]
- [x] 1.2 <task description>
```

**tasks.md** (when `plan_path` is NOT provided):
```
# Tasks: <Feature Name>

## Completed

- [x] 1.1 Retrospective tasks unavailable — no Superpowers execution plan was provided. See git log for implementation history.
```
