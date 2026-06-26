# runtime-validation Specification

## Purpose
TBD - created by archiving change frontend-perf-overlay. Update Purpose after archive.
## Requirements
### Requirement: Frontend Performance Overlay

The runtime-validation skill SHALL provide an optional Lighthouse-based performance
overlay that reports **Lighthouse lab metrics** against a running dev server during
REVIEW, activating only when a Lighthouse-family tool is already present, and degrading
to a manual checklist otherwise. Performance findings SHALL be **report-only advisory**
— they MUST NOT enter the fix-rescan loop and MUST NOT hard-block REVIEW. The report
MUST NOT present its results as field Core Web Vitals.

#### Scenario: Lighthouse present and server reachable

- **GIVEN** a `lighthouse` binary on PATH (or a `lighthouse` entry in `package.json`)
  AND a dev server reachable on a probed port
- **WHEN** runtime-validation runs the perf overlay
- **THEN** it SHALL run Lighthouse against the discovered URL and emit a "Perf Results
  (Lighthouse — lab)" report section containing the performance score and LCP, CLS, and
  TBT classified against the documented Good/Needs-work/Poor bands, AND the section
  SHALL state that these are lab signals for one URL — that field INP is not measured
  (TBT is its lab proxy) and the production bundle/field data are out of scope

#### Scenario: No Lighthouse tool installed

- **GIVEN** no Lighthouse-family tool on PATH or in `package.json`
- **WHEN** runtime-validation reaches the perf overlay
- **THEN** it SHALL skip execution without error AND emit a manual checklist line that
  names Lighthouse (e.g. "run `npx lighthouse <url>` manually"), preserving fail-open
  behavior

#### Scenario: Poor perf band is report-only and does not block REVIEW

- **GIVEN** the perf overlay ran and returned a Poor band (e.g. perf score < 50)
- **WHEN** runtime-validation assembles the report and runs the fix-rescan loop
- **THEN** perf findings SHALL NOT enter the fix-rescan loop (which is reserved for
  functional + a11y defects) AND SHALL be emitted as report-only advisory with a
  remediation hint, never as a standalone hard failure
- **AND** when render-blocking CSS is the flagged cause AND the project has no
  framework-level critical-CSS optimizer, the hint MAY name `critical`/`beasties` as a
  concrete remediation; otherwise it defers to the framework's own inlining

#### Scenario: Perf routing terms activate the skill

- **GIVEN** a user prompt containing "check lighthouse" or "core web vitals" or "page
  speed"
- **WHEN** the activation hook scores skills in REVIEW
- **THEN** runtime-validation SHALL match, AND the bare terms "perf"/"performance"
  alone SHALL NOT be sufficient to match (collision avoidance)

