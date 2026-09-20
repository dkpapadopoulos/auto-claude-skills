# design-foundations

## ADDED Requirements

### Requirement: Shipped design seed

The plugin SHALL ship a design seed under `assets/design-seed/` containing a
token set with semantic roles, a styleguide limited to rules a lint cannot
express, one dependency-free reference page, and an executable lint. `tokens.css`
SHALL be the source of truth and `tokens.json` SHALL hold exactly the same token
names and values. The seed SHALL be copied into a target project, which then
owns it; the plugin SHALL NOT read, rewrite, or silently upgrade a copied seed.
The reference page MUST NOT depend on any package manager, build step, or
framework.

#### Scenario: Token definitions cannot drift between formats

- **GIVEN** the shipped `assets/design-seed/`
- **WHEN** the token names and values in `tokens.css` and `tokens.json` are
  compared
- **THEN** the two sets MUST be identical, with no token present in one and
  absent from the other

#### Scenario: Seed carries no framework dependency

- **GIVEN** the shipped `assets/design-seed/` tree
- **WHEN** its contents are inspected
- **THEN** there MUST be no `package.json`, lockfile, build config, or remote
  script/style reference in the reference page

#### Scenario: Reference page shows the states that are hard to get right

- **GIVEN** `assets/design-seed/reference.html`
- **WHEN** it is inspected
- **THEN** it MUST demonstrate dense numeric display, a missing value rendered
  distinctly from an empty set, every status treatment the tokens define, and
  both light and dark themes

### Requirement: Token lint enforces references over a declared scope

The seed SHALL provide a lint that requires token references (`var(--token)`)
for the CSS properties it declares it covers, over an explicitly declared file
set. It SHALL state that scope in `--help` and in the styleguide, and SHALL NOT
claim general enforcement. Each diagnostic MUST carry a stable `TL-<n>` class.
A raw literal in a covered property MUST fail **even when its value equals a
token's value**, because a literal does not follow a theme change.

#### Scenario: A literal matching a token value is still a violation

- **GIVEN** a stylesheet in the declared file set setting a covered property to
  a raw literal whose value is exactly a token's value
- **WHEN** `token-lint.sh` runs
- **THEN** it MUST exit non-zero and report the file, the line, and a `TL-<n>`
  class

#### Scenario: Declared exceptions do not fire

- **GIVEN** a stylesheet whose only literals appear in comments, media-query
  conditions, `calc()` operands, or properties outside the declared coverage
- **WHEN** `token-lint.sh` runs
- **THEN** it MUST exit zero

### Requirement: Adoption records provenance and makes the guide reachable

Adoption SHALL record the preset name and version in the target project, and
SHALL add a pointer to the project's own agent instructions directing
implementation to the styleguide and the lint. The plugin SHALL NOT treat an
unmodified seed as a defect, and SHALL NOT ship a check that fails on one.

#### Scenario: Adopting the default unchanged is a supported outcome

- **GIVEN** a project that copied the seed and changed no token
- **WHEN** its `design/` directory and its checks are run and inspected
- **THEN** every check MUST exit zero, and `design/adopted.json` MUST record the
  preset name and version

### Requirement: Design method reachable without a design-project connector

The plugin SHALL document a design method whose primary lane requires no
external design-system connector, and SHALL surface it during the DESIGN phase
through a composition hint rather than a trigger-matched skill.

#### Scenario: DESIGN hint renders without adding a routed skill

- **GIVEN** the routing registry built from `config/default-triggers.json`
- **WHEN** a DESIGN-phase prompt is scored
- **THEN** the design-seed hint MUST be present in the DESIGN composition, and
  the registry MUST contain no skill entry whose triggers were added by this
  change

### Requirement: Comparative claims are evidenced by a controlled comparison

The plugin SHALL NOT claim that the design seed improves implementation output
unless that claim is supported by a comparison against a no-seed arm run under
an identical brief, fixture, model, tool access and budget. The protocol and
the scoring rubric SHALL be committed before either arm runs, and the rubric
SHALL NOT score resemblance to the seed, token usage, or the presence of a
design system. Process compliance SHALL be assessed separately from output
quality. Where only one arm was run, the result MAY be reported as feasibility
evidence and MUST NOT be reported as evidence of improvement.

