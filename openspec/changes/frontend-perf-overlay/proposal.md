# Proposal: Frontend Performance Overlay in runtime-validation

## Why

Our PDLC has a REVIEW-phase validation gate (`runtime-validation`) that already
discovers a running dev server, runs an axe-core **a11y overlay** against it, and
reports with a fix-rescan loop. It has **no frontend-performance check** — perf is
only listed as a deferred "Manual Check". For repos that ship user-facing web UIs,
Core Web Vitals (LCP/CLS/TBT) regressions slip through REVIEW unmeasured.

This change was triggered by evaluating `addyosmani/critical` for our frontend
flows. Finding: `critical` is a build-time **remediation** (inlines above-the-fold
CSS), not a **measurement**, so it cannot be a gate. The right gate tool is the
Lighthouse family, and the right home is the existing `runtime-validation` skill —
not a new skill — because the running-URL machinery, report, and fix-loop already
live there.

## What Changes

- **runtime-validation**: add an optional **Perf overlay** that parallels the
  existing a11y overlay — detect a Lighthouse-family tool, run it against the
  already-discovered server URL, report **Lighthouse lab metrics** (perf score + LCP,
  CLS, TBT) against thresholds. These are lab signals, **not** field Core Web Vitals
  (field CWV are LCP/INP/CLS; a lab run cannot measure INP, so TBT is reported as its
  lab proxy). Perf is **report-only advisory** — it does NOT enter the fix-rescan loop
  and never hard-blocks REVIEW; the report states the single-URL/dev-server scope.
- **Self-gating activation**: the overlay runs ONLY when a Lighthouse-family tool
  is already present (`lighthouse` on PATH, or `lighthouse`/`@lhci/cli`/`unlighthouse`
  in `package.json`). Repos without it fall through to the existing manual checklist.
  This makes demand self-selecting per-repo rather than guessed globally.
- **Routing**: add `lighthouse`/`web vitals`/`core web vitals`/`pagespeed`/`lcp`/`cls`
  trigger terms so "check perf"-style prompts route to runtime-validation. Dual-touch
  `config/default-triggers.json` + `config/fallback-registry.json`. Deliberately
  EXCLUDE bare `performance`/`perf` to avoid collisions with incident-analysis and
  alert-hygiene.
- **`critical`**: rejected as a gate tool (it remediates, it doesn't measure). Appears
  as a **conditional** remediation hint — surfaced concretely only when the overlay
  flags render-blocking CSS AND the project is a static/no-framework-optimizer build
  (`critical` or `beasties`); for framework apps it stays a one-liner deferring to the
  framework's own critical-CSS inlining. (`critical` is actively maintained — v8.0.0,
  2026-05-17 — so the hint points at a live tool.)

## Capabilities

### Modified
- **runtime-validation** — adds the perf-overlay requirement (ADDED requirement in
  a newly-created capability spec, since none existed before).

## Impact

- One SKILL.md body edit + two routing-config edits + one degradation test fixture.
- Description gains perf terms ⇒ a deliberate routing change (dual-touch).
- No new skill, no new runtime dependency forced on any user (overlay is opt-in by
  tool presence). Fail-open: missing tool ⇒ manual checklist, never a hard error.
- No trifecta surface (localhost-only, no egress, repo-local inputs).
