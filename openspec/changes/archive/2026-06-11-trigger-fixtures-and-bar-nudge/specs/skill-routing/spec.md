# skill-routing — delta spec: trigger-fixtures-and-bar-nudge

## ADDED Requirements

### Requirement: Adversarial trigger-regex fixture coverage for collision-prone skills

Each collision-prone trigger-bearing skill (`incident-analysis`, `brainstorming`, `requesting-code-review`, `supply-chain-investigation`, `verification-before-completion`, `outcome-review`) MUST have a fixture file at `tests/fixtures/routing/<skill>.txt` containing at least 4 `MATCH:` and at least 2 `NO_MATCH:` directives. (The debate's original shortlist named `security-scanner` and `finishing-a-development-branch`; both are composition-routed with no trigger regexes, so regex fixtures are meaningless for them — they were substituted by their collision counterparts `verification-before-completion` and `outcome-review`.) Every `NO_MATCH:` prompt MUST be a near-miss: it contains at least one token adjacent to the skill's trigger alternation that the regex is required to reject. Fixtures MUST be validated by the existing `tests/test-regex-fixtures.sh` harness against the live `config/default-triggers.json`; the harness MUST NOT be duplicated. Skills without trigger regexes MUST NOT have fixture files.

#### Scenario: Near-miss prompt does not fire an adjacent skill

- GIVEN the `supply-chain-investigation` fixture file contains `NO_MATCH: upgrade the lodash dependency to the latest version`
- WHEN `tests/test-regex-fixtures.sh` runs
- THEN no `supply-chain-investigation` trigger regex matches the prompt
- AND the suite fails loudly if a future trigger edit makes it match

#### Scenario: Trigger drift in default-triggers.json is caught before merge

- GIVEN a fixture file with passing `MATCH:` directives for a skill
- WHEN a trigger regex for that skill is edited in `config/default-triggers.json` such that a `MATCH:` prompt no longer matches
- THEN `bash tests/run-tests.sh` reports the fixture failure (the harness is glob-discovered; no wiring step exists or is required)

### Requirement: Word-boundary anchoring for substring-prone trigger words

Bare short-word trigger alternatives that match inside common English words MUST carry word-boundary anchors. Leading-only anchoring (`(^|[^a-z])word`) is the default — it blocks prefix contamination while preserving suffix inflections; both-side anchoring is used only where the word is itself a prefix of a contaminating word (`mass` → "massive"). The anchored set, discovered via fixture authoring and a systematic sibling scan: `review` (requesting-code-review, agent-team-review, pr-review hint — blocks "preview"), `ship`/`tag`/`merge`/`release`/`ready.to`/`complete`/`finish` (verification-before-completion — blocks "relationship", "staging"/"untagged", "emerged"/"emergency", "prerelease", "already too", "incomplete", "unfinished"), `hang` (systematic-debugging — blocks "change"/"changelog"/"exchange"), `nits?` (receiving-code-review — blocks "unit"/"initialize"/"monitoring"/"definition"), `as.?built` (openspec-ship — blocks "was built"/"has built"), `set.?up` (brainstorming — blocks "asset upload"/"offset update"), `mass` both-side (batch-scripting — blocks "massive"), `continue` (executing-plans — blocks "discontinued"), `release` (deploy-gate — blocks "prerelease"), `merge` (github-mcp hint — blocks "emergency"). All anchored triggers MUST be identical in `config/default-triggers.json` and `config/fallback-registry.json` (fallback-drift gate). Every anchored skill trigger MUST be pinned by fixture regressions in `tests/fixtures/routing/` (the two hint anchors are structurally untestable by the harness, which reads `.skills[]` only). Genuine uses MUST keep matching (verified inflections include "re-review", "we shipped", "tagged", "merged", "completed", "finished", "hangs", "nitpicks", "as-built", "setup", "continue", "released").

#### Scenario: Embedded substring does not fire a process or workflow skill

- GIVEN the prompt "preview the deployment in staging"
- WHEN trigger scoring runs
- THEN `requesting-code-review` does not trigger
- AND given the prompt "the relationship between hooks and registry is unclear", `verification-before-completion` does not trigger

#### Scenario: Leading-boundary anchors preserve genuine matches

- GIVEN the prompts "please re-review the fix", "we shipped the fix", and "tag the release and publish the plugin"
- WHEN trigger scoring runs
- THEN `requesting-code-review` triggers on the first AND `verification-before-completion` triggers on the second and third

### Requirement: Informational measurable-bar advisory in PLAN-phase design-guard

When the PLAN-phase design-guard reads a readable design document, it MUST additionally grep the document body for numeric-threshold patterns (digits with unit or percent, `p50|p90|p95|p99`, `threshold`, or comparison operators). When no pattern is found, the guard MUST append exactly one informational `[i]` line suggesting a measurable bar. The line MUST NOT affect the design-completeness verdict, MUST NOT render as `[X]`, and MUST NOT block any transition. All failure modes (unreadable file, grep error, missing state) MUST fail open. `SKILL_EXPLAIN=1` SHOULD emit a `[design-guard] bar=<0|1>` breadcrumb to stderr.

#### Scenario: Design doc without numeric bar gets the [i] line only

- GIVEN an active change whose `design_path` points to a readable design doc containing all three required headings but no numeric-threshold pattern
- WHEN the activation hook runs in PLAN phase
- THEN the DESIGN COMPLETENESS output reports all sections present AND includes one `[i]` measurable-bar line
- AND the hook exits 0 with no blocking action

#### Scenario: Organically numeric design doc stays quiet

- GIVEN a design doc containing `p95 < 200ms` or `>= 80%` in its body
- WHEN the activation hook runs in PLAN phase
- THEN no `[i]` measurable-bar line appears in the output

#### Scenario: Grep failure cannot block the hook

- GIVEN the numeric-bar grep errors for any reason
- WHEN the activation hook runs in PLAN phase
- THEN the completeness verdict is unchanged, the worst-case effect is the advisory `[i]` line appearing, AND the hook exits 0
