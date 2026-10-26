# runtime-validation — Validation Report template

Read at SKILL.md Step 4 before writing the `## Validation Report`, on every run. The report rules (same shape, Coverage Gaps and Manual Checks always present, the three Source values) stay in SKILL.md. Moved verbatim from SKILL.md.

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

### Perf Results (Lighthouse — lab) — lab signals, NOT field CWV
| Metric | Value | Band | Good / Needs-work / Poor |
|--------|-------|------|--------------------------|
| Perf score | 0–100 | … | ≥90 / 50–89 / <50 |
| LCP (lab) | ms | … | <2.5s / 2.5–4.0s / >4.0s |
| CLS (lab) | n | … | <0.1 / 0.1–0.25 / >0.25 |
| TBT (lab) | ms | … | <200ms / 200–600ms / >600ms |

> Lab signals from one dev-server URL. Field **INP is not measured** (TBT is its lab
> proxy); production bundle, CDN/image delivery, per-route, and third-party effects are
> out of scope. "Perf overlay ran" ≠ "Core Web Vitals covered."

### Visual Regression Results (Playwright — report-only) — N captures
| Capture | Source | Viewport | Result | Evidence |
|---------|--------|----------|--------|----------|
| homepage | generic-smoke | 1280x720 | MATCH | visual-runs/homepage.png |
| checkout | intent-truth | 375x667 | CHANGED | diff: visual-runs/checkout-diff.png |

> Session-scoped diffing, not cross-commit field regression. Baselines are gitignored and
> committed snapshots in the consumer's own suite own durable regression. `BASELINE_MISSING/SEEDED`
> on first run is neither pass nor fail — list the seeded capture in Coverage Gaps.

### Coverage Gaps
State each gap as a next action, not a passive note — a downstream agent or reviewer should be able to act on it without re-deriving what to do:
- [Validate scenario X manually — it could not be auto-validated because <reason>]
- [Install/enable <tool> to cover path Y, then re-run this scenario]
- [Add an execution path for eval-pack scenario Z, or mark it out-of-scope with a reason]

### Manual Checks Recommended
Phrase each as an imperative the human can execute:
- [Review <element/flow> by hand — requires human judgment (visual design, UX flow, business-logic correctness)]
- [Test in <other browser engine> — only one engine was available this run]
- [Load-test <path> to confirm performance characteristics under concurrency]
```
