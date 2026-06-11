# Adopt Doubt Discipline

## Why

Triage of addyosmani/agent-skills (52k stars, 2026-06-11) found three portable pieces of review discipline its `doubt-driven-development` skill and `/ship` command encode that our review pipeline lacks:

1. Our `agent-team-review` reviewer spawn templates pass the design doc and diff, but nothing prevents the lead from also passing the implementer's own summary or claims of correctness — which biases reviewers toward agreement ("handing the reviewer your conclusion biases it toward agreement").
2. We have no checkable definition of performative review. The bot-review-asymptote problem (reviewers raise findings, all get dismissed, rounds continue) is documented only in session memory, not as a skill-level red flag.
3. The Codex-for-factual-claims second opinion is a memory habit, not skill text — it gets silently skipped.

Additionally, our sizing rule sends any <5-file change to single-agent review, even when it touches auth, secrets, hooks, or CI config — exactly the changes that most need the security and governance lenses. And `skill-scaffold` gives no guidance on description authoring, risking descriptions that summarize workflows (which agents may follow instead of reading the full skill).

## What Changes

- `skills/agent-team-review/SKILL.md`: claim-withheld reviewer dispatch rule; doubt-theater red flag in lead synthesis; mandatory cross-model offer (never silent skip, read-only invocation); sensitive-path override in the sizing rule.
- `skills/skill-scaffold/SKILL.md`: description authoring rule (state purpose + when-to-use, never summarize workflow steps).
- `tests/test-adversarial-governance.sh`: content assertions for the four agent-team-review constraints.
- `tests/test-skill-scaffold-content.sh` (new): content assertion for the description rule.

## Capabilities

### Modified
- `adversarial-review` — four ADDED requirements: Claim-Withheld Reviewer Dispatch, Doubt-Theater Detection, Cross-Model Review Offer, Sensitive-Path Fan-Out Override.
- `skill-routing` — one ADDED requirement: Workflow-Free Skill Descriptions.

### Added
- (none — no new capability)

## Impact

Two SKILL.md files, one existing test file, one new test file. No hooks, no routing entries, no registry changes, no new skills. Prompt-text-only change to review behavior; no runtime code paths touched.
