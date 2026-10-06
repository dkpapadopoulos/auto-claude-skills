## ADDED Requirements

### Requirement: Gate-gaming scope may be declared and is read from the merge-base

The verdict writer SHALL take the gate-gaming diff over the paths listed under `gate_gaming_paths:` in `.verify.yml`, plus `.verify.yml` itself, when a usable declaration exists at the merge-base with the mainline. The declaration MUST be read from the merge-base revision and MUST NOT be read from the branch head, the index or the working tree. When no declaration exists at the merge-base, or `.verify.yml` is not a regular file there, the writer SHALL use the name glob (`*test*`, `*spec*`, `.verify.yml`) unchanged.

#### Scenario: A marker on a file the gate runs

- **GIVEN** the merge-base declares `tests/`
- **WHEN** the branch adds a skip marker to a test file under `tests/`
- **THEN** `gate_gaming_status` MUST be `suspect`
- **AND** a push of that branch touching a routing path MUST be denied by routing governance

#### Scenario: The same marker quoted in a document

- **GIVEN** the merge-base declares `tests/`
- **WHEN** the branch adds a file under `docs/` that contains the same marker inside a string
- **THEN** `gate_gaming_status` MUST be `clean`
- **AND** `gate_gaming_scope` MUST be `declared`

#### Scenario: No declaration

- **GIVEN** the merge-base has no `gate_gaming_paths` key
- **WHEN** the branch adds that file under `docs/`
- **THEN** `gate_gaming_status` MUST be `suspect`
- **AND** `gate_gaming_scope` MUST be `default`

#### Scenario: A branch edits its own declaration

- **GIVEN** the merge-base declares `tests/`, or declares nothing
- **WHEN** the branch adds or re-points `gate_gaming_paths` — committed, staged or uncommitted — and adds a skip marker to a test file under `tests/`
- **THEN** the scope MUST be the one at the merge-base
- **AND** `gate_gaming_status` MUST be `suspect`

### Requirement: A changed declaration is suspect

The writer SHALL record `gate_gaming_status` as `suspect` in place of `clean` when the declaration committed at the branch head differs from the declaration at the merge-base, unless both are usable and every path declared at the merge-base is still declared at the head. The verdict SHALL carry `gate_gaming_scope_change` with the value `none`, `widened` or `changed`.

#### Scenario: A branch only narrows the declaration

- **GIVEN** the merge-base declares `tests/` and `docs/`
- **WHEN** the branch commits a declaration of `docs/` alone and changes nothing else
- **THEN** `gate_gaming_status` MUST be `suspect`
- **AND** `gate_gaming_scope_change` MUST be `changed`

#### Scenario: A branch adds a first declaration

- **GIVEN** the merge-base has no `gate_gaming_paths` key
- **WHEN** the branch commits one
- **THEN** `gate_gaming_status` MUST be `suspect`

#### Scenario: A branch only adds a path

- **GIVEN** the merge-base declares `tests/`
- **WHEN** the branch commits a declaration of `tests/` and `docs/`
- **THEN** `gate_gaming_status` MUST be `clean`
- **AND** `gate_gaming_scope_change` MUST be `widened`

### Requirement: An unusable declaration leaves the check unverified

When the declaration at the merge-base is an inline list, is declared more than once, has no entries, or contains an entry that is quoted, starts with `:`, `-` or `/`, contains `..` as a path segment, contains whitespace, or matches no file at the merge-base, the writer MUST NOT run the check over any pathspec. It SHALL record `gate_gaming_status` as `unverified`, add `gate-gaming-check` to `could_not_verify`, record `gate_gaming_scope` as `unusable`, and print the reason. It MUST NOT apply a subset of the declared paths and MUST NOT fall back to the name glob.

#### Scenario: Pathspec magic

- **GIVEN** the merge-base declares `docs/` and `:(exclude)tests/`
- **WHEN** the writer records a verdict
- **THEN** `gate_gaming_status` MUST be `unverified`
- **AND** `gate_gaming_scope` MUST be `unusable`

#### Scenario: A declared file the name glob would not select

- **GIVEN** the merge-base declares `checks/validate.py` and a second entry that matches no file
- **WHEN** the branch removes an assertion from `checks/validate.py`
- **THEN** `gate_gaming_status` MUST NOT be `clean`

### Requirement: The verdict records the scope that was used

The verdict SHALL carry `gate_gaming_scope` with the value `declared`, `default`, `unusable` or `unverified`, and `gate_gaming_paths` with the pathspec the diff was taken over. `unverified` and an empty list SHALL be recorded when no base could be resolved or the checker is missing.

#### Scenario: A declared scope

- **GIVEN** the merge-base declares `tests/`
- **WHEN** the writer records a verdict
- **THEN** `gate_gaming_paths` MUST be `["tests/", ".verify.yml"]`

#### Scenario: A gate entry removed under a declared scope

- **GIVEN** the merge-base declares `tests/`
- **WHEN** the branch deletes a `- name:` entry from `.verify.yml`
- **THEN** `gate_gaming_status` MUST be `suspect`
