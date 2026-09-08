# Spec delta: pdlc-safety — redirection operands are not refspecs

## ADDED Requirements

### Requirement: The push subject parser MUST NOT read shell redirections as refspecs

A shell redirection operand MUST NOT be counted as a refspec, and MUST NOT
prevent a single-ref push from resolving its ref. This applies to both the
partial-subject predicate and the ref resolver.

A redirection MUST be recognised by its structure — an optional `&`, an optional
file-descriptor digit run, then `<` or `>` — and MUST NOT be recognised by an
enumeration of particular spellings. When the operand is a bare operator, the
following word is its target and MUST also be skipped.

A word whose first character is not part of that structure MUST NOT be treated as
a redirection, so a quoted ref name beginning with an operator character is still
a refspec.

#### Scenario: a single-ref push written with a redirection

- **GIVEN** a gated command `git push -u origin feat/x 2>&1 | tail -8`
- **WHEN** the push gate resolves the subject
- **THEN** the command is not reported as carrying more than one ref
- **AND** the resolved push ref is `feat/x`

#### Scenario: a genuinely multi-ref push is still reported

- **GIVEN** a gated command that names two refspecs, with a redirection appended
- **WHEN** the push gate resolves the subject
- **THEN** the command is still reported as carrying more than one ref

#### Scenario: a redirection target is not mistaken for a refspec

- **GIVEN** a gated command `git push origin main > next`
- **WHEN** the push gate resolves the subject
- **THEN** the resolved push ref is `main`
