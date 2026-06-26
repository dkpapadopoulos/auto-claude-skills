# Design: Frontend Performance Overlay

## Architecture

The perf overlay is structurally a clone of the existing **axe-core a11y overlay**
inside `runtime-validation`, applied to the same discovered server URL:

1. **Detect (Step 1, Browser/Perf Path).** Add a perf detection block:
   ```
   command -v lighthouse  → "lighthouse: available"
   else if package.json has lighthouse / @lhci/cli / unlighthouse in (dev)deps
        → "lighthouse: available via npx"
   else → "lighthouse: not detected"
   ```
   Availability is the **only** activation condition — no global flag, no config.

2. **Execute (Step 3, Perf overlay).** Runs only if detected AND a server URL was
   found by the existing port probe (3000/5173/8000/8080):
   ```
   npx lighthouse "$URL" --quiet --chrome-flags="--headless" \
     --only-categories=performance --output=json --output-path=stdout \
     | jq '{score: .categories.performance.score,
            lcp: .audits["largest-contentful-paint"].numericValue,
            cls: .audits["cumulative-layout-shift"].numericValue,
            tbt: .audits["total-blocking-time"].numericValue}'
   ```
   JSON artifact saved to `tests/artifacts/validation/lighthouse.json` (gitignored).

3. **Report (Step 4, new section).** "Perf Results (Lighthouse — lab)" parallels
   "A11y Results", reporting **Lighthouse lab metrics** (NOT field Core Web Vitals):
   | Metric | Good | Needs work | Poor |
   |--------|------|-----------|------|
   | LCP (lab) | <2.5s | 2.5–4.0s  | >4.0s |
   | CLS (lab) | <0.1  | 0.1–0.25  | >0.25 |
   | TBT (lab) | <200ms| 200–600ms | >600ms |
   | Perf score | ≥90 | 50–89 | <50 |

   **Framing correction (Codex sparring):** these are **lab** signals from a single
   Lighthouse run, not field Core Web Vitals. The three field CWV are LCP, **INP**,
   and CLS (INP replaced FID in March 2024). A plain Lighthouse lab run **cannot
   measure INP** — it reports **TBT** as a lab proxy for interaction latency. So the
   overlay deliberately reports TBT (measurable) and the report MUST state that field
   INP is not measured. Do NOT relabel TBT as a CWV.

4. **Fix priority (Step 5) — report-only, NOT a fix-loop participant.** Unlike axe
   findings (discrete, rescannable defects), Lighthouse scores are noisy and
   route/build-sensitive — you cannot "verify a fix" by rescanning a score the way
   you can a contrast violation. Therefore perf findings are **report-only advisory**:
   they appear in the report with a remediation hint but do **not** enter the
   fix-rescan loop and never hard-block REVIEW. Functional + a11y own the loop;
   perf sits outside it. (This resolves the fix-loop contract mismatch Codex raised.)

5. **Measurement scope & honesty (Codex blind-spot d).** The report MUST carry an
   explicit limitation line: the overlay measures **one auto-discovered URL on the
   running dev server in whatever mode it is running** — not the production bundle,
   not field/CrUX data, not per-route, not third-party/CDN effects. "Perf overlay
   ran" ≠ "Core Web Vitals covered." This prevents false REVIEW assurance.

6. **Degradation.** No Lighthouse tool ⇒ the existing Tier-3 manual checklist line
   is reworded to name Lighthouse ("run `npx lighthouse <url>` manually"). No new
   failure path.

## Routing

Extend the single trigger alternation in `config/default-triggers.json` (and mirror
in `config/fallback-registry.json`) with perf terms. POSIX-ERE, dot-separated to
match the file's existing style; word-boundary safety is applied by the activation
hook's post-filter.

Added terms: `lighthouse`, `web.vitals`, `core.web.vitals`, `page.?speed`, `lcp`, `cls`.
**Excluded** (deliberate): bare `perf`/`performance` — collides with incident-analysis
("DB performance") and alert-hygiene. Decision recorded so a future reader doesn't
"helpfully" add it back.

## Trade-offs

