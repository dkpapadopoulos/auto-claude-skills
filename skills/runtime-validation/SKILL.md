---
name: runtime-validation
description: Use when you need to prove a change actually works through its real interfaces — during REVIEW or on requests like validate the feature, does it work, run e2e, or smoke test — covering browser E2E, API smoke, CLI checks, and a11y, perf (Lighthouse), and visual-regression audits with graceful tool-degradation
---

# Runtime Validation

Realistic-context validation orchestrator: detect available tools, derive scenarios from specs and eval packs, execute browser/API/CLI paths, report with evidence. Composes with `webapp-testing` when available.

## When to Use

During REVIEW phase, after code changes are complete. Also invocable on explicit validation requests (e.g., "validate the feature", "does it work", "try it out", "run e2e", "smoke test").

This skill proves the feature works in a realistic context — beyond "tests pass" to "the feature behaves correctly when exercised through its real interfaces."

## Reference files

Situational detail lives in `references/` in this skill's base directory. Read each file with the Read tool at the moment named; never run those scripts or write the report from memory.

| File | Read it |
|---|---|
| `references/perf-overlay.md` | Step 3, before running the Lighthouse perf overlay (a Lighthouse CLI was detected and a dev-server URL found) |
| `references/visual-regression-overlay.md` | Step 3, before running the visual-regression overlay (Playwright is available) |
| `references/report-template.md` | Step 4, before writing the `## Validation Report` (every run) |

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

# Lighthouse (perf overlay) — self-gating: only runs if already present.
# Detect ONLY the `lighthouse` CLI (what the overlay actually invokes) so detection
# matches execution. @lhci/cli and unlighthouse have different invocations and are
# NOT run by this overlay — reporting them "available" would announce-then-skip.
command -v lighthouse >/dev/null 2>&1 && echo "lighthouse: available" || {
  if [ -f package.json ]; then
    jq -e '.dependencies.lighthouse // .devDependencies.lighthouse' package.json >/dev/null 2>&1 \
      && echo "lighthouse: available via npx" || echo "lighthouse: not detected"
  else
    echo "lighthouse: not detected"
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

Eval-pack safety scenarios are **append-only** — never delete a scenario to make the bar pass. If a case is genuinely obsolete, mark it `deprecated` with a dated rationale instead. Production failures and edge cases become new scenarios; the set grows over the life of the work.

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

### Expectation Provenance (MUST)

Every scenario's **expected outcome** MUST trace to one of the three source tiers above — `eval-pack`, `intent-truth`, or `generic-smoke` (the only values the report's Source column permits). The implementation under validation (diff, source code) MAY inform **which paths to exercise** and supplies **actual observations** — it MUST NOT define what counts as correct. Deriving "expected" from the code you are validating turns validation into confirmation of the implementation, bugs included.

If the only statement of expected behavior is the implementation itself, the scenario is at best `generic-smoke` — or a Coverage Gap flagged for human definition of expected behavior. A scenario whose expectation cannot be traced to a source tier is invalid: do not report it as PASS.

### Mandatory: Safety-Relevant Paths

When the change touches **authentication/authorization, data deletion, money/payments, or destructive or externally-visible side effects**, those paths **MUST be exercised** and reported (pass/fail with evidence) — not deferred to "Manual Checks". Green tests on the happy path do not clear a change that alters a safety-relevant path without exercising it. If no tool can exercise such a path, say so explicitly in Coverage Gaps and flag it for human verification rather than omitting it.

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

**Lighthouse perf overlay** (runs alongside the browser path when a Lighthouse-family
tool was detected AND the port probe found a dev-server URL). **Report-only:** perf
findings are advisory and do NOT enter the fix-rescan loop.

Read `references/perf-overlay.md` and run its script: it re-probes the dev-server port to set `PERF_URL`, self-gates on an installed `lighthouse` (never an npx download), and writes `tests/artifacts/validation/lighthouse.json`.

These are **Lighthouse lab** metrics from a single run, **not** field Core Web Vitals.
The three field CWV are LCP, **INP**, and CLS; a lab run cannot measure INP, so TBT is
reported as its lab proxy. The report MUST state that field INP is not measured and that
only one dev-server URL was sampled (not the production bundle / field data).

**Visual-regression overlay** (runs alongside the browser path when Playwright is
available). **Report-only:** visual diffs are advisory and do NOT enter the fix-rescan loop
and never hard-block REVIEW — same rationale as the Lighthouse overlay (screenshots are
environment-sensitive).

Uses Playwright's built-in screenshot comparison (`toHaveScreenshot`) — no extra dependency.
Baselines are **gitignored** artifacts under `tests/artifacts/validation/`, never committed.

Read `references/visual-regression-overlay.md` and run its script: it routes Playwright's snapshots to the persistent `tests/artifacts/validation/visual-baselines/`, seeds a missing baseline, and otherwise reports `MATCH` or `CHANGED`.

A first run with no baseline reports `BASELINE_MISSING/SEEDED` and lists the scenario in
Coverage Gaps — it is **not** a PASS or FAIL. Subsequent runs report `MATCH` or `CHANGED`.
This is **session-scoped** diffing (detects change within a review session); it is **not**
cross-commit field regression. For durable cross-commit regression, direct the user to
**project-native committed Playwright snapshots** in their own suite.

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

