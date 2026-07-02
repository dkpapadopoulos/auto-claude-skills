# Spec: skill-creation-gate

## Purpose

Deterministic, owned done-gate and authoring flow for creating or editing skills
in this plugin. Ensures a new/edited skill proves it routes correctly (and does
not over-route) before it is considered complete, and guarantees the
`writing-skills` discipline is applied — without depending on external plugins
for the enforceable floor.

## ADDED Requirements

### Requirement: writing-skills is required on skill creation

The registry MUST register `writing-skills` with `role: required` so the
activation hook selects it whenever a skill-creation prompt matches its triggers,
regardless of how many domain slots are already filled. The entry MUST be present
and consistent in both `config/default-triggers.json` and
`config/fallback-registry.json`.

#### Scenario: Selected despite full domain slots
- **GIVEN** a prompt that triggers two domain skills (e.g. `skill-scaffold` and another domain match) AND the skill-creation trigger
- **WHEN** the activation hook scores the prompt in DESIGN phase
- **THEN** `writing-skills` MUST appear in the activation context (not dropped by the max-2-domain cap)

#### Scenario: Registry parity
- **WHEN** the fallback registry is regenerated from `config/default-triggers.json`
- **THEN** `writing-skills` MUST carry `role: required` in both files

### Requirement: Owned skills require a routing fixture

Each owned skill MUST have a matching routing fixture file under
`tests/fixtures/routing/` when it has at least one trigger regex in
`config/default-triggers.json`, and the suite MUST fail when one does not. An
owned skill is one whose `invoke` targets this plugin (`auto-claude-skills`).
Skills invoked via other plugins are exempt, and owned skills with no trigger
regex (composition-only / hint-routed, e.g. `security-scanner`) are exempt
because a trigger fixture is meaningless for them.

#### Scenario: Missing fixture fails CI
- **GIVEN** an owned skill registered in `config/default-triggers.json` with no `tests/fixtures/routing/<name>.txt`
- **WHEN** `bash tests/run-tests.sh` runs
- **THEN** the fixture-coverage test MUST report a failure (non-zero), so `.verify.yml` blocks merge

#### Scenario: External skill exempt
- **GIVEN** a skill registered with `invoke: Skill(superpowers:<name>)` and no fixture
- **WHEN** the fixture-coverage test runs
- **THEN** it MUST NOT report a failure for that skill

#### Scenario: Composition-only owned skill exempt
- **GIVEN** an owned skill with an empty `triggers` array (hint-routed, e.g. `security-scanner`) and no fixture
- **WHEN** the fixture-coverage test runs
- **THEN** it MUST NOT report a failure for that skill

### Requirement: Routing fixtures MUST include borrowed decoy negatives

A routing fixture for an owned skill MUST contain at least one `MATCH:` line and
at least one `NO_MATCH:` line, where a decoy negative is a prompt that is a known
positive for a different skill. This makes an over-broad trigger regex fail the
deterministic gate.

#### Scenario: Over-broad regex caught by decoy
- **GIVEN** a skill whose trigger regex also matches another skill's positive prompt
- **WHEN** that other skill's positive is present as a `NO_MATCH:` decoy in the fixture
- **THEN** `test-regex-fixtures.sh` MUST fail (expected NO_MATCH but matched)

### Requirement: skill-scaffold emits eval and dual-file routing artifacts

The `skill-scaffold` skill MUST instruct the author to emit a
`tests/fixtures/routing/<skill>.txt` stub (positives + borrowed decoy negatives)
and an optional `skills/<skill>/evals/evals.json` trigger-eval stub, and MUST
state that the routing entry goes in both `config/default-triggers.json` and
`config/fallback-registry.json`.

#### Scenario: Scaffold output contract
- **WHEN** `skill-scaffold` SKILL.md is read
- **THEN** it MUST reference `tests/fixtures/routing/<skill>.txt`, borrowed decoy negatives, and the dual-config routing requirement

### Requirement: Skill-creation flow is documented

CLAUDE.md MUST document the 3-stage skill-creation flow (`writing-skills` →
`skill-scaffold` → `skill-creator`), that the enforceable floor is owned and
deterministic, and the `test-regex-fixtures.sh` missing-fixture gotcha.

#### Scenario: Flow documented
- **WHEN** CLAUDE.md is read
- **THEN** it MUST describe the three-skill division of labor and the fixture-coverage gate
