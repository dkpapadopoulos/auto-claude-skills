## MODIFIED Requirements

### Requirement: Heredoc-aware push-gate classification

The push-gate command classifier MUST treat heredoc bodies as data, not command
text, except where the body is fed to a shell interpreter (in which case it MUST
be scanned as code) or to an owner the scanner cannot classify (in which case the
parse MUST be reported unbalanced so callers fall back to the fail-closed
substring path). Arithmetic contexts MUST NOT be misread as heredoc operators.

#### Scenario: Documentation write with pushy prose is not a push
- **WHEN** the command `cat > notes.md <<'EOF'` has a heredoc body containing `git push origin main` and a terminating `EOF`
- **THEN** `command_invokes_git_write` MUST return non-match
- **AND** `command_git_mutate_before_push` MUST return non-match
- **AND** the parse MUST be reported balanced

#### Scenario: Plan heredoc followed by a real push is a push, not a mutate-then-push
- **WHEN** a command writes a plan file via heredoc whose body contains fenced `git add -A` / `git commit -m x` lines, followed after the terminator by a real `git push`
- **THEN** `command_invokes_git_write` MUST match (the trailing push is real)
- **AND** `command_git_mutate_before_push` MUST NOT match (the fenced body lines are data)

#### Scenario: Executable heredoc bodies never lose a push
- **WHEN** the command is `bash <<EOF` with body line `git push origin main` and terminator `EOF`
- **THEN** the body MUST scan as code and `command_invokes_git_write` MUST match
- **AND** for an owner the scanner cannot classify (`ssh host <<EOF`, `python3 - <<PY`) the parse MUST NOT be reported balanced, retaining the fail-closed substring path

### Requirement: Deny remedies must be achievable without suppressing the deny

Gate deny messages MUST NOT name a remedy that cannot be executed in the current
install. The gate MUST NEVER be suppressed based on a skill-availability signal;
availability MUST be resolved from on-disk SKILL.md presence, never from the
agent-writable registry cache.

#### Scenario: Uninstalled backbone yields an achievable deny, not an allow
- **WHEN** a gating backbone skill is not installed (no SKILL.md on disk) and a `git push` or `gh pr merge` would be denied by the REVIEW or VERIFY leg
- **THEN** the guard MUST still emit `permissionDecision: deny`
- **AND** the deny message MUST include the achievable remedy `run /setup` instead of relying solely on "invoke Skill(superpowers:X)"

#### Scenario: A tampered registry cache cannot weaken the gate
- **WHEN** the backbone is present on disk but the registry cache is tampered to `available:false`
- **THEN** the decision MUST be unchanged (still deny) AND the message MUST NOT change (no cache-forge deny→allow lever)

#### Scenario: Installed backbone leaves the deny byte-identical
- **WHEN** the backbone IS installed and a REVIEW/VERIFY deny fires
- **THEN** the deny message MUST be byte-identical to the pre-change guard (no `/setup` clause)
