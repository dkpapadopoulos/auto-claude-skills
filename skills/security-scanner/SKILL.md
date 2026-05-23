---
name: security-scanner
description: Run Semgrep/Opengrep SAST and Trivy vulnerability scanning during code review with self-healing fix loop
---

# Security Scanner

Hybrid deterministic scanning: CLI tools find vulnerabilities, you fix them.

## When to Use

During REVIEW phase, after code changes are complete. Also invocable on explicit security requests.

## Step 1: Detect Available Tools

Pick the SAST binary (prefer opengrep, fall back to semgrep), then check the rest:

```bash
SAST_BIN="$(command -v opengrep || command -v semgrep || true)"
[ -n "$SAST_BIN" ] && echo "sast: $SAST_BIN" || echo "sast: not installed"
command -v trivy && echo "trivy: available" || echo "trivy: not installed"
command -v osv-scanner && echo "osv-scanner: available" || echo "osv-scanner: not installed (optional)"
command -v gitleaks && echo "gitleaks: available" || echo "gitleaks: not installed"
```

Why opengrep first: it's a fork of Semgrep v1.100.0 (LGPL 2.1) that produces byte-identical JSON for the fields this skill consumes (`check_id`, `extra.severity`, `path`, `start.line`, `extra.message`), uses the same `--config auto` registry (`semgrep.dev/c/auto`), honors `.semgrepignore`, and ships as a single signed binary with no Python dependency. It also returns real `extra.fingerprint` and `extra.lines` values that semgrep gates behind a login.

If **no SAST binary and no trivy** is installed, fall back to LLM-only code review and recommend installation:
- Opengrep (preferred): download the signed binary from https://github.com/opengrep/opengrep/releases or run the official install script
- Semgrep (fallback): `brew install semgrep` or `pip install semgrep`
- Trivy: `brew install trivy`
- Gitleaks: `brew install gitleaks`

## Step 2: Run SAST (Opengrep or Semgrep)

If a SAST binary is available, scan for code vulnerabilities. The `$SAST_BIN` var from Step 1 transparently uses opengrep when present, semgrep otherwise — flags and JSON shape are compatible.

**Important:** Each Bash invocation is a fresh shell. Resolve `SAST_BIN` at the top of every code block below — do not assume Step 1's resolution persists.

**Fast scan (changed files in current branch — prefer this for inner-loop reviews):**
```bash
SAST_BIN="$(command -v opengrep || command -v semgrep || true)"
[ -z "$SAST_BIN" ] && { echo "no SAST binary installed"; exit 0; }
git diff --name-only -z "$(git merge-base HEAD main)..HEAD" | xargs -0 "$SAST_BIN" scan --json --config auto --severity WARNING 2>/dev/null | jq '{count: (.results | length), results: [.results[] | {rule: .check_id, severity: .extra.severity, file: .path, line: .start.line, message: .extra.message}]}'
```

Note: If `merge-base` fails (no main branch), fall back to `git diff --name-only -z HEAD~1 | xargs -0 ...` for the last commit only.

**Full project scan (use for thorough reviews or when explicitly asked):**
```bash
SAST_BIN="$(command -v opengrep || command -v semgrep || true)"
[ -z "$SAST_BIN" ] && { echo "no SAST binary installed"; exit 0; }
"$SAST_BIN" scan --json --config auto --severity WARNING . 2>/dev/null | jq '{count: (.results | length), results: [.results[] | {rule: .check_id, severity: .extra.severity, file: .path, line: .start.line, message: .extra.message}]}'
```

**If output is large (count > 20), filter by severity first:**
```bash
SAST_BIN="$(command -v opengrep || command -v semgrep || true)"
[ -z "$SAST_BIN" ] && { echo "no SAST binary installed"; exit 0; }
"$SAST_BIN" scan --json --config auto --severity ERROR . 2>/dev/null | jq '.results[:20]'
```

## Step 3: Run Trivy (Dependency/CVE Scanning)

If trivy is available, scan for vulnerable dependencies and IaC misconfigurations.

