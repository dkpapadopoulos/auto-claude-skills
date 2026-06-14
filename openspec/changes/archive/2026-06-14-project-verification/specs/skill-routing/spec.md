# Capability: skill-routing

## ADDED Requirements

### Requirement: Hint-path triggers must self-anchor against substring mis-fires

Triggers evaluated on the hint path (`hooks/skill-activation-hook.sh` raw `[[ "$P" =~ $htrigger ]]`) are NOT covered by the scorer's word-boundary post-filter and therefore MUST anchor their own alternations. Anchoring MUST use POSIX-ERE bracket-class boundaries `(^|[^a-z])…([^a-z]|$)` and MUST NOT use `\b`, `\d`, `(?:…)`, or other PCRE constructs, which silently fail to match under Bash 3.2. The `frontend-playwright` trigger specifically MUST NOT fire on backend prompts whose words merely contain a frontend fragment as a substring.

#### Scenario: Backend prompt does not trigger the Playwright mandate
- **GIVEN** a pure-backend prompt such as "tabulate the metrics", "update onboarding docs", or "paginate the results"
- **WHEN** the activation hook evaluates the `frontend-playwright` trigger under `/bin/bash` (3.2)
- **THEN** the trigger MUST NOT match
- **AND** no Playwright/frontend validation mandate MUST be emitted

#### Scenario: Genuine frontend prompt still triggers
- **GIVEN** a frontend prompt such as "the button component", "fix the navbar", or "make the layout responsive"
- **WHEN** the activation hook evaluates the `frontend-playwright` trigger under `/bin/bash` (3.2)
- **THEN** the trigger MUST match
- **AND** the Playwright/frontend hint MUST be emitted

#### Scenario: Anchored regex compiles under Bash 3.2
- **GIVEN** the anchored `frontend-playwright` trigger expression
- **WHEN** the regex-compilation test in `tests/test-routing.sh` runs under `/bin/bash`
- **THEN** the expression MUST compile (exit code not 2) and MUST be present identically in both `config/default-triggers.json` and `config/fallback-registry.json`
