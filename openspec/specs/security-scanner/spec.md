# Security Scanner

## Purpose

Deterministic code-security review via Semgrep (SAST), Trivy (dependencies), and Gitleaks (secrets). Produces JSON-structured findings, degrades gracefully when tools are missing, and drives a self-healing fix-rescan loop during REVIEW.
## Requirements
### Requirement: Hybrid deterministic scanning
The security-scanner skill MUST orchestrate CLI tools (Semgrep, Trivy, Gitleaks) via Bash and parse their structured JSON output for the agent to act on.

#### Scenario: Semgrep SAST scan on changed files
Given semgrep is installed
When the agent invokes the security-scanner skill during REVIEW
Then it runs semgrep with `--json --config auto` on the files the branch changed and did not delete, via `git diff --name-only -z --diff-filter=d` from a merge base resolved once, and stops with a message when no such file is left
And with no `main` branch, or no merge base with it, it reports "could not check", never that nothing was left to scan
And on a branch that deletes one file and adds a detectable finding, the parsed count is greater than zero
And the parsed output includes the number of files scanned, the messages of `level: error` entries as errors, and the files with any other entry (syntax error, partial parse, timeout) as not fully parsed
And `count: 0` is read as a pass only when there are no errors and at least one file was scanned; empty output, an error or zero files scanned is "could not check"
And that pass covers only the files not listed as not fully parsed; the agent reviews each listed file itself and reports it as not checked by the scanner
And presents findings as a structured table with severity, file, line, rule, and message

#### Scenario: Trivy dependency scan
Given trivy is installed
When the agent invokes the security-scanner skill during REVIEW
Then it runs trivy fs with `--format json --severity HIGH,CRITICAL`
And presents vulnerabilities with package name, installed version, fixed version, CVE, and title

#### Scenario: Gitleaks secret detection without leaking secrets
Given gitleaks is installed
When the agent invokes the security-scanner skill
Then it runs gitleaks detect with `--report-format json --report-path <temp file> --redact` and parses that file, a form that works on every gitleaks v8 release
And on a repository holding a detectable secret in committed history the parsed count is greater than zero
And output includes RuleID, File, StartLine, and Description but NOT the Match content
And `count: 0` is read as a pass only when gitleaks logged at least one commit scanned and no error; an empty result, zero commits scanned or an error is "could not check"
And that scan covers committed history only; uncommitted changes are scanned with `gitleaks protect` (staged and unstaged), never by committing them first
And because `protect` always logs zero commits scanned, its `count: 0` is a pass when it logged no error

### Requirement: Graceful degradation
The skill MUST adapt to available tools without failing.

#### Scenario: No tools installed
Given neither semgrep nor trivy nor gitleaks is installed
When the agent invokes the security-scanner skill
Then it falls back to LLM-only review and recommends installation commands

#### Scenario: Partial tools
Given only semgrep is installed (trivy and gitleaks are not)
When the agent invokes the security-scanner skill
Then it runs semgrep scan and notes that dependency and secret scanning are unavailable

### Requirement: Self-healing fix loop
The agent MUST fix critical/high findings and re-scan to verify.

#### Scenario: Fix and verify
Given semgrep finds a SQL injection vulnerability
When the agent fixes the code
Then it re-runs semgrep on the changed file to verify the fix
And reports the fix in the final summary

#### Scenario: Loop cap
Given multiple findings exist
When the agent enters the fix-rescan loop
Then it performs at most 3 iterations to prevent infinite loops

### Requirement: Session-start capability detection
The session-start hook MUST detect and report available security tools.

#### Scenario: Tools detected at session start
Given the session-start hook runs
When semgrep and gitleaks are installed but trivy is not
Then additionalContext includes "Security tools: semgrep=true, trivy=false, bandit=false, gitleaks=true"

### Requirement: REVIEW phase routing
The security-scanner MUST activate via REVIEW composition, not trigger scoring.

#### Scenario: Composition-only activation
Given the REVIEW phase composition in default-triggers.json
When the agent enters REVIEW phase
Then it fires Skill(auto-claude-skills:security-scanner) with "when": "always"

