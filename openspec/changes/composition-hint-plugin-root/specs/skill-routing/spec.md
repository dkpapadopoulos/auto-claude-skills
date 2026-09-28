# skill-routing

## MODIFIED Requirements

### Requirement: Rendered guidance MUST name a plugin file by an absolute path

Any text the routing hooks render into a prompt that names a file shipped inside
this plugin MUST name it by a path the reader can open. Because
`CLAUDE_PLUGIN_ROOT` is not set in the model's shell and the file is absent from
the user's project, a repo-relative name — and the pair
`${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)}`, which resolves to the
USER's repo root — is openable only in this repo. Such a path SHALL be written
as `{{PLUGIN_ROOT}}/<path>` and the renderer SHALL substitute the running plugin
root before emission. A path naming a file in the USER's project MUST stay
relative.

This requirement is deliberately stated over **rendered text**, not over a list
of fields. The enumeration of rendering surfaces has been wrong three times
(four → five → six → eight), so a requirement scoped to named fields is
satisfied by the next surface that is added and missed. The surfaces known to
carry such text today are a skill's `precondition`, `methodology_hints[].hint`,
`phase_compositions[*].hints[].text`, the hint text the `spec-driven` preset
injects from `session-start-hook.sh`, and directives the activation hook
hardcodes into `SKILL_LINES`. That list is illustrative; a new surface is in
scope on the day it renders, not on the day it is added here.

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

#### Scenario: A composition hint's plugin path resolves outside this plugin

- **GIVEN** a `phase_compositions[*].hints[].text` naming `scripts/persist-state.sh`
- **WHEN** the hint is rendered for a prompt in a repo that is not this plugin
- **THEN** the emitted text MUST contain no `CLAUDE_PLUGIN_ROOT` fallback pair
- **AND** the emitted path MUST be absolute and readable with
  `CLAUDE_PLUGIN_ROOT` unset

#### Scenario: A preset that rewrites a hint preserves the placeholder

- **GIVEN** `~/.claude/skill-config.json` sets `"preset": "spec-driven"`, which
  rewrites `phase_compositions.DESIGN.hints[].text`
- **WHEN** the rewritten hint is rendered in a repo that is not this plugin
- **THEN** the emitted path MUST be absolute and readable, exactly as the
  default text's would be

### Requirement: A rendered path's quoting MUST follow its consumer

A plugin path emitted inside a shell command the reader pastes SHALL be
single-quoted, with a contained single quote escaped, so that the command is
parseable and inert. A plugin path emitted as the NAME of a file for the reader
to open SHALL be emitted bare, because shell quoting characters passed to a
file-reading tool are part of the path and make it unopenable.

Where a single rendering surface carries both kinds — as
`phase_compositions[*].hints[].text` does — the consumer SHALL be declared by
the text itself, and the classification is per-TEXT, not per-placeholder: a text
containing `'{{PLUGIN_ROOT}}/…'` is a pasted command and every placeholder in it
takes the escaped treatment; otherwise a bare `{{PLUGIN_ROOT}}/…` names a file
and takes none. The escaping SHALL be performed by the single shared expander
rather than reimplemented per surface.

Because the classification is per-text, a single text MUST NOT mix the two
spellings — one treatment would be applied to both — and the two spellings above
are the ONLY supported ones. In particular a double-quoted `"{{PLUGIN_ROOT}}"`
MUST be rejected rather than silently treated as bare: it is the most natural
shell spelling and the exact form the broken instances used, so accepting it
quietly reintroduces an unescaped path into a pasted command. Every `{{…}}`
occurring in such a text MUST be exactly `{{PLUGIN_ROOT}}`; an unrecognised
placeholder is substituted by nothing and reaches the reader as literal braces.

#### Scenario: An unsupported placeholder spelling is rejected

- **GIVEN** a hint text whose placeholder is misspelled, double-quoted, or which
  mixes the quoted and bare spellings
- **WHEN** the configuration is linted
- **THEN** the lint MUST fail and name the supported spellings

#### Scenario: A hint path is emitted without shell quoting

- **GIVEN** a hint naming a plugin file for the reader to read
- **WHEN** the hint is rendered
- **THEN** the emitted path MUST NOT be wrapped in shell quotes

#### Scenario: A quoted placeholder survives a root containing a single quote

- **GIVEN** a plugin root whose path contains a single quote
- **WHEN** a composition hint written `'{{PLUGIN_ROOT}}/<path>'` is rendered
- **THEN** the emitted line MUST parse as a shell command
- **AND** the path MUST survive as exactly one shell word

#### Scenario: A bare placeholder is not escaped

- **GIVEN** a plugin root whose path contains a single quote
- **WHEN** a composition hint written with a bare `{{PLUGIN_ROOT}}/<path>` is
  rendered
- **THEN** the emitted path MUST contain the root verbatim, with no escaping
  characters inserted
