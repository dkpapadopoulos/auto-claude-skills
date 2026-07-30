# Spec delta: pdlc-safety — outbound publication leak gate

## ADDED Requirements

### Requirement: Private memory text MUST NOT reach a published body

A PreToolUse gate MUST evaluate every Bash command that invokes
`gh issue create|comment|edit`, `gh pr create|comment|edit`, or a `gh api`
POST/PATCH (or field-bearing, method-omitted) call against an issue/PR
endpoint (`*/issues`, `*/issues/*`, `*/pulls`, `*/pulls/*`; `*/pulls/*/merge`
is excluded — it publishes no body). The body is resolved from
`--body-file`/`-F` (issue/pr) or `--input`/`-f|-F|--field|--raw-field
name=@<path>` (`gh api`) when present as a FILE path, and otherwise from the
whole command string, which conservatively covers any inline `--body`/`-b`/`-f`
value without parsing it.

The gate MUST emit `permissionDecision: deny` when the body contains a run of 16
or more consecutive normalized words that appears in the local memory corpus and
does NOT appear in the repository's tracked content at HEAD. Normalization is
lowercasing with every non-alphanumeric byte mapped to a space.

The memory corpus is every `*.md` file in the resolved memory directory,
including `MEMORY.md`.

Shingles MUST be built per memory file, with the word buffer reset at each file
boundary; a run formed by concatenating the tail of one file with the head of
another MUST NOT match.

The deny message MUST name the source as `memory/<file>.md:<line>` and MUST NOT
reproduce the matched text.

Detection MUST be fail-closed: a match always denies. Inability to evaluate
(absent memory corpus, missing `jq`, unreadable body) MUST allow, and MUST state
that the check did not run. The gate MUST NOT alter the decision of any other
outbound gate, and MUST NOT be implemented inside `hooks/openspec-guard.sh`.

#### Scenario: verbatim private memory text in an issue body is denied

- **GIVEN** a memory corpus containing a 16-word run absent from tracked repo
  content, and a body file reproducing that run verbatim
- **WHEN** the model runs `gh issue create --body-file <body>`
- **THEN** the gate MUST emit `permissionDecision: deny` naming
  `memory/<file>.md:<line>`, and the message MUST NOT contain the matched text

#### Scenario: a path:line citation of the same fact is allowed

- **GIVEN** the same corpus and a body citing `memory/<file>.md:9` with no
  verbatim run
- **WHEN** the model runs `gh issue create --body-file <body>`
- **THEN** the gate MUST produce no output and exit 0

#### Scenario: text present in tracked repo content is not a leak

- **GIVEN** a 16-word run present in both the memory corpus and a tracked repo
  file at HEAD
- **WHEN** a body reproduces that run
- **THEN** the gate MUST allow

#### Scenario: a run spanning two memory files does not match

- **GIVEN** a body whose 16-word run exists only as the tail of one memory file
  followed by the head of the next
- **WHEN** the body is evaluated
- **THEN** the gate MUST allow

#### Scenario: the push gate is unperturbed

- **GIVEN** a `git push` command
- **WHEN** the publication gate receives it
- **THEN** it MUST produce no output and exit 0

#### Scenario: absent corpus allows and announces

- **GIVEN** no memory directory for the current repository
- **WHEN** a publish command is evaluated
- **THEN** the gate MUST allow and MUST state that it could not check
