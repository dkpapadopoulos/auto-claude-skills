# security-scanner delta: the gitleaks report reaches the agent

## MODIFIED Requirements

### Requirement: Hybrid deterministic scanning
The security-scanner skill MUST orchestrate CLI tools (Semgrep, Trivy, Gitleaks) via Bash and parse their structured JSON output for the agent to act on.

#### Scenario: Semgrep SAST scan on changed files
Given semgrep is installed
When the agent invokes the security-scanner skill during REVIEW
Then it runs semgrep with `--json --config auto` on branch-changed files via `git diff --name-only -z`
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
And an empty result is not read as a pass; only an explicit `count: 0` is, and it covers committed history only
