## ADDED Requirements

### Requirement: The push gate MUST announce when a missing external tool disables it

When `jq` is not on `PATH`, `hooks/openspec-guard.sh` SHALL emit an advisory naming `jq` as the cause, stating that the command was not gated, and naming the remedy. It MUST NOT deny: a check that cannot run must never block, and denying here would make every push impossible on a configuration `CLAUDE.md` documents as supported. It MUST NOT attempt to gate without `jq` — every check that reads recorded evidence parses it with jq and all seven deny sites serialise through it, so a gate that appeared to run would be reporting on checks whose inputs it could not read.

The announcement MUST survive the state in which the session token resolves. Fixing only the payload parser so a token resolves is insufficient and MUST NOT be treated as the fix: the guard then walks its whole length and still concludes nothing.

#### Scenario: A gated command is submitted on a machine without jq

- **WHEN** `jq` is absent from `PATH` and a `git push` is submitted
- **THEN** the guard emits a non-empty advisory naming `jq`, stating the command was not gated, and carrying no `permissionDecision`

#### Scenario: A token resolves but no gate can run

- **WHEN** `jq` is absent and a session token IS resolvable, so the guard passes the empty-token exit
- **THEN** the advisory still fires — the announcement is conditioned on the tool being missing, not on the token being unresolvable

#### Scenario: jq is present

- **WHEN** `jq` is available
- **THEN** the guard's output is byte-identical to its pre-change output, and carries no degradation note about `jq`

### Requirement: An announcement that is not valid JSON is not an announcement

Every advisory the guard emits without `jq` SHALL be escaped so the result parses as JSON. Escaping MUST handle the backslash before the quote, since escaping quotes first would then have its own escapes doubled. Text reaching these emitters includes interpolated filesystem paths and existing notes containing quotes, so this is reachable in normal operation rather than adversarially.

A malformed object is dropped by the harness, which returns the guard to exactly the silence the announcement exists to end — so this requirement is part of the announcement, not a cosmetic concern.

#### Scenario: The plugin path contains a backslash

- **WHEN** the guard announces degradation without `jq` and the interpolated plugin root contains a backslash or a quote
- **THEN** the emitted object still parses as JSON

#### Scenario: A warning already contains a quote

- **WHEN** the combined-warnings emitter runs without `jq` over text containing a quote
- **THEN** the emitted object still parses as JSON
