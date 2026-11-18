# skill-routing delta: hook commands quote the plugin root

## ADDED Requirements

### Requirement: Hook commands quote the plugin root

Every command in `hooks/hooks.json` MUST quote its `${CLAUDE_PLUGIN_ROOT}` path, in the form `"${CLAUDE_PLUGIN_ROOT}/hooks/<script>.sh"` followed by any arguments, so that a plugin path containing a space still names the script.

#### Scenario: plugin installed under a path with a space

- **GIVEN** the plugin root is a directory whose path contains a space
- **WHEN** the harness runs any registered hook command through a shell, with `${CLAUDE_PLUGIN_ROOT}` either expanded from the environment or substituted as text
- **THEN** the shell SHALL run the hook script with its arguments, not a path truncated at the space

#### Scenario: an unquoted command is added

- **GIVEN** a `hooks/hooks.json` command that does not start with `"${CLAUDE_PLUGIN_ROOT}/`
- **WHEN** `tests/test-hook-file-modes.sh` runs
- **THEN** it SHALL fail naming that command
