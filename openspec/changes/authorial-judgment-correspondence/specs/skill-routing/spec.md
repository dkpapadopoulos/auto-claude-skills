# skill-routing: frontend-quality hint leads with an evidence-and-behaviour baseline

## MODIFIED Requirements

### Requirement: Advisory routing to external frontend-quality skills

The routing config SHALL include a `frontend-quality-rules` methodology hint whose text
leads with an evidence-and-behaviour baseline an agent can act on in any install: use
real evidence for testimonials, logos, statistics and product claims, omit unsupported
proof and label simulated results; exercise every changed action and its loading,
empty, error and success states at desktop and phone widths and by keyboard; report
what was exercised and what remains unfinished. The hint SHALL name our own
`runtime-validation` skill as the skill that runs those checks. After the baseline, the
hint SHALL offer the external Vercel frontend-quality skills conditionally ("if
installed"), without gating on a `.plugin` field and without emitting a hardcoded
`Skill(<plugin>:<skill>)` invocation token. React/Next-specific guidance
(`react-best-practices`) SHALL be offered only on React/Next signals; framework-agnostic
guidance (`web-design-guidelines`) MAY be offered on general frontend signals. The
identifier is the upstream skill's `name` (vercel-labs/agent-skills `skills/web-design-guidelines`);
"Web Interface Guidelines" is its heading, and `web-interface-guidelines` resolves to nothing. The
hint SHALL fire in the `IMPLEMENT` and `REVIEW` phases, and its triggers SHALL
self-anchor word boundaries `(^|[^a-z])…($|[^a-z])`. The hint's name, triggers and
phases are unchanged by this requirement; only its text is.

#### Scenario: Hint surfaces on a React frontend prompt in IMPLEMENT

- **GIVEN** a session in the `IMPLEMENT` phase
- **WHEN** the user prompt matches a React/Next frontend signal (e.g. "add a React component")
- **THEN** the routing context SHALL include the `frontend-quality-rules` advisory hint text
- **AND** the text SHALL state the evidence-and-behaviour baseline before any external skill
- **AND** the hint SHALL reference `react-best-practices` conditionally and name
  `runtime-validation` for the checks

#### Scenario: Hint does not hardcode an unknowable invocation token

- **GIVEN** the `frontend-quality-rules` hint definition in `config/default-triggers.json`
- **WHEN** the hint text is inspected
- **THEN** it SHALL NOT contain a literal `Skill(` invocation for the external Vercel skills
- **AND** it SHALL phrase the reference conditionally ("if installed")

#### Scenario: Config is mirrored to the fallback registry

- **GIVEN** the `frontend-quality-rules` hint in `config/default-triggers.json`
- **WHEN** the fallback registry is regenerated
- **THEN** `config/fallback-registry.json` SHALL contain the same hint, keeping the two files in sync

#### Scenario: Hint text change adds no mandate

- **GIVEN** the negative corpus under `tests/probes/negative-corpus/`
- **WHEN** the scan is run before and after the hint text change
- **THEN** the diff of selected skills and rendered hints SHALL be empty except for the hint's own text