#### Scenario: Methodology hint reinforcement
Given a prompt containing "security scan" during REVIEW phase
When the activation hook processes methodology hints
Then the deterministic-security-scan hint fires with Skill(auto-claude-skills:security-scanner) reference

### Requirement: Preferred SAST binary detection
The security-scanner skill MUST detect `opengrep` first and fall back to `semgrep` when opengrep is absent. The detected binary MUST be used for all SAST scan invocations.

#### Scenario: Opengrep preferred when both installed
- **GIVEN** both `opengrep` and `semgrep` are on PATH
- **WHEN** the agent invokes the security-scanner skill during REVIEW
- **THEN** the resolved `$SAST_BIN` MUST point to the `opengrep` binary
- **AND** Step 2 invocations MUST use `"$SAST_BIN"` rather than a hardcoded binary name

#### Scenario: Semgrep fallback when opengrep absent
- **GIVEN** `semgrep` is on PATH but `opengrep` is not
- **WHEN** the agent invokes the security-scanner skill during REVIEW
- **THEN** the resolved `$SAST_BIN` MUST point to the `semgrep` binary
- **AND** the skill MUST proceed without warning the user about the absence of opengrep

#### Scenario: Graceful degradation with neither
- **GIVEN** neither `opengrep` nor `semgrep` is on PATH
- **WHEN** the agent invokes the security-scanner skill
- **THEN** `$SAST_BIN` MUST resolve to an empty string
- **AND** the skill MUST fall back to LLM-only review and recommend installing opengrep first, semgrep as fallback

### Requirement: JSON contract preservation across SAST binaries
The security-scanner skill SHALL parse SAST JSON output using only fields that are byte-identical between opengrep and semgrep: `results[].check_id`, `results[].extra.severity`, `results[].path`, `results[].start.line`, and `results[].extra.message`.

#### Scenario: Byte-identical jq output on a fixture
- **GIVEN** a fixture file with a known Python code-execution-sink finding
- **WHEN** the skill's jq pipeline runs against both `opengrep scan --json --config auto` and `semgrep scan --json --config auto` output
- **THEN** the parsed `{rule, severity, file, line, message}` records MUST be identical

#### Scenario: Same registry for --config auto
- **GIVEN** both binaries are invoked with `--config auto`
- **WHEN** they fetch the rule registry
- **THEN** they MUST resolve to the same `semgrep.dev/c/auto` endpoint

### Requirement: Capability detection emits opengrep field
The session-start hook MUST detect `opengrep` availability and include an `opengrep=` field in the `SECURITY_CAPS` line. The existing `semgrep=`, `trivy=`, and `gitleaks=` fields MUST remain emitted to preserve backwards compatibility.

#### Scenario: Both SAST binaries detected
- **GIVEN** both `opengrep` and `semgrep` are installed at session start
- **WHEN** the session-start hook runs
- **THEN** the `Security tools:` line MUST contain both `semgrep=true` and `opengrep=true`

#### Scenario: Only opengrep detected
- **GIVEN** `opengrep` is installed but `semgrep` is not
- **WHEN** the session-start hook runs
- **THEN** the `Security tools:` line MUST contain `semgrep=false, opengrep=true`

### Requirement: Routing trigger and hint copy include opengrep
The `deterministic-security-scan` methodology hint MUST trigger on prompts mentioning `opengrep` in addition to existing keywords, and the hint and purpose copy MUST reference opengrep alongside semgrep and trivy. Both `config/default-triggers.json` and `config/fallback-registry.json` MUST be updated identically.

#### Scenario: Prompt mentioning opengrep activates the hint
- **GIVEN** a prompt containing the word `opengrep` during REVIEW phase
- **WHEN** the activation hook processes methodology hints
- **THEN** the `deterministic-security-scan` hint MUST fire

#### Scenario: Config parity preserved
- **GIVEN** the security-scan trigger regex and hint/purpose copy in both config files
- **WHEN** `test_fallback_registry_parity` runs
- **THEN** the assertion MUST pass — both files contain the same `opengrep`-aware copy

