## ADDED Requirements

### Requirement: Phase hints name the owning skill and stay short

Each `phase_compositions.<PHASE>.hints[].text` SHALL be at most 480 bytes; a hint of 300 bytes or more SHALL name the `Skill(...)` or plugin script that owns the procedure it refers to, and SHALL state the condition under which it applies. The full procedure MUST live in the owning skill's `SKILL.md`. The per-phase byte totals (DESIGN, PLAN, REVIEW, SHIP) SHALL be pinned as ratchets in `tests/test-phase-hint-brevity.sh` and MUST move only in the commit that moves them. (The first draft said 240 bytes; the spec-driven PERSIST DESIGN hint carries the three-file layout the model must reproduce, and that list is the content, so the ceiling is 480.)

#### Scenario: A DESIGN block is rendered

- **WHEN** the activation hook renders the DESIGN phase hints
- **THEN** every hint is at most 480 bytes, every hint of 300 bytes or more contains `Skill(` or a plugin script, and the EVAL STRATEGY, AUTONOMY CHECK and ADVERSARIAL REVIEW procedures are present in full in `skills/runtime-validation/SKILL.md`, `skills/agent-safety-review/SKILL.md` and `skills/agent-team-review/SKILL.md`

#### Scenario: Hint content changes

- **WHEN** only hint texts and the INTENT EXTRACTION directive change
- **THEN** the composition-state file and the push gate's decision are byte-identical to the previous render for the same input

### Requirement: An unmet gating milestone states its consequence

When the composition chain renders `requesting-code-review` or `verification-before-completion` with any marker other than `[DONE]`, the line SHALL state that `git push` is denied until that Skill is invoked. Non-gating steps MUST NOT carry the suffix. The suffix MUST NOT change any state file or any gate decision.

#### Scenario: Review step not yet invoked

- **WHEN** a chain's `requesting-code-review` step is `[NEXT]`
- **THEN** its line ends with the denial suffix and the `writing-plans` line does not, and the state file bytes equal those of a render without the suffix

### Requirement: External plugins cannot rewrite config-owned topology

At registry build, frontmatter from an external-marketplace plugin's `SKILL.md` whose directory name matches a config-owned skill MUST NOT change that skill's `role`, `phase`, `precedes` or `requires`. It MAY still supply `triggers` and `priority`. Frontmatter from this plugin's bundled skills and from the user's skills directory keeps its overrides.

#### Scenario: Planted external skill

- **WHEN** an external plugin ships `skills/verification-before-completion/SKILL.md` with `role: domain`, `phase: DESIGN`, `precedes`, `requires`, `priority: 1` and `triggers`
- **THEN** the registry entry keeps the config `role`, `phase`, `precedes` and `requires`, and carries the planted `priority` and `triggers`

#### Scenario: Bundled skill with topology frontmatter

- **WHEN** `skills/deploy-gate/SKILL.md` declares `role`, `phase`, `precedes` and `requires`
- **THEN** the registry entry equals the config entry, as today

### Requirement: The injection ratchet is independent of the checkout's git state

`tests/test-injection-budget.sh` SHALL present the hook with a fixture git repository in a fixed state (one commit, `origin/main` at HEAD, clean tree) on every probe, and SHALL carry a control that dirties the fixture and asserts the PHASE REALITY line disappears.

#### Scenario: Suite runs in a dirty worktree

- **WHEN** the suite runs in a checkout with uncommitted changes or commits ahead of `origin/main`
- **THEN** the measured total equals the total on a clean main checkout

### Requirement: Session-start fork count is pinned

The session-start hook SHALL issue no more external-process forks for `jq`, `basename`, `dirname`, `ls`, `grep`, `sort` and `awk` than the ratchet constant in `tests/test-session-start-fork-budget.sh` over the test fixture; the constant MUST only change in the commit that moves it. Semver directory selection MUST compare components numerically.

#### Scenario: Versions 9.9.9 and 10.0.0 exist

- **WHEN** a plugin directory contains both
- **THEN** `10.0.0/` is resolved
