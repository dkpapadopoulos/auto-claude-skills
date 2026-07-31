## ADDED Requirements

### Requirement: A fail-open hook MUST NOT exit early because a sourced lib returned non-zero

Every `.`/`source` invocation in a hook carrying `trap 'exit 0' ERR` MUST be written so that a non-zero **source status** cannot trip the trap — that is, the source MUST be a non-final operand of an `&&`/`||` list. Where the caller then uses a function from that lib, the guard MUST also confirm the function is defined before calling it, because a partially-sourced lib leaves the function undefined and the resulting command-not-found trips the same trap. An existence check (`[ -f "$lib" ]`) MUST NOT be treated as a guard: it proves only that the file is present, and the failure under test is a lib that exists and returns non-zero while sourcing.

This requirement is deliberately scoped to the source's own exit status. The `&&`/`||` form does NOT suppress the trap when a command *inside* the sourced file fails — that trap fires during the sourced file's execution — so satisfying this requirement MUST NOT be read as proving that no sourced lib can exit the hook. Measured: a lib that runs `false`, hits a command-not-found, or performs a failing `X="$(cd … && pwd)"` assignment still produces a silent allow. Closing that requires clearing the trap around the whole lib-loading region at every source site, and is tracked separately as issue #192.

#### Scenario: Push-gate token lib fails mid-source

- **WHEN** `hooks/lib/session-token.sh` exists but returns non-zero part-way through sourcing, and a `git push` command is submitted to `hooks/openspec-guard.sh`
- **THEN** the guard falls back to the singleton token, reaches its push decision, and emits a `permissionDecision` — rather than exiting 0 with empty stdout, which the harness cannot distinguish from an allow

#### Scenario: Sourced lib leaves its function undefined

- **WHEN** a guarded source succeeds in status terms but the lib did not finish defining the function the caller needs
- **THEN** the caller takes its fallback branch instead of invoking the undefined function

#### Scenario: A command inside the sourced lib fails

- **WHEN** a sourced lib runs a failing command mid-source rather than returning non-zero
- **THEN** the hook still exits early — a known residual gap that this requirement does NOT close, recorded so a green lint is not mistaken for full coverage

### Requirement: The repo MUST deterministically reject any new unguarded source in a fail-open hook

A test SHALL enumerate every `hooks/*.sh` carrying an ERR trap, classify each source line, and fail on any unguarded line that is not covered by an explicit allowlist. Pre-existing violations MAY be allowlisted, but the allowlist MUST be keyed by the source line's own text rather than by line number, since line numbers drift with unrelated edits and a number-keyed exemption silently stops describing what it exempted. `hooks/openspec-guard.sh` MUST NOT be allowlistable, because its early exit is a silent push-gate allow.

#### Scenario: A new unguarded source is added

- **WHEN** a hook carrying an ERR trap gains a bare `. lib` line that is not in the allowlist
- **THEN** the test fails and names the offending file and source line

#### Scenario: An allowlisted line is fixed

- **WHEN** a previously allowlisted source line is guarded, moved, or deleted so that it no longer matches a violation
- **THEN** the test fails until the stale allowlist entry is removed, so a fixed line cannot leave a standing exemption behind

### Requirement: The lint MUST be pinned by fixtures that prove it can still detect the defect

The repository SHALL commit a red fixture — a hook with an ERR trap and an unguarded source of a lib that returns non-zero mid-source — and a green fixture that guards the same source. The lint MUST flag the red fixture and MUST NOT flag the green one. Because both fixtures exit 0, assertions on their behaviour MUST key on whether the hook reached its decision point, never on the exit code.

#### Scenario: Red fixture executed

- **WHEN** the red fixture is run
- **THEN** it exits 0 without reaching its deny decision, demonstrating the silent early exit that the exit code alone cannot reveal

#### Scenario: Green fixture executed

- **WHEN** the green fixture is run with the same failing lib
- **THEN** it reaches and prints its deny decision
