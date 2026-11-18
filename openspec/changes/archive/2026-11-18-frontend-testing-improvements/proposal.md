# Proposal: Frontend-Testing Improvements

## Why

The frontend-testing story our enforced PDLC hands downstream users has three gaps:

1. **No prescriptive frontend-quality guidance.** We have `frontend-design` (aesthetics) and
   `runtime-validation` (measures a11y/perf), but nothing routes users to prescriptive
   *build-it-right* standards (UI interaction/a11y rules; React/Next performance rules like
   async-waterfall elimination and bundle splitting). High-quality external skills exist for
   this (`vercel-labs/web-interface-guidelines`, `vercel-labs/agent-skills` react-best-practices)
   but nothing surfaces them.

2. **No visual-regression evidence.** `runtime-validation` captures screenshots but never diffs
   them, so unintended visual changes during REVIEW go undetected.

3. **A routing seam bug.** The `frontend-playwright` methodology hint promises *"During REVIEW,
   use runtime-validation"* but its `phases` are only `DESIGN`+`IMPLEMENT`, so that REVIEW
   promise can never fire.

## What Changes

- **Add an advisory `frontend-quality-rules` methodology hint** that surfaces the external Vercel
  frontend-quality skills *if installed*, following the established `firebase`/`playwright-mcp`
  advisory-conditional precedent (no `.plugin` gate, no hardcoded invocation token). React/Next
  guidance is scoped to React/Next signals; general UI guidance fires on generic frontend signals.
  Explicit fallback to our own `frontend-design` + `runtime-validation` so a stale/absent reference
  degrades to silence, not a broken instruction.
- **Fix the `frontend-playwright` REVIEW seam** by adding `REVIEW` to its `phases`.
- **Add a report-only visual-regression overlay** to `runtime-validation`'s Browser Path:
  Playwright's built-in screenshot compare (no new dependency), gitignored baselines, first-run
  `BASELINE_MISSING/SEEDED` handling, excluded from the fix-rescan loop (env-sensitive, same
  rationale as the Lighthouse perf overlay).
- **Add routing terms** (`visual.regress|layout.regress|screenshot`) to `runtime-validation`
  triggers with negative regex fixtures.

## Capabilities

- **Modified: `skill-routing`** — new `frontend-quality-rules` hint; `frontend-playwright` phase
  fix; new `runtime-validation` trigger terms. Config in `config/default-triggers.json` +
  `config/fallback-registry.json`.
- **Modified: `runtime-validation`** — visual-regression overlay section, report section, and
  verification bullet in `skills/runtime-validation/SKILL.md`.

## Impact

- **Code/config:** `config/default-triggers.json`, `config/fallback-registry.json`,
  `skills/runtime-validation/SKILL.md`.
- **Tests:** new regex fixtures (positive + negative) for the new hint and trigger terms;
  routing test for the `frontend-playwright` REVIEW phase; new
  `tests/test-visual-regression-overlay.sh` content contract (mirrors `test-perf-overlay.sh`).
- **Dependencies:** none added. Visual regression uses Playwright's built-in compare; the Vercel
  skills are external and optional.
- **No hook-logic change** — zero blast radius on the fail-open activation hot path.

## Out of Scope

- Adopting or racing `dev-browser` (parked; revival trigger: a named user hitting token/flakiness
  pain → run the A/B against the `webapp-testing` baseline).
- Copying Vercel rule content into this repo (context bloat; react-best-practices' AGENTS.md is
  ~2975 lines).
- Building a `skills_any` hook-gating primitive (deferred; revival trigger: ≥2 external-skill hints
  needing presence-gating, OR measured mis-routing).
- Committed visual baselines (belong in the consumer project's own Playwright suite, not our
  gitignored review artifacts).
