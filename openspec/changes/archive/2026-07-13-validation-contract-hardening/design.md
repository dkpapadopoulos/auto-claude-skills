# Design: Validation-Contract Hardening

## Architecture

Two independent, small deltas shipped as one change (same theme: close the gap between the promised validation contract and what is deterministically checked).

### Delta 1 — Expectation provenance rule (`skills/runtime-validation/SKILL.md`)

Placement: embedded in **Step 2: Derive Validation Scenarios** step text (measured pattern: step-text directives get 5/5 uptake vs 0/5 for adjacent hints — PR #104), as a `### Expectation Provenance (MUST)` subsection after the three-tier sourcing list:

- Every scenario's **expected outcome** MUST trace to one of the three source tiers: `eval-pack`, `intent-truth`, or `generic-smoke` — the same enum the report's Source column permits.
- The implementation (diff, source code) MAY inform **which paths to exercise** (coverage) and supplies **actual observations**, but MUST NOT define what counts as correct.
- If the only statement of expected behavior is the implementation itself, the scenario is at best `generic-smoke` — or a Coverage Gap flagged for human definition of expected behavior. A scenario whose expectation cannot be traced to a source tier is invalid; do not report it as PASS.

Plus one reinforcing sentence at the existing `Source column values` line in the report section: a row whose Source is outside the enum had its expectation derived from somewhere else (usually the implementation) and must be re-derived or dropped.

### Delta 2 — G/W/T body check (`hooks/skill-activation-hook.sh`, DESIGN COMPLETENESS block)

Current: `_DC_ACC=1` iff an h2/h3 `Acceptance Scenarios` heading matches. New:

1. `_DC_ACC_HEAD` keeps the heading-presence result (existing grep, unchanged).
2. When `_DC_ACC_HEAD=1`, one awk pass extracts the section (from the acceptance-scenarios h2/h3 to the next h2/h3 or EOF; h4+ subsections stay inside) and counts lines containing uppercase `GIVEN`, `WHEN`, `THEN` tokens (case-sensitive, non-letter boundaries so `**GIVEN**` and `- GIVEN` match while prose "when" does not).
3. Triplet count = `min(given, when, then)`. Contract satisfied when count >= 2 (config promises 2-4; the upper bound is not enforced — extra scenarios are not a defect).
4. `_DC_ACC=1` only when heading present AND count >= 2. Distinct advisory message for the thin case: `[X]  Acceptance Scenarios (heading present but <2 GIVEN/WHEN/THEN scenarios — write 2-4 concrete GIVEN/WHEN/THEN scenarios)`. Missing-heading message unchanged.
5. **Fail-open:** awk error, non-numeric output, or empty result degrades to heading-presence semantics (`_DC_ACC=_DC_ACC_HEAD`). The guard remains advisory-only — it never denies; Bash 3.2 / BSD-awk safe (no interval expressions, no associative arrays); `SKILL_EXPLAIN` breadcrumb gains `gwt=<count>`.

## Trade-offs

- **Provenance rule vs "code-blind" directive:** "do not read the diff" is unenforceable theater — the validating agent in a REVIEW session already has the diff in context. Provenance-of-expectations is checkable by the agent itself and consistent with the existing Source column.
- **Provenance rule vs clean-context validator dispatch:** a fresh subagent with spec-only inputs is the honest maximal version but ~10x scope (subagent plumbing + read-isolation, which the repo's behavioral-eval contamination knowledge shows is genuinely hard). Rejected for now.
- **Section-scoped vs whole-file G/W/T count:** whole-file grep is simpler but false-OKs when G/W/T tokens appear in other sections (e.g. an eval-strategy section quoting the format). Section scoping costs one awk pass.
- **Advisory vs hard-deny:** the design guard is deliberately advisory (hard-deny posture lives in `hooks/openspec-guard.sh` by prior design decision). Not changed.
- **Case-sensitive uppercase matching:** avoids prose false-positives ("when the user clicks..."); the contract hint mandates uppercase GIVEN/WHEN/THEN format, so case sensitivity enforces the promised shape.

## Dissenting Views

- **Codex (sparring partner):** endorsed both deltas in this shape; explicitly rejected the clean-context dispatch as "not worth the size without a measured false-pass from runtime-validation expectation leakage." That measurement is the revival criterion: an observed diff-derived expectation in a real validation report reopens the clean-context option.
- **No new behavioral uptake eval for Delta 1:** repo learnings demand eval-ing uptake, not presence. Counter-argument applied here: the *placement pattern* (step-text MUST vs adjacent hint) was already measured at 5/5 vs 0/5 in PR #104; re-measuring per directive fails the cheapest-alternative bar. Deterministic content tests assert presence; uptake risk is accepted and documented. Revival trigger: any real validation report showing a diff-derived expectation → author the uptake eval red-first.

## Decisions

1. Ship both deltas in one change/branch (same theme, disjoint files, tiny individually).
2. Delta 1 lives in Step 2 step-text + one line at the Source column; no new report columns, no runtime mechanism.
3. Delta 2 threshold: `min(GIVEN, WHEN, THEN) >= 2`, section-scoped, case-sensitive; fail-open to heading semantics; advisory-only.
4. No behavioral uptake eval this change (see Dissenting Views); deterministic tests only.

## Capabilities Affected

- `runtime-validation` (skill prose contract)
- `skill-routing` (PLAN-phase design guard in `hooks/skill-activation-hook.sh`)

## Out-of-Scope

- Clean-context / subagent validator dispatch (revival criterion recorded above).
- Any change to gate posture (`openspec-guard.sh`), push-gate, or verdict semantics.
- Enforcing the 2-4 upper bound on scenarios; spec-driven-mode spec files (the guard keeps reading the design_path file it reads today).
- The rejected document practices (deep modules, file-length lints, model-per-seat, history-tattoo automation, 40%-saturation heuristics).

## Acceptance Scenarios

See `specs/runtime-validation/spec.md` and `specs/skill-routing/spec.md` (2-4 GIVEN/WHEN/THEN each). Success bar: all existing suites stay green and the new regression cases pass with min(GIVEN,WHEN,THEN) >= 2 logic verified in both directions.

## Implementation Notes (synced at ship time)

- Built as designed; no architectural deviations. One review follow-up: the spec's "extraction failure fails open" scenario initially relied on structural enforcement only (`|| true` + numeric validation) — code review flagged the missing regression test, so a targeted awk-stub test was added (`test_plan_completeness_gwt_awk_failure_fails_open`, failing only the G/W/T awk pass via an `inacc`-matching stub so the hook's unrelated awk uses keep working).
- The existing `_write_design_fixture` helper and the heading-variants test needed G/W/T content added — the old fixtures encoded the pre-hardening contract (bare heading = OK), which is exactly the behavior this change retires.
- Per-line token counting (documented in the hook comment): a line holding two full scenarios counts once and heading-line tokens are skipped; an undercount can only strengthen the advisory, never block.

## Divergences (auto-generated at ship time)

**Acceptance Scenarios:**
- [x] runtime-validation: expectation derivable only from implementation → downgrade/Coverage Gap, never spec-backed PASS — implemented as designed (SKILL.md Step 2 provenance block)
- [x] runtime-validation: out-of-enum Source row invalid → re-derive or drop — implemented as designed (report-section sentence)
- [x] runtime-validation: content test pins the directive — implemented as designed (4 assertions)
- [x] skill-routing: >=2 G/W/T in section → [OK] — implemented as designed
- [x] skill-routing: heading present but thin → distinct advisory [X], no deny — implemented as designed
- [x] skill-routing: out-of-section tokens don't count — implemented as designed
- [~] skill-routing: extraction failure fails open — implemented as designed, PLUS a regression test added post-review (`test_plan_completeness_gwt_awk_failure_fails_open`); the plan had left this scenario structurally-enforced-only

**Scope changes:**
- Added: none
- Removed: none
- Modified: none

**Design decision changes:**
- None. The no-behavioral-uptake-eval decision and the clean-context-dispatch rejection (with revival criteria) stand as recorded in Trade-offs/Dissenting Views.
