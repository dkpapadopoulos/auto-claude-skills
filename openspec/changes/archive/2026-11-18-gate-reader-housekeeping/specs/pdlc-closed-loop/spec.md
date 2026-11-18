## ADDED Requirements

### Requirement: Archive provenance records a measured OpenSpec surface

`openspec_write_provenance` MUST record `openspec_surface` as the session state's value when that value is a string other than `none`, otherwise as `openspec_capabilities.surface` from the registry cache session-start writes, otherwise as `unknown`. It MUST record `none` only when the registry cache says `none`.

#### Scenario: The ship path, which never sets the surface in session state

- **GIVEN** a session state file created by `openspec_state_upsert_change` and a registry cache whose surface is `openspec-core`
- **WHEN** `openspec_write_provenance` runs
- **THEN** `source.json` holds `openspec_surface: "openspec-core"`

#### Scenario: No registry cache

- **GIVEN** the same state file and no registry cache
- **WHEN** `openspec_write_provenance` runs
- **THEN** `source.json` holds `openspec_surface: "unknown"`