**Dependency scan:**
```bash
trivy fs --scanners vuln,misconfig --format json --severity HIGH,CRITICAL --ignore-unfixed . 2>/dev/null | jq '{count: (.Results // [] | map(.Vulnerabilities // [] | length) | add // 0), results: [.Results // [] | .[].Vulnerabilities // [] | .[] | {pkg: .PkgName, installed: .InstalledVersion, fixed: .FixedVersion, severity: .Severity, cve: .VulnerabilityID, title: .Title}]}'
```

**If Dockerfile exists, also scan the image config:**
```bash
trivy config --format json --severity HIGH,CRITICAL . 2>/dev/null | jq '.Results // []'
```

## Step 3.5: Run OSV-Scanner (Registry-Native Advisories)

If `osv-scanner` is available, run a supplementary scan against [OSV.dev](https://osv.dev), which aggregates GHSA, PyPA, RustSec, Go vulnerability DB, and npm/Maven Central security advisories. OSV often surfaces registry-native advisories before they propagate to Trivy's NVD-anchored data.

**Detection:**
```bash
command -v osv-scanner >/dev/null 2>&1 && echo "osv-scanner: available" || echo "osv-scanner: not installed (optional)"
```

If not installed, document the install path and skip:

```bash
# macOS arm64
curl -L https://github.com/google/osv-scanner/releases/latest/download/osv-scanner_darwin_arm64 -o ~/.local/bin/osv-scanner
chmod +x ~/.local/bin/osv-scanner
```

(Ensure `~/.local/bin` is on your `PATH`, or use `/usr/local/bin/` instead.)

(Linux: replace `darwin_arm64` with `linux_amd64`. macOS Intel: `darwin_amd64`.)

**Scan (recursive directory mode):**

```bash
osv-scanner scan -r --format=json . 2>/dev/null | jq '{count: ([.results[]?.packages[]?.vulnerabilities[]?] | length), results: [.results[]?.packages[]? | {pkg: .package.name, ecosystem: .package.ecosystem, version: .package.version, vulns: [.vulnerabilities[]? | {id: .id, aliases: .aliases, severity: (.database_specific.severity // (.severity[0].score | if . != null then "cvss_vector:\(.)" else null end) // "unknown"), summary: .summary}]}]}'
```

**De-duplicate against Trivy results.** Cross-check the `aliases` field: if a finding's `id` or any alias matches a CVE/GHSA already reported by Trivy in Step 3, treat as duplicate and surface only once. Label OSV-only findings (no Trivy counterpart) under the "Registry-native advisories" subsection of the report.

If `osv-scanner` is not available, this step is skipped silently — no impact on Steps 4-6.

## Step 4: Run Gitleaks (Secret Detection)

If gitleaks is available, scan for hardcoded secrets.

```bash
gitleaks detect --source . --no-banner --report-format json 2>/dev/null | jq '{count: (. | length), results: [.[] | {rule: .RuleID, file: .File, line: .StartLine, description: .Description}]}'
```

## Step 5: Triage and Fix

Present findings as a structured table:

```markdown
## Security Scan Results

### SAST (Opengrep/Semgrep) — N findings
| Severity | File | Line | Rule | Message |
|----------|------|------|------|---------|

### Trivy (Dependencies) — N vulnerabilities
| Severity | Package | Installed | Fixed | CVE | Title |
|----------|---------|-----------|-------|-----|-------|

### OSV-Scanner (Registry-native advisories) — N findings
| Severity | Package | Ecosystem | Version | Advisory ID | Aliases | Summary |
|----------|---------|-----------|---------|-------------|---------|---------|

### Gitleaks (Secrets) — N findings
| Rule | File | Line | Description |
|------|------|------|-------------|
```

**Fix priority:** CRITICAL > HIGH > ERROR > WARNING

For each fixable finding:
1. Fix the issue using your normal editing tools
2. Re-run the specific scanner on the changed file to verify the fix
3. Move to the next finding

**Max 3 fix-rescan iterations** to prevent infinite loops.

## Step 6: Report

After fixing, present a final summary:
- Total findings by tool and severity
- What was fixed (with file:line references)
- What needs human review (and why — e.g., business logic dependency, false positive candidate)
- What was NOT scanned (tools not installed) with install recommendations

## Ignore Files

If false positives are found, help the user configure:
- `.semgrepignore` for Semgrep/Opengrep exclusions (both binaries honor the same filename)
- `.trivyignore` for Trivy exclusions
- `.gitleaksignore` for Gitleaks exclusions
