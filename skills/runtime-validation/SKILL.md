---
name: runtime-validation
description: Use when you need to prove a change actually works through its real interfaces — during REVIEW or on requests like validate the feature, does it work, run e2e, or smoke test — covering browser E2E, API smoke, CLI checks, and a11y audits with graceful tool-degradation
---

# Runtime Validation

Realistic-context validation orchestrator: detect available tools, derive scenarios from specs and eval packs, execute browser/API/CLI paths, report with evidence. Composes with `webapp-testing` when available.

## When to Use

During REVIEW phase, after code changes are complete. Also invocable on explicit validation requests (e.g., "validate the feature", "does it work", "try it out", "run e2e", "smoke test").

This skill proves the feature works in a realistic context — beyond "tests pass" to "the feature behaves correctly when exercised through its real interfaces."

## Step 1: Detect Available Tools

Run capability detection via Bash to determine what's available. Each path is independent — detect all three, then execute whichever paths have tools.

### Browser Path

```bash
# Playwright (preferred)
command -v npx && npx playwright --version 2>/dev/null && echo "playwright: available" || echo "playwright: not installed"

# Cypress (fallback)
if [ -f package.json ]; then
  jq -e '.dependencies.cypress // .devDependencies.cypress' package.json >/dev/null 2>&1 && echo "cypress: available" || echo "cypress: not detected"
fi

# axe-core (a11y overlay)
command -v axe && echo "axe: available" || {
  if [ -f package.json ]; then
    jq -e '.dependencies["@axe-core/cli"] // .devDependencies["@axe-core/cli"]' package.json >/dev/null 2>&1 && echo "axe: available via npx" || echo "axe: not detected"
  else
    echo "axe: not detected"
  fi
}

# webapp-testing companion skill — check cached skill registry (NOT session flags)
jq -r '.skills[] | select(.name == "webapp-testing" and .available == true) | .name' ~/.claude/.skill-registry-cache.json 2>/dev/null && echo "webapp-testing: available" || echo "webapp-testing: not available"
```

### API Path

```bash
# curl availability
command -v curl && echo "curl: available" || echo "curl: not installed"

# Probe common dev server ports
for port in 3000 5173 8000 8080; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://localhost:${port}/" 2>/dev/null)
  [ "$code" != "000" ] && echo "server: localhost:${port} (HTTP ${code})"
done

# OpenAPI spec files
for f in openapi.yaml openapi.json swagger.json swagger.yaml; do
  [ -f "$f" ] && echo "openapi: ${f}"
done
```

### CLI Path

```bash
# Check for built binary
for dir in ./dist ./build ./target ./bin; do
  [ -d "$dir" ] && find "$dir" -maxdepth 1 -type f -perm +111 2>/dev/null | head -5
done

# Check package.json bin field
if [ -f package.json ]; then
  jq -r '.bin // empty | if type == "string" then . else keys[] end' package.json 2>/dev/null
fi

# Check Makefile targets
[ -f Makefile ] && make -qp 2>/dev/null | awk -F: '/^[a-zA-Z0-9][^$#\/\t=]*:([^=]|$)/ {split($1,a," ");print a[1]}' | head -10
```

## Step 2: Derive Validation Scenarios

Three-tier scenario sourcing (highest fidelity first):

### Tier 1: Eval Packs

Check for committed eval packs:

```bash
ls tests/fixtures/evals/*.json 2>/dev/null
```

If eval packs exist, read them and filter scenarios by `path` field to match detected execution paths (browser, api, cli). Each scenario provides structured inputs and expected outputs.

### Tier 2: Intent Truth

If no eval packs or for additional coverage, derive scenarios from:
- OpenSpec specs (`openspec/changes/<feature>/specs/`, `openspec/specs/<capability>/spec.md`) — acceptance scenarios
- Plan artifacts (`docs/plans/*-plan.md`, `docs/plans/*-design.md`) — task descriptions with implicit validation criteria
- Legacy specs (`docs/superpowers/specs/*-design.md`) — if canonical paths empty

