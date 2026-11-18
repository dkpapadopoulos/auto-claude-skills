# Design: Frontend-Testing Improvements

## Architecture

Three independent, reversible changes across two capabilities. **No hook-logic change** — all
routing changes are config data; the only skill-doc change is additive.

### 1. `frontend-quality-rules` advisory hint (`skill-routing`)

A new `methodology_hints[]` entry in `config/default-triggers.json` (mirrored to
`config/fallback-registry.json`, which session-start regenerates — both are touched per the
canonical-source convention).

- **Mechanism:** advisory-conditional wording, following the `firebase` (line 877) and
  `playwright-mcp` (line 890) precedent — neither has a `.plugin` field; both say *"If X is
  available, use it."* The model reads which skills are actually loaded at runtime and resolves the
  invocation itself. We never emit a hardcoded `Skill(<plugin>:<skill>)` token, because we don't own
  the Vercel namespace.
- **Framework scoping:** two references, scoped separately. `web-interface-guidelines`
  (framework-agnostic UI/a11y) is offered on general frontend signals; `react-best-practices`
  (React/Next-specific perf) is offered only when React/Next signals are present. This prevents
  routing React guidance onto Vue/Svelte/plain-DOM frontends.
- **Regex self-anchoring:** hint-path triggers bypass the word-boundary post-filter, so triggers
  must self-anchor `(^|[^a-z])…($|[^a-z])` (per the `frontend-playwright` entry and the
  hint-path reference note).
- **Phases:** `IMPLEMENT` (build-it-right) + `REVIEW` (audit).
- **Fallback:** hint text names our own `frontend-design` + `runtime-validation` as the fallback,
  so a stale/renamed external reference degrades to silence, not a broken instruction.

### 2. `frontend-playwright` REVIEW-seam fix (`skill-routing`)

Add `REVIEW` to the `frontend-playwright` hint's `phases` array so its own *"During REVIEW, use
runtime-validation"* text can fire. One-line data change + a routing assertion.

### 3. Visual-regression overlay (`runtime-validation`)

A report-only overlay in the Browser Path of `skills/runtime-validation/SKILL.md`, structurally
parallel to the existing Lighthouse perf overlay.

- **Diff mechanism:** Playwright's built-in screenshot comparison. No `pixelmatch` or other new
  dependency — the skill already assumes Playwright.
- **Baseline storage:** gitignored, `tests/artifacts/validation/visual-baselines/<scenario>/<viewport>.png`;
  actuals/diffs under `tests/artifacts/validation/visual-runs/`. **Not committed** — committed
  snapshots belong in the *consumer's* own Playwright suite.
- **First run:** `BASELINE_MISSING/SEEDED` — capture the screenshot as the new baseline, list it in
  Coverage Gaps, do **not** pass/fail on it.
- **Subsequent runs:** `MATCH` or `CHANGED` in a new report-only section.
- **Report-only:** excluded from the fix-rescan loop and never hard-blocks REVIEW (screenshots are
  environment-sensitive, same rationale as Lighthouse perf). Honesty note in the report:
  session-scoped diffing detects change *within* a review session; durable cross-commit regression
  is delegated to project-native committed snapshots.
- **Routing:** add `visual.regress|layout.regress|screenshot` to `runtime-validation` triggers,
  with negative fixtures guarding false positives (e.g. `tabulate`, `onboarding`).

## Trade-offs

- **Advisory hint emits even when the external skills are absent** (mild context noise). Accepted:
  the conditional wording + explicit fallback bounds the cost to one line, and the model degrades to
  our own skills. This is the same trade the `firebase`/`playwright-mcp` hints already make.
- **Session-scoped visual diffing, not cross-commit.** Accepted: committed baselines would bloat our
  repo and belong to the consumer's suite; we report the limitation explicitly.

## Dissenting views (from the design debate)

- **Critic argued for "do nothing" (option D)**, on the premise that naming absent tooling breaks a
  routing invariant. **Adjudicated against:** the premise is factually wrong — `firebase` and
  `playwright-mcp` already name possibly-absent tooling without a `.plugin` gate. The "do nothing"
  case collapses.
- **Critic's surviving concerns were folded into the design**, not dismissed: (1) React/Next
  framework mismatch → framework-scoped references; (2) unknowable invocation surface → descriptive,
  not hardcoded, skill references; (3) third-party staleness/supply-chain → generic wording +
  explicit fallback, docs-only blast radius.
- **Critic's "the gap may be imaginary" stands as a watch-item:** the hint only pays off for
  React/Next users who have installed the Vercel skills; it is inert otherwise. Acceptable because
  the cost of being inert is ~one advisory line.

## Decisions & rejected alternatives

- **Rejected B (build a `skills_any` hook-gating primitive now):** the ~50ms fail-open activation
  hot path gates all routing; an unguarded non-zero there can bypass gates. Enormous blast radius
  and speculative reuse (one consumer). Reversibility asymmetry is decisive — A is a config revert,
  B is a hot-path amputation. **Deferred** with revival trigger: ≥2 external-skill hints needing
  presence-gating, OR measured mis-routing.
- **Rejected C (own thin `frontend-quality` orchestrator skill):** owns a checklist with no
  enforceable floor (external skills may be absent), duplicates `frontend-playwright` /
  `runtime-validation`, and adds maintenance.
- **Rejected `dev-browser` adoption:** substrate swap on a vendor benchmark; not selected by the
  user. Parked with revival trigger.
- **Rejected `pixelmatch` for visual diffing:** violates "no new dependency"; Playwright's built-in
  compare suffices.

## Verification

Deterministic feature → standard TDD + the acceptance scenarios below are the bar. No
probabilistic/AI behavior, so no eval set. **Trifecta:** private_data Absent, untrusted_input Absent
(screenshots of a local dev server the user already runs), outbound_action Absent → count 0; no
`agent-safety-review` required.
