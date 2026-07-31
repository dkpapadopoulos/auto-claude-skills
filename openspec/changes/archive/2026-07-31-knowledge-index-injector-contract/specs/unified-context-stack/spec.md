# Delta: unified-context-stack — knowledge index validated against the injector's contract

## ADDED Requirements

### Requirement: The knowledge bundle validator enforces the session-start injector's index contract

`scripts/knowledge-validate.sh` MUST reject a knowledge bundle in which any fact file lacks an index entry that the session-start hook would actually inject, rather than accepting any occurrence of the slug anywhere in `index.md`. The validator SHALL apply the injector's own line predicate to `index.md` first and then search only the surviving lines for the fact's `(slug.md)` reference, so the property asserted by the gate is the property the consumer enforces.

The error message SHALL name the required bullet shape and point at `scripts/knowledge-rebuild-index.sh`, so a failure is actionable without reading the hook.

This requirement MUST NOT be generalised to `scripts/memory-validate.sh`. Claude Code auto-memory has no injector owned by this project, so there is no consumer predicate to align to and tightening it would invent a contract rather than enforce one.

#### Scenario: an index entry the injector would drop fails validation

- **WHEN** `index.md` references a fact only on a line the injector's predicate does not match, such as a bold-wrapped `- **[Title](slug.md)**`, an indented sub-bullet, or a numbered item
- **THEN** `knowledge-validate.sh` exits non-zero and names the offending slug

#### Scenario: a conformant bundle still passes

- **WHEN** every fact is referenced by a line-anchored `- [Title](slug.md) — desc` bullet as emitted by `knowledge-rebuild-index.sh`
- **THEN** `knowledge-validate.sh` exits zero, and slugs that are substrings of other slugs do not match each other

### Requirement: The validator's and the injector's index predicates are pinned to each other by test

`tests/test-knowledge.sh` MUST extract the index-line predicate literal from both `hooks/session-start-hook.sh` and `scripts/knowledge-validate.sh` and assert the two are byte-identical, because the literal is necessarily written in both files and either side could otherwise drift silently. A test that only demonstrates one non-injectable example is insufficient: a later loosening of the hook's predicate would make the validator stricter than the injector and false-block legitimate bundles while every example-based assertion stayed green.

The extraction MUST fail loudly when it yields an empty pattern, so a change to either file's shape surfaces as a failure rather than as a vacuous comparison.

#### Scenario: the hook's predicate is loosened but the validator is not

- **WHEN** the injection predicate in `hooks/session-start-hook.sh` is changed and `scripts/knowledge-validate.sh` is left untouched
- **THEN** the equality assertion fails

#### Scenario: the predicate cannot be extracted

- **WHEN** either file no longer matches the extraction anchor and the recovered pattern is empty
- **THEN** the test records an explicit failure rather than comparing two empty strings