Extract acceptance criteria and transform them into executable scenarios with inputs and expected outcomes.

### Tier 3: Generic Smoke Tests

If neither eval packs nor Intent Truth are available, generate generic smoke checks per detected path:
- **Browser:** homepage loads (HTTP 200), no console errors, basic a11y pass (axe AA)
- **API:** health endpoint returns 200, documented endpoints respond with expected status codes
- **CLI:** `--help` exits 0, basic command produces non-empty output with expected shape

## Step 3: Execute Per-Path

Execute each detected path independently. Ad-hoc scripts go to `mktemp -d` (never the repo working tree). Screenshots and artifacts go to `tests/artifacts/validation/` (gitignored).

```bash
# Create artifact directory
mkdir -p tests/artifacts/validation/

# Create temp directory for ad-hoc scripts
VALIDATION_TMPDIR=$(mktemp -d)
```

### Browser Path

**When `webapp-testing` companion is available:** Delegate browser scenarios via `Skill(webapp-testing)`. Pass derived scenarios as context. The companion handles Playwright orchestration, screenshot capture, and browser lifecycle.

**When Playwright is available directly (no webapp-testing):**

```bash
# Run existing Playwright tests if present
npx playwright test --reporter=json 2>/dev/null | jq '{passed: .stats.expected, failed: .stats.unexpected, flaky: .stats.flaky}'

# For ad-hoc scenarios (derived from eval packs or specs), generate ephemeral test scripts:
cat > "${VALIDATION_TMPDIR}/smoke.spec.ts" << 'EOTEST'
import { test, expect } from '@playwright/test';
// ... generated scenario code ...
EOTEST
npx playwright test "${VALIDATION_TMPDIR}/smoke.spec.ts" --reporter=json
```

**axe-core a11y overlay** (runs alongside browser path when axe is detected):

```bash
# Via Playwright axe integration
npx @axe-core/cli http://localhost:${PORT}/ --exit --reporter json 2>/dev/null | jq '{violations: [.violations[] | {id, impact, description, nodes: [.nodes[] | .target]}]}'

# Capture screenshots with a11y annotations
npx playwright screenshot --full-page "http://localhost:${PORT}/" "tests/artifacts/validation/a11y-screenshot.png" 2>/dev/null
```

Check for AA contrast, ARIA landmarks, keyboard navigation, form labels, and alt text.

### API Path

```bash
# Health probe
curl -sf "http://localhost:${PORT}/health" && echo "health: pass" || echo "health: fail"

# Endpoint smoke tests from derived scenarios
for scenario in "${SCENARIOS[@]}"; do
  endpoint=$(echo "$scenario" | jq -r '.inputs.endpoint')
  expected_status=$(echo "$scenario" | jq -r '.expected.status')
  actual_status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${PORT}${endpoint}")
  echo "${endpoint}: expected=${expected_status} actual=${actual_status}"
done

# If OpenAPI spec available, validate response bodies against schema
# Use jq to compare response shape against documented schema
```

### CLI Path

```bash
# --help smoke
./${BINARY} --help >/dev/null 2>&1 && echo "help: pass (exit 0)" || echo "help: fail (exit $?)"

# Scenario execution from eval packs
for scenario in "${CLI_SCENARIOS[@]}"; do
  cmd=$(echo "$scenario" | jq -r '.inputs.command')
  expected=$(echo "$scenario" | jq -r '.expected.exit_code // 0')
  eval "${cmd}" >/dev/null 2>&1
  actual=$?
  echo "${cmd}: expected_exit=${expected} actual_exit=${actual}"
done
```

### Graceful Degradation

Each path degrades independently through four tiers:

| Tier | Condition | Behavior |
|------|-----------|----------|
| 1 | Tool available + specs/evals exist | Derive and run structured scenarios with full evidence |
| 2 | Tool available + no specs/evals | Run generic smoke checks (Tier 3 scenarios from Step 2) |
| 3 | No tool detected for a path | Emit manual validation checklist with specific steps for that path |
| 4 | No tools at all | Report "no interactive validation tools available" and emit a manual checklist fallback |

