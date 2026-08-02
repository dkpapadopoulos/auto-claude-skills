# Spec: serena-mcp-registration

## ADDED Requirements

### Requirement: Serena registrations MUST use an absolute path

The plugin MUST register the Serena MCP server with an absolute, executable
`serena` path so the registration succeeds regardless of the PATH of the process
that later spawns the MCP server. A bare `serena` command MUST NOT be written.

The plugin MUST resolve the absolute path via `command -v serena`, and when that
fails, by probing (in order, first executable wins): `$HOME/.local/bin/serena`,
`$HOME/.local/share/uv/tools/serena-agent/bin/serena`, `$HOME/.cargo/bin/serena`.

#### Scenario: Auto-register writes an absolute path
- **GIVEN** `serena` resolves to `/Users/x/.local/bin/serena` and no Serena MCP
  registration exists
- **WHEN** the session-start auto-registration runs
- **THEN** it invokes `claude mcp add` with command
  `/Users/x/.local/bin/serena start-mcp-server …`, not bare `serena`
- **AND** it writes the `…-serena-registered` marker

#### Scenario: Resolver falls back to a probe when serena is off PATH
- **GIVEN** `serena` is NOT on the current PATH but exists and is executable at
  `$HOME/.local/bin/serena`
- **WHEN** `serena_resolve_bin` is called
- **THEN** it echoes `$HOME/.local/bin/serena` and returns success

#### Scenario: Resolver reports failure when serena is absent everywhere
- **GIVEN** `serena` is not on PATH and none of the probed paths exist
- **WHEN** `serena_resolve_bin` is called
- **THEN** it echoes nothing and returns non-zero

### Requirement: A bare-command registration MUST self-heal once

The plugin MUST detect an existing Serena registration whose command is a bare
`serena` and rewrite it to the resolved absolute path, at most once per machine,
preserving the registration's scope and args. The operation MUST be fail-open: any
missing precondition (no `claude` CLI, unresolvable serena, unreadable
registration) or error MUST NOT block session start, MUST leave any existing
registration intact, and MUST record a one-time marker so it does not retry every
session.

#### Scenario: Existing bare registration is rewritten to an absolute path
- **GIVEN** a `serena` registration exists with command `serena` (bare),
  `serena` resolves to an absolute path, and the migration marker is absent
- **WHEN** session start runs the self-heal
- **THEN** the registration is rewritten (via `claude mcp` remove+add) with the
  absolute serena command, preserving its scope and args
- **AND** the `…-serena-abspath-migrated` marker is written

#### Scenario: Self-heal is idempotent and skips healthy registrations
- **GIVEN** the migration marker already exists, OR the existing registration
  already uses an absolute path
- **WHEN** session start runs the self-heal
- **THEN** no `claude mcp remove`/`add` is invoked and session start is unaffected

#### Scenario: Self-heal fails open when serena cannot be resolved
- **GIVEN** a bare `serena` registration exists but serena resolves nowhere
- **WHEN** session start runs the self-heal
- **THEN** the existing registration is NOT removed, a breadcrumb is written, and
  session start completes normally
