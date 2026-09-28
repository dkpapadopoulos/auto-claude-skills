# skill-routing

## ADDED Requirements

### Requirement: A file the model reads MUST NOT re-derive the plugin root

A file the plugin ships for the model to read verbatim — today those under
`skills/` and `commands/` — MUST NOT attempt to compute the plugin's location. The
session-start hook SHALL state the absolute plugin root once in the session
context, and such files SHALL reference it through the documented placeholder.

`CLAUDE_PLUGIN_ROOT` is set for hook processes and unset in the model's shell, so
every re-derivation resolves somewhere other than the plugin: a
`$(git rev-parse --show-toplevel)` fallback resolves to the USER's repository, a
`.` fallback resolves to the current working directory, and a bare expansion
yields the empty string, making the path start at the filesystem root.

This requirement is stated over *re-derivation*, not over a list of spellings.
The population of bad spellings was measured three times during the change that
introduced this requirement and was wrong twice; a requirement enumerating the
forms that happened to ship is satisfied by the next form that does not.

#### Scenario: A skill names a plugin script from an adopting repository

- **GIVEN** a repository that is not this plugin, with `CLAUDE_PLUGIN_ROOT` unset
- **WHEN** the session-start hook runs
- **THEN** the emitted session context MUST contain an absolute plugin root
- **AND** that path MUST be readable from the adopting repository

#### Scenario: No model-read file derives the plugin root

- **GIVEN** the files shipped under `skills/` and `commands/`
- **WHEN** they are linted
- **THEN** none of them MAY derive the root — not by expanding
  `CLAUDE_PLUGIN_ROOT` in any fallback form, not from `$0`, and not by naming a
  plugin file by a bare relative path
- **AND** prose that names the variable without expanding it MUST remain allowed,
  so guidance can say what not to do
- **AND** a documented search for the installed plugin directory MUST remain
  allowed, because that is how a reader LOCATES the root rather than guessing it

#### Scenario: Every plugin script a skill names resolves under the emitted root

- **GIVEN** the plugin scripts named by files under `skills/` and `commands/`
- **WHEN** each is resolved against the emitted plugin root
- **THEN** every one MUST exist and be readable

### Requirement: A renderer's placeholder MUST NOT be used where nothing renders

The `{{PLUGIN_ROOT}}` placeholder substituted by the routing hooks MUST NOT
appear in a file the Skill tool hands to the model verbatim. No substitution
occurs on that path, so the literal braces would reach the reader — a worse
outcome than an incorrect expansion, which at least produces a path.

Where a non-rendered file must name the plugin root, it SHALL use the
angle-bracket placeholder documented in the session context, consistent with the
other substitution points those files already use.

#### Scenario: The rendered placeholder is kept out of non-rendered files

- **GIVEN** the files shipped under `skills/` and `commands/`
- **WHEN** they are linted
- **THEN** none of them MAY contain `{{PLUGIN_ROOT}}`

#### Scenario: The substitution convention is explained where the reader can see it

- **GIVEN** model-read files that use the angle-bracket placeholder
- **WHEN** the session-start hook emits its context
- **THEN** that context MUST name the placeholder and instruct the reader to
  substitute the emitted root for it

### Requirement: A pasted plugin path MUST be single-quoted

A placeholder standing in for the plugin root, where it is immediately followed
by `/` and therefore names a path, SHALL be single-quoted. A placeholder not
followed by `/` names the token itself and is unconstrained. The rule is
deliberately UNCONDITIONAL — it does not distinguish a command from a
reference. The reader substitutes a
literal filesystem path into that command, and a path is not necessarily inert:
measured, a root containing `$(...)` EXECUTES when the substituted line is
pasted inside double quotes. Single quotes also make an unsubstituted
placeholder a literal rather than a redirect operator, so a reader who forgets
to substitute gets a clear "no such file" naming the placeholder instead of a
truncated file.

The read-versus-paste asymmetry ruled for RENDERED text does not apply here, and
the reason is the premise. That rule keeps shell quotes out of a REAL path: a
hook emits a resolved `/abs/path`, an agent reuses that token verbatim, and the
quoted form does not exist. It protects against verbatim reuse of a resolved
string. A placeholder-bearing span can never be reused verbatim — it is not a
path, it does not resolve, and the reader must construct a new string before it
is usable — so the premise is false for every such span and the asymmetry has
nothing to act on.

This requirement is therefore ENFORCED BY ITS OWN SHAPE rather than by a
separate check. No content check can decide whether a quoted path is meant to be
opened or pasted. But the rule forbids the BARE spelling, and bare is the only
form an author following the read-versus-paste convention would write, so a read
target cannot be expressed in its correct shape and cannot appear silently. The
invariant it upholds: no model-read file may contain a placeholder-bearing READ
target. Where one would
otherwise be needed, the file SHALL name the script some nearby runnable step
already names, rather than giving a path of its own. If that invariant is ever
broken the rule over-quotes the read, which is the safe direction: an
over-quoted read fails loudly and names the quotes in its own error, while an
under-quoted paste executes a command substitution contained in the root.

#### Scenario: A substituted path cannot execute on paste

- **GIVEN** a model-read file naming the plugin root placeholder followed by `/`
- **WHEN** the file is linted
- **THEN** that placeholder MUST be single-quoted, whether the surrounding text
  reads as a command or as a reference

#### Scenario: A placeholder that names no path is unconstrained

- **GIVEN** a model-read file naming the placeholder with no `/` after it
- **WHEN** the file is linted
- **THEN** the lint MUST NOT require quoting, because no path is being formed

#### Scenario: The plugin root is stated even when jq is absent

- **GIVEN** a session where `jq` is not installed, so the hook takes its
  degraded path
- **WHEN** the session-start hook emits its message
- **THEN** that message MUST still state the absolute plugin root, unless the
  path cannot be represented in the hand-built JSON that path emits
- **AND** the emitted message MUST remain parseable JSON
