# skill-routing — Delta: capture-knowledge phase-scoped surfacing

## ADDED Requirements

### Requirement: Phase-scoped capture-knowledge surfacing

The activation hook MUST surface `capture-knowledge` as a model-assessed candidate at
the SDLC phases where durable team learnings emerge — `LEARN`, `SHIP`, and `DEBUG` —
independently of the user typing a capture keyword. The surfacing MUST be implemented
through the existing `phase_compositions[PHASE].hints` mechanism (a single advisory
line per phase), NOT as an unconditional session banner and NOT by widening the skill's
regex triggers. Each hint MUST carry an explicit relevance gate that instructs the model
to invoke `Skill(auto-claude-skills:capture-knowledge)` only if a durable, non-obvious,
team-relevant learning emerged and to skip otherwise (routine or repo-derivable facts).
The existing human approval at write time MUST remain the safety gate; this requirement
adds a *when-to-consider* signal only and MUST NOT introduce any autonomous write. The
hint text MUST contain the literal `Skill(auto-claude-skills:capture-knowledge)`
invocation so the model can act on it. `config/fallback-registry.json` MUST stay in sync
with `config/default-triggers.json` for these hints (enforced by the existing Fallback
Registry Sync Gate). The pre-existing capture-keyword trigger MUST continue to work.

#### Scenario: LEARN phase surfaces capture-knowledge without keywords

- **GIVEN** a registry whose `LEARN` driver (`outcome-review`) is available
- **WHEN** a prompt routes to `PRIMARY_PHASE == LEARN` with no capture/save/remember keyword (e.g. "how did the auth feature perform after launch")
- **THEN** the activation context MUST contain `Skill(auto-claude-skills:capture-knowledge)` carried by a relevance-gated `CAPTURE KNOWLEDGE` hint

#### Scenario: SHIP phase surfaces capture-knowledge without keywords

- **GIVEN** a registry whose `SHIP` driver (`verification-before-completion`) is available
- **WHEN** a prompt routes to `PRIMARY_PHASE == SHIP` with no capture keyword (e.g. "wrap up the auth module and ship the release")
- **THEN** the activation context MUST contain `Skill(auto-claude-skills:capture-knowledge)`

#### Scenario: DEBUG phase surfaces capture-knowledge without keywords

- **GIVEN** a registry whose `DEBUG` driver (`systematic-debugging`) is available
- **WHEN** a prompt routes to `PRIMARY_PHASE == DEBUG` with no capture keyword (e.g. "debug the broken auth login error")
- **THEN** the activation context MUST contain `Skill(auto-claude-skills:capture-knowledge)` via a post-resolution `CAPTURE KNOWLEDGE` hint

#### Scenario: Not an unconditional banner

- **GIVEN** any phase other than LEARN, SHIP, or DEBUG (e.g. DESIGN, PLAN, IMPLEMENT, REVIEW)
- **WHEN** a prompt routes to that phase with no capture keyword
- **THEN** the `CAPTURE KNOWLEDGE` phase hint MUST NOT be emitted (surfacing is phase-scoped, not global)
