# Spec delta: skill-routing — a rendered hint's plugin paths must be openable

## ADDED Requirements

### Requirement: Rendered guidance MUST name a plugin file by an absolute path

Any text the routing hooks render into a prompt from a skill's `precondition` or
from a `methodology_hints[].hint` that names a file shipped inside this plugin
MUST name it by a path the reader can open. Because `CLAUDE_PLUGIN_ROOT` is not
set in the model's shell and the file is absent from the user's project, a
repo-relative name is openable only in this repo. Such a path SHALL be written in
the config as `{{PLUGIN_ROOT}}/<path>` and the renderer SHALL substitute the
running plugin root before emission. A path naming a file in the USER's project
MUST stay relative.

`phase_compositions[*].hints[].text` is rendered by the same hook and is
deliberately OUT of this requirement's scope, because three instances violate it
today (DISCOVER and DESIGN name `scripts/persist-state.sh` via the unset
`CLAUDE_PLUGIN_ROOT` pair; PLAN names `scripts/scope-conformance.sh` relatively —
measured `rc=127` in an external repo). Widening the requirement to that field
without fixing them would commit a spec the shipped code violates. Bringing that
field in is a separate change; until then this requirement's population is stated
here rather than implied, and the lint enforcing it reads
`methodology_hints` only.

#### Scenario: A hint's plugin path is substituted and opens in an adopting repo

- **GIVEN** a methodology hint whose text contains `{{PLUGIN_ROOT}}/<path>`
- **WHEN** the hint is rendered for a prompt in a repo that is not this plugin
- **THEN** the emitted text MUST contain no `{{PLUGIN_ROOT}}` literal
- **AND** the emitted path MUST be absolute and readable with
  `CLAUDE_PLUGIN_ROOT` unset

#### Scenario: A path naming the user's own file is not rewritten

- **GIVEN** a hint that names both a plugin file and a file the user adopts into
  their own repo
- **WHEN** the hint is rendered
- **THEN** only the plugin path MUST be made absolute, and the user's path MUST
  stay relative to their project

#### Scenario: A plugin root containing a space survives substitution

- **GIVEN** a plugin root whose path contains a space
- **WHEN** a hint naming a plugin file is rendered
- **THEN** the emitted path MUST contain the root whole and MUST be readable

### Requirement: A rendered path's quoting MUST follow its consumer

A plugin path emitted inside a shell command the reader pastes SHALL be
single-quoted, with a contained single quote escaped, so that the command is
parseable and inert. A plugin path emitted as the NAME of a file for the reader
to open SHALL be emitted bare, because shell quoting characters passed to a
file-reading tool are part of the path and make it unopenable.

#### Scenario: A hint path is emitted without shell quoting

- **GIVEN** a hint naming a plugin file for the reader to read
- **WHEN** the hint is rendered
- **THEN** the emitted path MUST NOT be wrapped in shell quotes
