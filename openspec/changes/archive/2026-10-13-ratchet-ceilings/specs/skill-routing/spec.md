## MODIFIED Requirements

### Requirement: Phase hints name the owning skill and stay short

Each `phase_compositions.<PHASE>.hints[].text` SHALL be at most 480 bytes; a hint of 300 bytes or more SHALL name the `Skill(...)` or plugin script that owns the procedure it refers to, and SHALL state the condition under which it applies. The full procedure MUST live in the owning skill's `SKILL.md`. The per-phase byte totals (DESIGN, PLAN, REVIEW, SHIP, DISCOVER, DEBUG, LEARN) SHALL be pinned as ceilings in `tests/test-phase-hint-brevity.sh`: growth MUST fail, the constant MUST be raised only in the commit that grows the text and that commit MUST say why, and a reduction passes (the constant MAY be lowered later). The 480-byte figure is also a ceiling. (The first draft said 240 bytes; the spec-driven PERSIST DESIGN hint carries the three-file layout the model must reproduce, and that list is the content, so the ceiling is 480. The totals were equality ratchets from PR #349 until the ratchet-ceilings change.)

#### Scenario: A DESIGN block is rendered

- **WHEN** the activation hook renders the DESIGN phase hints
- **THEN** every hint is at most 480 bytes, every hint of 300 bytes or more contains `Skill(` or a plugin script, and the EVAL STRATEGY, AUTONOMY CHECK and ADVERSARIAL REVIEW procedures are present in full in `skills/runtime-validation/SKILL.md`, `skills/agent-safety-review/SKILL.md` and `skills/agent-team-review/SKILL.md`

#### Scenario: Hint content changes

- **WHEN** only hint texts and the INTENT EXTRACTION directive change
- **THEN** the composition-state file and the push gate's decision are byte-identical to the previous render for the same input

#### Scenario: A phase total shrinks

- **WHEN** a hint is shortened and the phase total falls below its ceiling
- **THEN** `tests/test-phase-hint-brevity.sh` passes without the constant moving

### Requirement: Session-start fork count is pinned

The session-start hook SHALL issue no more external-process forks for `jq`, `basename`, `dirname`, `ls`, `grep`, `sort` and `awk` than the ceiling constant in `tests/test-session-start-fork-budget.sh` over the test fixture: growth MUST fail, the constant MUST be raised only in the commit that adds the forks and that commit MUST say why, and a reduction passes (the constant MAY be lowered later). A count that cannot be read MUST fail, never pass as under the ceiling. Semver directory selection MUST compare components numerically.

#### Scenario: Versions 9.9.9 and 10.0.0 exist

- **WHEN** a plugin directory contains both
- **THEN** `10.0.0/` is resolved

#### Scenario: Forks are removed

- **WHEN** a change removes forks from the session-start hook
- **THEN** `tests/test-session-start-fork-budget.sh` passes without the constant moving
