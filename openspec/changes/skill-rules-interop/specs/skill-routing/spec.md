# skill-routing (delta)

## ADDED Requirements

### Requirement: skill-rules.json Trigger Derivation

The session-start registry builder MUST derive routing triggers from a
discovered plugin's `skill-rules.json` when the corresponding SKILL.md
frontmatter supplies no `triggers`. `promptTriggers.keywords` MUST be translated
to word-boundary ERE regexes and `promptTriggers.intentPatterns` MUST be passed
through only when ERE-valid. All failure paths MUST fail open (the skill keeps
empty triggers; the hook never aborts).

#### Scenario: Keyword translated to word-boundary regex
- **WHEN** a discovered plugin skill has no frontmatter `triggers` and its
  `skill-rules.json` lists the keyword `branch`
- **THEN** the built registry entry for that skill MUST contain a trigger
  `(^|[^a-z0-9])branch($|[^a-z0-9])`

#### Scenario: Keyword lowercased and metacharacters escaped
- **WHEN** the keyword is `values.yaml` or an acronym such as `PR`
- **THEN** the generated trigger MUST be lowercased and MUST escape ERE
  metacharacters (e.g. `values\.yaml`), so it matches the lowercased prompt at a
  word boundary and not as a mid-word substring

#### Scenario: PCRE-only intentPattern dropped with logged count
- **WHEN** an `intentPatterns` entry uses a PCRE-only construct such as `.*?` or
  `(?!...)`
- **THEN** that pattern MUST NOT appear in the skill's triggers **AND** the
  builder MUST log the dropped count to stderr (never to stdout)

#### Scenario: ERE-valid intentPattern preserved
- **WHEN** an `intentPatterns` entry is a valid ERE (e.g. `(create|start).*(branch|feature)`)
- **THEN** that pattern MUST appear verbatim in the skill's triggers

#### Scenario: Frontmatter triggers take precedence
- **WHEN** a discovered skill has both SKILL.md frontmatter `triggers` and a
  `skill-rules.json` entry
- **THEN** the frontmatter triggers MUST be used and the `skill-rules.json`
  entry MUST be ignored for that skill

#### Scenario: Malformed skill-rules.json fails open
- **WHEN** a plugin's `skill-rules.json` is missing, empty, or not valid JSON
- **THEN** the affected skill MUST keep empty triggers and the registry build
  MUST complete normally (fail-open, no abort)
