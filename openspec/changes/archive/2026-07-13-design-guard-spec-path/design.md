# Design: Design-Guard Spec-Path Fallback

## Architecture

One additive block in the DESIGN COMPLETENESS section of `hooks/skill-activation-hook.sh`, immediately after the existing design-file G/W/T check:

1. Runs ONLY when the design-file check left `_DC_ACC=0` (missing heading or thin section) — the success path is untouched.
2. Derives the change directory from the path the guard already holds: `_DP_DIR="${_DP_DESIGN%/*}"`; if `${_DP_DIR}/specs` is not a directory, skip silently (this is every default-mode design doc).
3. One `cat "${_DP_DIR}"/specs/*/spec.md | awk` pass counts lines containing uppercase `WHEN` and `THEN` tokens (same non-alpha-boundary pattern as the design-file check, so `- **WHEN**` matches). Aggregated `min(WHEN, THEN) >= 2` sets `_DC_ACC=1` and `_DC_ACC_SPECS=1`.
4. Rendering: when satisfied via specs, the line reads `[OK] Acceptance Scenarios (in sibling specs/)` so a reader knows where the contract was met; the all-present short-circuit is unchanged (`_DC_ACC=1`). SKILL_EXPLAIN breadcrumb gains `gwt_specs=${_DC_SPEC_WT:-n/a}`.

## Trade-offs

- **WHEN/THEN count vs `#### Scenario:` heading count:** heading count false-OKs on empty scenario stubs (the gate-gaming hole this guard family exists to close); token counting is deny-biased. Chosen: tokens.
- **GIVEN excluded from the spec-file rule:** the OpenSpec scenario template makes GIVEN optional — verified against real repo spec files (2 of 7 sampled changes are WHEN/THEN-only). Requiring GIVEN would false-`[X]` template-conformant specs.
- **Sibling glob vs session-state `spec_path`:** the state field is a single file (multi-capability changes under-covered) and costs jq forks; the glob derives from data the guard already validated and covers every `specs/<cap>/spec.md`.
- **Distinct `[OK]` wording:** "(in sibling specs/)" preserves information the plain `[OK]` would hide — reviewers of default-mode docs should still expect scenarios in the design file itself.

## Dissenting Views

- The dogfood's second finding (0/5 advisory uptake in both probe arms) argues the *bigger* lever is promoting the advisory into CURRENT-step text (the mechanism measured at 5/5 in the discovery-precondition work). Deliberately NOT bundled here: this fix is the prerequisite (a permanently-red advisory cannot be effective anywhere it renders), and step-text promotion needs its own uptake eval.
- Meta-mentions of "GIVEN/WHEN/THEN" in prose still count as tokens (dogfood finding 3). Unchanged here — it biases toward `[OK]`/hint noise only in docs that discuss the format itself, and a fix (excluding code-quoted or slash-joined mentions) risks false-`[X]` on legitimate scenarios. Revisit if it misleads outside plugin-dev docs.

## Decisions

1. Satisfied-rule: aggregated `min(WHEN, THEN) >= 2` across all sibling spec files, uppercase, non-alpha boundaries, per-line counting (same semantics as the design-file check).
2. Strictly additive: the block can only flip `[X]→[OK]`; awk failure, non-numeric output, or missing glob all degrade to the design-file verdict — fail-open by construction, advisory posture unchanged.
3. Bash 3.2 / BSD-awk safe: no interval expressions, no associative arrays; glob expansion inside `cat` with stderr suppressed covers the no-match case.

## Capabilities Affected

- `skill-routing` (PLAN-phase design guard in `hooks/skill-activation-hook.sh`)

## Out-of-Scope

- Promoting the thin/missing advisory into CURRENT-step composition text (separate follow-up with its own red-first uptake eval).
- The meta-mention counting artifact (documented above; revisit on evidence of real confusion).
- Any change to gate posture, push gates, or the design-file check's existing semantics.

## Acceptance Scenarios

See `specs/skill-routing/spec.md` (4 GIVEN/WHEN/THEN scenarios). Success bar: aggregated min(WHEN,THEN) >= 2 flips the line to [OK]; full suite stays green at 85/85 files; post-fix corpus re-run flips the acceptance line on the repo's real spec-driven changes whose specs carry >= 2 scenarios.

## Implementation Notes (synced at ship time)

- Built as designed. One review follow-up strengthened spec conformance: the all-present short-circuit initially dropped the "(in sibling specs/)" annotation (a documented deviation); review flagged it against the spec's SHALL, so the summary line now carries "; acceptance in sibling specs/" when the fallback satisfied the check — verified red-first against the pre-fix hook.
- Post-fix dogfood corpus: all 7 real spec-driven changes flipped to [OK] (gwt_specs 4-10), including this change itself rendering "all sections present (…; acceptance in sibling specs/)".

## Divergences (auto-generated at ship time)

**Acceptance Scenarios:**
- [x] Spec-driven change satisfies via sibling specs — implemented as designed (`test_plan_completeness_specpath_satisfies_perline`)
- [x] GIVEN-less template scenarios count — implemented as designed (GIVEN-less bold WHEN/THEN fixtures in both flip tests)
- [x] Thin sibling specs do not flip — implemented as designed (`test_plan_completeness_specpath_thin_specs_stay_flagged`)
- [x] Default-mode designs unaffected — locked by the entire pre-existing fixture population (verified by reviewer)
- [~] Distinct annotation on the summary line — spec's SHALL initially unmet on the all-present short-circuit; fixed post-review (6429c30), red-first verified

**Scope changes:** none (Added/Removed/Modified: none)

**Design decision changes:** none — deny-bias trade (WHEN/THEN prose meta-mentions) stands as documented in Dissenting Views.
