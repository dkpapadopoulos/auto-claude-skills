# security-scanner delta: a SAST scan that covered nothing is not clean

## MODIFIED Requirements

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
