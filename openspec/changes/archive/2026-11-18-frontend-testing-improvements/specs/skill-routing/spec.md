# Spec Delta: skill-routing

## ADDED Requirements

### Requirement: Advisory routing to external frontend-quality skills

The routing config SHALL include a `frontend-quality-rules` methodology hint that advises using the
external Vercel frontend-quality skills when they are installed, without gating on a `.plugin`
field and without emitting a hardcoded `Skill(<plugin>:<skill>)` invocation token. The hint SHALL
name our own `frontend-design` and `runtime-validation` skills as the fallback. React/Next-specific
guidance (`react-best-practices`) SHALL be offered only on React/Next signals; framework-agnostic
guidance (`web-interface-guidelines`) MAY be offered on general frontend signals. The hint SHALL
fire in the `IMPLEMENT` and `REVIEW` phases, and its triggers SHALL self-anchor word boundaries
`(^|[^a-z])…($|[^a-z])`.

#### Scenario: Hint surfaces on a React frontend prompt in IMPLEMENT

- **GIVEN** a session in the `IMPLEMENT` phase
- **WHEN** the user prompt matches a React/Next frontend signal (e.g. "add a React component")
- **THEN** the routing context SHALL include the `frontend-quality-rules` advisory hint text
- **AND** the hint SHALL reference `react-best-practices` and name `frontend-design` /
  `runtime-validation` as the fallback

#### Scenario: Hint does not hardcode an unknowable invocation token

- **GIVEN** the `frontend-quality-rules` hint definition in `config/default-triggers.json`
- **WHEN** the hint text is inspected
- **THEN** it SHALL NOT contain a literal `Skill(` invocation for the external Vercel skills
- **AND** it SHALL phrase the reference conditionally ("if installed")

#### Scenario: Config is mirrored to the fallback registry

- **GIVEN** the `frontend-quality-rules` hint added to `config/default-triggers.json`
- **WHEN** the fallback registry is regenerated
- **THEN** `config/fallback-registry.json` SHALL contain the same hint, keeping the two files in sync

### Requirement: frontend-playwright hint fires in REVIEW

The `frontend-playwright` methodology hint SHALL include `REVIEW` in its `phases` so that its
"During REVIEW, use runtime-validation" guidance can fire in the REVIEW phase.

#### Scenario: frontend-playwright surfaces in REVIEW

- **GIVEN** a session in the `REVIEW` phase
- **WHEN** the user prompt matches a frontend signal (e.g. "review the login form")
- **THEN** the routing context SHALL include the `frontend-playwright` hint text

### Requirement: runtime-validation routes on visual-regression terms

The `runtime-validation` skill triggers SHALL match `visual regression`, `layout regression`, and
`screenshot` terms, without matching unrelated substrings (e.g. `tabulate`, `onboarding`).

#### Scenario: Visual-regression prompt routes to runtime-validation

- **GIVEN** a session in the `REVIEW` phase
- **WHEN** the user prompt contains "visual regression" or "screenshot" in a validation context
- **THEN** `runtime-validation` SHALL be surfaced in the routing context

#### Scenario: Negative terms do not false-trigger

- **GIVEN** the `runtime-validation` trigger regex
- **WHEN** matched against `tabulate the results` or `user onboarding flow`
- **THEN** the visual-regression terms SHALL NOT match those substrings