When **no interactive validation tools** are detected across all paths, produce a manual validation checklist instead:

```markdown
### Manual Validation Checklist
No interactive validation tools detected. Verify manually:
- [ ] Open the application and confirm the changed feature works
- [ ] Check browser console for errors
- [ ] Verify API responses match expected schemas
- [ ] Test CLI commands produce expected output
- [ ] Check accessibility with browser dev tools
```

## Step 4: Unified Report

Present results with the heading `## Validation Report`. Same shape regardless of which paths executed — omit sections for paths that were not detected but always include Coverage Gaps and Manual Checks.

```markdown
## Validation Report

### Browser Results (Playwright) — N scenarios
| Scenario | Source | Result | Evidence |
|----------|--------|--------|----------|
| homepage-loads | eval-pack | PASS | screenshot: tests/artifacts/validation/home.png |
| login-flow | intent-truth | FAIL | Expected redirect to /dashboard, got 404 |

### API Results (curl @ localhost:PORT) — N scenarios
| Endpoint | Source | Result | Evidence |
|----------|--------|--------|----------|
| GET /health | generic-smoke | PASS | HTTP 200, 12ms |
| POST /api/auth/login | eval-pack | PASS | HTTP 200, valid JSON body |

### CLI Results (./path/to/binary) — N scenarios
| Command | Source | Result | Evidence |
|---------|--------|--------|----------|
| --help | generic-smoke | PASS | exit 0, usage text present |
| process input.json | eval-pack | FAIL | exit 1, "missing field" error |

### A11y Results (axe-core) — N checks
| Check | Severity | Element | Issue |
|-------|----------|---------|-------|
| color-contrast | serious | .btn-primary | Contrast ratio 3.2:1 < 4.5:1 (AA) |
| aria-label | moderate | nav > ul | Navigation landmark missing label |

### Coverage Gaps
- [Scenarios that could not be validated and why]
- [Paths that had no tool available]
- [Eval pack scenarios without matching execution path]

### Manual Checks Recommended
- [Checks requiring human judgment — visual design, UX flow, business logic correctness]
- [Cross-browser testing if only one browser engine was available]
- [Performance characteristics under load]
```

**Source column values:** `eval-pack` (from `tests/fixtures/evals/*.json`), `intent-truth` (from specs/plans), `generic-smoke` (auto-generated).

## Step 5: Fix-Rescan Loop

If validation failures are found during REVIEW, fix and re-validate. **Max 3 iterations** to prevent infinite loops (same pattern as `security-scanner`):

1. Present failing scenarios from the Validation Report
2. Fix the underlying issue using normal editing tools
3. Re-run only the specific failing scenarios to verify the fix
4. If new failures emerge, return to step 1
5. After 3 iterations, report remaining failures as requiring human review

**Fix priority:** Functional failures (wrong output, crashes) > A11y violations (serious > moderate) > Warnings

After the loop completes (or on first pass if all scenarios pass), present the final Validation Report.

## Step 6: Session Marker

After completing validation (regardless of pass/fail outcome), write a session-scoped marker to prevent duplicate runs in SHIP phase:

```bash
touch ~/.claude/.skill-validation-ran-$(cat ~/.claude/.skill-session-token 2>/dev/null || echo default)
```

This marker is checked by the SHIP phase composition gate. If present, the SHIP fallback entry for runtime-validation is suppressed — validation already ran in REVIEW.

## Cleanup

After all validation is complete:

```bash
# Clean up ad-hoc scripts (temp directory)
rm -rf "${VALIDATION_TMPDIR}"

# Artifacts in tests/artifacts/validation/ are preserved (gitignored) for human review
```

Ad-hoc test scripts are ephemeral and never committed. Screenshots and validation artifacts persist in `tests/artifacts/validation/` for post-review inspection but are gitignored.
