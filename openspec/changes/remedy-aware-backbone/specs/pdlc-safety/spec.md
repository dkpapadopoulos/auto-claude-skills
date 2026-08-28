# Spec Delta: pdlc-safety — heredoc-aware classification and achievable remedies

The push-gate command classifier MUST treat heredoc bodies as data, not command text, except where the body is fed to a shell interpreter. Gate deny messages MUST NOT name a remedy that cannot be executed in the current install.

## Acceptance Scenarios

### Scenario 1: Documentation write with pushy prose is not a push

- GIVEN a Bash command `cat > notes.md <<'EOF'` whose heredoc body contains the line `git push origin main` and a terminating `EOF` line
- WHEN the push gate classifies the command
- THEN `command_invokes_git_write` MUST return non-match, `command_git_mutate_before_push` MUST return non-match, and the parse MUST be reported balanced

### Scenario 2: Plan heredoc followed by a real push is a push, not a mutate-then-push

- GIVEN a command that writes a plan file via heredoc whose body contains ` ```bash `, `git add -A`, and `git commit -m x` lines, followed after the terminator by a real `git push` segment
- WHEN the push gate classifies the command
- THEN `command_invokes_git_write` MUST match (the trailing push is real) AND `command_git_mutate_before_push` MUST NOT match (the fenced body lines are data)

### Scenario 3: Executable heredoc bodies never lose a push

- GIVEN the command `bash <<EOF` with body line `git push origin main` and terminator `EOF`
- WHEN the push gate classifies the command
- THEN the embedded push MUST remain detectable — for known shell interpreters the body scans as code and `command_invokes_git_write` MUST match; for owners the scanner cannot classify (e.g. `ssh host <<EOF`, `python3 - <<PY`) the parse MUST NOT report balanced, retaining the fail-closed substring path

### Scenario 4: REVIEW/VERIFY deny remedies are achievable

- GIVEN a session in which the registry marks `requesting-code-review` and `verification-before-completion` unavailable (superpowers not installed) and the availability flag has been persisted
- WHEN a `git push` would otherwise be denied by the REVIEW or VERIFY leg
- THEN the guard MUST NOT emit `permissionDecision: deny` for those legs and MUST emit advisory text whose remedy is installing the backbone (run /setup); AND when the availability flag is absent or the skills are available, the deny behavior MUST be byte-identical to the pre-change guard