# Scenario execution from eval packs.
# SECURITY: scenario commands are run as code. Treat eval packs as TRUSTED committed fixtures
# only — never execute scenario commands sourced from untrusted/attacker-influenced input.
# Do NOT `eval` the command string (eval runs in THIS shell and re-parses, so a crafted
# fixture could mutate the validation environment). Prefer the structured argv form, which
# runs with NO shell; fall back to a child subshell (bash -c) for the legacy string form.
for scenario in "${CLI_SCENARIOS[@]}"; do
  expected=$(echo "$scenario" | jq -r '.expected.exit_code // 0')
  if echo "$scenario" | jq -e '.inputs.argv | type == "array"' >/dev/null 2>&1; then
    # Preferred: argv array executed directly — no shell, no injection surface.
    argv=(); while IFS= read -r _a; do argv+=("$_a"); done < <(echo "$scenario" | jq -r '.inputs.argv[]')
    "${argv[@]}" >/dev/null 2>&1; actual=$?
    label="${argv[*]}"
  else
    # Legacy string form (trusted fixtures only): run in a child subshell, never `eval`.
    cmd=$(echo "$scenario" | jq -r '.inputs.command')
    bash -c "${cmd}" >/dev/null 2>&1; actual=$?
    label="${cmd}"
  fi
  echo "${label}: expected_exit=${expected} actual_exit=${actual}"
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
- [ ] Run `npx lighthouse <url>` manually and review the performance score + LCP/CLS/TBT
```

## Step 4: Unified Report

Present results with the heading `## Validation Report`. Same shape regardless of which paths executed — omit sections for paths that were not detected but always include Coverage Gaps and Manual Checks.

Read `references/report-template.md` before writing the report: it holds the exact table for each path (Browser, API, CLI, A11y, Perf, Visual Regression) and the Coverage Gaps and Manual Checks sections. Write each Coverage Gap as a next action and each Manual Check as an imperative the human can execute, never as a passive note.

**Source column values:** `eval-pack` (from `tests/fixtures/evals/*.json`), `intent-truth` (from specs/plans), `generic-smoke` (auto-generated). A row whose Source is not one of these three values had its expectation derived from somewhere else — usually the implementation — and must be re-derived from a valid source tier or dropped (see Expectation Provenance).

## Step 5: Fix-Rescan Loop

If validation failures are found during REVIEW, fix and re-validate. **Max 3 iterations** to prevent infinite loops (same pattern as `security-scanner`):

1. Present failing scenarios from the Validation Report
2. Fix the underlying issue using normal editing tools
3. Re-run only the specific failing scenarios to verify the fix
4. If new failures emerge, return to step 1
5. After 3 iterations, stop the auto-fix loop and hand off each remaining failure as an explicit action — name the scenario, the observed failure, and the specific fix or decision the human must make. Do not file it as a passive "needs review."

**Fix priority:** Functional failures (wrong output, crashes) > A11y violations (serious > moderate) > Warnings

**Perf is report-only.** Lighthouse scores are noisy and not rescannable like discrete
defects, so perf findings do NOT enter this fix-rescan loop and never hard-block REVIEW —
they are reported with a remediation hint only. When render-blocking CSS is the flagged
cause AND the project has no framework-level critical-CSS inlining, the hint MAY name a
critical-CSS tool (`critical` or the maintained `beasties` fork of critters); for
framework apps (Next/Nuxt/SSR) defer to the framework's own inlining.

After the loop completes (or on first pass if all scenarios pass), present the final Validation Report.

## Cleanup

After all validation is complete:

```bash
# Clean up ad-hoc scripts (temp directory)
rm -rf "${VALIDATION_TMPDIR}"

# Artifacts in tests/artifacts/validation/ are preserved (gitignored) for human review
```

Ad-hoc test scripts are ephemeral and never committed. Screenshots and validation artifacts persist in `tests/artifacts/validation/` for post-review inspection but are gitignored.

## Eval strategy at DESIGN

The DESIGN-phase hint `EVAL STRATEGY` points here. Before leaving DESIGN, classify how the feature is verified; ask the user if it is unclear.

- **Probabilistic, AI, LLM or agent behaviour** (outputs cannot be exact-matched): plan an eval SET, not just unit tests. It holds a smoke subset; adversarial and safety subsets (jailbreak, injection, safety-routing suppression); a pinned judge model and version; never-delete cases (deprecate with a dated rationale instead); and a pre-registered safety stop naming the halt condition and who can call it. Author the safety subset first and have it failing (red) before implementation.
- **Deterministic behaviour**: standard test-driven development plus the design's acceptance scenarios are the bar.
- **Safety dimensions are hard pass/fail gates**, never averaged into a quality blend.

Run eval packs through this skill (Step 2 derives scenarios from specs and evals; Step 3 executes them).

## Verification

Before claiming the change works, confirm -- from observed output, not inference:

- Each declared path (browser / API / CLI) either ran with its result captured in `tests/artifacts/validation/`, or was explicitly reported as skipped with the missing tool named -- announce-then-skip is a failure.
- Safety-relevant paths were exercised, not deferred.
- A passing run shows real interface output (HTTP status, exit code, screenshot) -- not a stubbed or assumed success.
- Lab-only signals (e.g. Lighthouse perf) are reported as lab, never field, and never gate the result.
- Visual-regression results (if run) are reported as MATCH / CHANGED / BASELINE_MISSING and never hard-block the review -- first-run baselines are seeded, not failed; durable cross-commit regression is delegated to the consumer's committed snapshot suite.
