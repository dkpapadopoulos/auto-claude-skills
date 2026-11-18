# runtime-validation delta: the a11y overlay never downloads axe

## ADDED Requirements

### Requirement: The a11y overlay runs only an installed axe

The runtime-validation skill MUST run the axe a11y overlay only through an axe CLI that is already installed (a global `axe` or the project's `node_modules/.bin/axe`), and MUST NOT run it through `npx @axe-core/cli`, which downloads an unpinned version when the package is not installed.

#### Scenario: axe installed in the project

- **GIVEN** `node_modules/.bin/axe` is executable and no global `axe` is on PATH
- **WHEN** runtime-validation reaches the a11y overlay
- **THEN** it SHALL run `node_modules/.bin/axe --stdout` against the dev-server URL and read the violations from the first entry of the JSON array it prints

#### Scenario: axe not installed

- **GIVEN** no global `axe` and no `node_modules/.bin/axe`, even if `@axe-core/cli` is listed in `package.json`
- **WHEN** runtime-validation reaches the a11y overlay
- **THEN** it SHALL print that the overlay was skipped and SHALL NOT download or run any axe package
