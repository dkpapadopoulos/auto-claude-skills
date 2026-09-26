# Spec delta: design-foundations — the seed's own instructions must be runnable

## ADDED Requirements

### Requirement: The seed's adoption instructions MUST be executable as written

`ADOPT.md` SHALL NOT identify the seed directory by a token the reader cannot
obtain. It MUST be identified by something the reader holds — the directory the
file itself was opened from — and MUST NOT be derived from an environment
variable that is unset in the reader's shell. Any document the routing hint sends
the reader to SHALL reference sibling plugin files relative to its own location,
not relative to the reader's project.

#### Scenario: The adoption command runs in a repo that is not this plugin

- **GIVEN** the absolute path of the seed's `ADOPT.md`, as a rendered hint names it
- **WHEN** its copy command is run in an unrelated git repository, in either the
  hook shell or the model's shell, with `CLAUDE_PLUGIN_ROOT` unset
- **THEN** the seed's files MUST land under `design/`
- **AND** the copied token lint MUST run and pass over a stylesheet that
  references role tokens

#### Scenario: The method document's own references resolve

- **GIVEN** the method document, opened at an absolute path
- **WHEN** a relative reference in it is resolved against the document's own
  directory
- **THEN** the referenced path MUST exist