#### Scenario: A single-arm pilot does not license a comparative claim

- **GIVEN** a completed pilot in which only the seeded arm was run
- **WHEN** its result is written up
- **THEN** the write-up MUST describe it as feasibility evidence, and MUST NOT
  state or imply that the seed produced a better result than its absence would
  have

#### Scenario: The rubric cannot reward looking like the seed

- **GIVEN** the committed scoring rubric
- **WHEN** its dimensions are inspected
- **THEN** none MUST score resemblance to the shipped seed, token usage, or the
  presence of a design system, and every dimension MUST cite a source that
  predates the seed or is independent of it

#### Scenario: Disagreeing judges yield an inconclusive result, not a tiebreak

- **GIVEN** two blinded judge responses that favour different arms
- **WHEN** the verdict is resolved
- **THEN** the recorded outcome MUST be judge-sensitive/inconclusive, and no
  additional judge call MUST be made to break the tie

#### Scenario: The fixture preserves the gaps the screen is meant to discover

- **GIVEN** the frozen report fixture used by both arms
- **WHEN** it is compared against the in-memory report structure
- **THEN** it MUST have been produced through the store-then-retrieve path, and
  fields that the persistence path drops MUST be absent from it

### Requirement: A pilot artifact's designated data block carries only fixture data

The title names the data block, not the artifact, because that is what the
check covers. An artifact produced by a pilot arm SHALL be refused for outbound
transmission unless the data embedded in its designated `id="dion-report"`
block hash-matches the frozen fixture bytes. The check SHALL be mechanical and
SHALL NOT depend on human inspection of the artifact. It SHALL NOT be described
as validating the artifact as a whole: data rendered into the visible HTML body
is outside its scope, and that residual is carried by the capability boundary
below plus the human preview.

#### Scenario: An artifact whose designated data block carries non-fixture data is refused

- **GIVEN** a generated artifact whose `id="dion-report"` block differs from the
  frozen fixture bytes
- **WHEN** it is submitted for outbound transmission
- **THEN** the transmission MUST be refused, and the refusal MUST NOT require a
  human to notice the difference

### Requirement: Pilot arms are denied the named outbound tools and the sensitive paths

The previous wording — "Pilot arms SHALL have no outbound transmission
capability of their own" — was not enforceable and was not true: an arm runs with
unrestricted tool access and no dispatch mechanism here exposes a tool-restriction
parameter. What is enforceable is stated instead.

Arms SHALL be dispatched as headless sessions rooted in their own worktree, NOT as
subagents of an orchestrating session. This is a capability requirement, not a
preference: measured before launch, the deny rule below is **inert** for a subagent,
because the worktree's `.claude/settings.json` — which registers it — is never loaded
for an agent belonging to another session, and the rule's own arm-identification reads
a project directory the harness does not set for one. A subagent dispatch therefore
satisfies the letter of this requirement while enforcing nothing.

Pilot arms SHALL be denied, by a `PreToolUse` deny rule, the named non-Bash
outbound tools (`WebFetch`, `WebSearch`, and the whole `mcp__` tool namespace),
matched on tool name so that the rule is complete by construction for the tools
it names. Pilot arms SHALL additionally be denied reads of an enumerated set of
sensitive paths — `~/.config/gh/hosts.yml`, `~/.ssh`, `~/.claude.json`, and
`~/.claude/projects/*/memory/` — across every path-bearing tool, the set being
finite and therefore soundly enumerable. The residual Bash-level network
capability SHALL be stated in the design record rather than claimed absent.

#### Scenario: A named outbound tool and a sensitive read are both refused

- **GIVEN** a pilot arm running as a headless session in its own worktree, under
  the pilot's deny rule
- **WHEN** it invokes `WebFetch`, any `mcp__` tool, or a read of an enumerated
  sensitive path
- **THEN** the call MUST be refused, the refusal MUST be observable as coming
  from that rule rather than from an unrelated failure, and the arm's ordinary
  file and shell tools MUST remain usable
