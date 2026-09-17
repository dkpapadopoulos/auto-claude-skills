# design-foundations

## ADDED Requirements

### Requirement: Shipped design seed

The plugin SHALL ship a design seed under `assets/design-seed/` containing a
token set with semantic roles, a styleguide limited to rules a lint cannot
express, one dependency-free reference page, and an executable lint. `tokens.css`
SHALL be the source of truth and `tokens.json` SHALL hold exactly the same token
names and values. The seed SHALL be copied into a target project, which then
owns it; the plugin SHALL NOT read, rewrite, or silently upgrade a copied seed.
The reference page MUST NOT depend on any package manager, build step, or
framework.

#### Scenario: Token definitions cannot drift between formats

- **GIVEN** the shipped `assets/design-seed/`
- **WHEN** the token names and values in `tokens.css` and `tokens.json` are
  compared
- **THEN** the two sets MUST be identical, with no token present in one and
  absent from the other

#### Scenario: Seed carries no framework dependency

- **GIVEN** the shipped `assets/design-seed/` tree
- **WHEN** its contents are inspected
- **THEN** there MUST be no `package.json`, lockfile, build config, or remote
  script/style reference in the reference page

#### Scenario: Reference page shows the states that are hard to get right

- **GIVEN** `assets/design-seed/reference.html`
- **WHEN** it is inspected
- **THEN** it MUST demonstrate dense numeric display, a missing value rendered
  distinctly from an empty set, every status treatment the tokens define, and
  both light and dark themes

### Requirement: Token lint enforces references over a declared scope

The seed SHALL provide a lint that requires token references (`var(--token)`)
for the CSS properties it declares it covers, over an explicitly declared file
set. It SHALL state that scope in `--help` and in the styleguide, and SHALL NOT
claim general enforcement. Each diagnostic MUST carry a stable `TL-<n>` class.
A raw literal in a covered property MUST fail **even when its value equals a
token's value**, because a literal does not follow a theme change.

#### Scenario: A literal matching a token value is still a violation

- **GIVEN** a stylesheet in the declared file set setting a covered property to
  a raw literal whose value is exactly a token's value
- **WHEN** `token-lint.sh` runs
- **THEN** it MUST exit non-zero and report the file, the line, and a `TL-<n>`
  class

#### Scenario: Declared exceptions do not fire

- **GIVEN** a stylesheet whose only literals appear in comments, media-query
  conditions, `calc()` operands, or properties outside the declared coverage
- **WHEN** `token-lint.sh` runs
- **THEN** it MUST exit zero

### Requirement: Adoption records provenance and makes the guide reachable

Adoption SHALL record the preset name and version in the target project, and
SHALL add a pointer to the project's own agent instructions directing
implementation to the styleguide and the lint. The plugin SHALL NOT treat an
unmodified seed as a defect, and SHALL NOT ship a check that fails on one.

#### Scenario: Adopting the default unchanged is a supported outcome

- **GIVEN** a project that copied the seed and changed no token
- **WHEN** its `design/` directory and its checks are run and inspected
- **THEN** every check MUST exit zero, and `design/adopted.json` MUST record the
  preset name and version

### Requirement: Design method reachable without a design-project connector

The plugin SHALL document a design method whose primary lane requires no
external design-system connector, and SHALL surface it during the DESIGN phase
through a composition hint rather than a trigger-matched skill.

#### Scenario: DESIGN hint renders without adding a routed skill

- **GIVEN** the routing registry built from `config/default-triggers.json`
- **WHEN** a DESIGN-phase prompt is scored
- **THEN** the design-seed hint MUST be present in the DESIGN composition, and
  the registry MUST contain no skill entry whose triggers were added by this
  change