- **Extend vs new skill.** Extending reuses server-discovery + report + fix-loop and
  adds no routing surface beyond keywords; a standalone skill would duplicate all
  three. Cost: runtime-validation's SKILL.md grows. Accepted — still one focused skill.
- **Lighthouse heavyweight (needs Chrome).** Mitigated by strict self-gating: only
  repos that already installed a Lighthouse tool ever invoke it. Everyone else is
  unaffected (manual line).
- **Advisory vs hard-fail.** Advisory chosen to avoid false REVIEW blocks on perf
  noise (Lighthouse scores vary run-to-run). Hard budgets are a future opt-in if
  demand appears.

## Dissenting views

- *"Just do C (document-only)."* Defensible if no users ship perf-sensitive web UIs.
  Countered by self-gating: A collapses to C's behavior for those users at near-zero
  added cost, while paying off for repos that opted into Lighthouse.
- *"critical deserves a remediation skill."* Rejected — for framework apps, Next/SSR
  and **beasties** (the maintained fork of the now-archived critters) subsume
  critical-CSS inlining; a whole skill for one transform fails the edges-created test.
  A **conditional** remediation hint is the honest ceiling (see Decision 3). Note:
  `critical` is NOT abandoned — it is at v8.0.0 (modified 2026-05-17), so the hint
  points at a live tool.
- *"Split perf into its own skill (Codex)."* Codex argued the fix-loop contract
  doesn't compose. **Rejected as a split, accepted as a mechanism fix:** making perf
  report-only (outside the fix-loop, Architecture §4) dissolves the contract mismatch
  without a new skill. A separate skill would duplicate server-discovery + report +
  degrade machinery and would inherit the *same* dev-server/single-URL measurement
  limitation — splitting fixes none of the real problem (measurement honesty), which
  §5 addresses directly. Extend stands.

## Decisions

1. Home = extend `runtime-validation`, not a new skill (Codex split rejected; see
   Dissenting views — report-only framing resolves the fix-loop objection).
2. Activation = tool-presence self-gating, no config flag.
3. `critical` = rejected as gate. Remediation hint is **conditional**: surfaced with
   concrete weight only when the overlay flags render-blocking CSS AND the project is
   a static/no-framework-optimizer build (point at `critical` or `beasties`); for
   framework apps it stays a one-liner deferring to the framework's own inlining.
4. Perf = **report-only advisory, outside the fix-rescan loop** (noisy/non-rescannable
   scores); never hard-blocks REVIEW.
5. Report = labels metrics as **Lighthouse lab** signals, names TBT as a lab proxy,
   and MUST state field INP is not measured + the single-URL/dev-server scope limit.
6. Routing = add specific perf terms, exclude bare `perf`/`performance`.
7. Eval = deterministic ⇒ TDD; the degradation fixture (no-Lighthouse ⇒ manual
   checklist, no error) is the red-first test.

## Out-of-Scope

- Hard perf budgets / CI-failing thresholds (future opt-in).
- Committed `.lighthouserc` budget config.
- Bundling Lighthouse or auto-installing Chrome.
- Wiring `critical` (or any build transform) as an executable step.
- Perf checks for non-web (CLI/API) paths.

## Implementation Notes (synced at ship time)

- **PERF_URL wiring:** the original design assumed the Step 1 port-probe exported a
  URL; it did not. As-built, the overlay is self-contained — it re-probes ports
  `3000 5173 8000 8080` inside the Step 3 block and sets `PERF_URL` to the first that
  responds, running Lighthouse only when non-empty.
- **Self-gating in the embedded bash (review M2):** the overlay's `npx lighthouse`
  invocation is additionally guarded by `command -v lighthouse` / `npx --no-install`
  so the design's "only repos that already installed Lighthouse invoke it" guarantee
  holds even under mechanical execution, not just prose.
- **Content guard tightened (review M1):** the lab-honesty regression test asserts the
  verbatim phrase "INP is not measured" (not the substring "INP", which matched
  "inputs").
- **Spec delta format:** the acceptance spec was reformatted at ship time to openspec's
  delta grammar (`## ADDED Requirements` → `### Requirement:` → `#### Scenario:`); no
  semantic change.
- No other divergence from the approved design. `critical` remains rejected-as-gate;
  perf remains report-only.
