# Validation-Contract Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close two gaps where the validation contract is promised but not enforced: (1) an Expectation Provenance MUST rule in `runtime-validation` Step 2; (2) a GIVEN/WHEN/THEN body check in the PLAN-phase design guard.

**Architecture:** Delta 1 is skill prose + content-test assertions (no runtime change). Delta 2 extends the advisory DESIGN COMPLETENESS block in `hooks/skill-activation-hook.sh` with a section-scoped awk count of uppercase GIVEN/WHEN/THEN tokens; `min >= 2` keeps `[OK]`, fewer renders a distinct thin-heading `[X]`; fail-open to heading-presence semantics. Spec: `openspec/changes/validation-contract-hardening/`.

**Tech Stack:** Bash 3.2 (macOS `/bin/bash`), BSD awk/grep, jq; test suites under `tests/`.

## Global Constraints

- Bash 3.2 compatible — no associative arrays, no PCRE, no awk interval expressions (`{2,3}`); syntax-check with `/bin/bash -n` and run suites under `/bin/bash`.
- Design guard stays **advisory-only** (never denies) and **fail-open** (any sub-check error degrades silently).
- Strings containing backticks in tests MUST be single-quoted (backtick-execution trap).
- Run suites as `bash tests/<suite>.sh < /dev/null` (socket-stdin hang).
- Targeted edits only; never full-file rewrites.
- Work in a per-feature worktree (main working tree has unrelated staged files that must not be swept into commits).

---

### Task 1: Expectation Provenance rule (runtime-validation)

**Files:**
- Modify: `tests/test-validation-skill-content.sh` (after the `fixtures/evals` assertion, line 58)
- Modify: `skills/runtime-validation/SKILL.md` (Step 2, after "### Tier 3: Generic Smoke Tests"; and the "Source column values" line in the report section)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: SKILL.md prose containing the literal strings `Expectation Provenance`, `MUST NOT define what counts as correct`, `` `eval-pack`, `intent-truth`, or `generic-smoke` ``, `do not report it as PASS` (the content test contract).

- [ ] **Step 1: Write the failing content assertions**

In `tests/test-validation-skill-content.sh`, after `assert_contains "rv: eval pack consumption" "fixtures/evals" "$RV_CONTENT"`:

```bash
# Expectation provenance (validation-contract-hardening)
assert_contains "rv: expectation provenance heading" "Expectation Provenance" "$RV_CONTENT"
assert_contains "rv: provenance MUST rule" "MUST NOT define what counts as correct" "$RV_CONTENT"
assert_contains "rv: provenance source enum" 'eval-pack`, `intent-truth`, or `generic-smoke' "$RV_CONTENT"
assert_contains "rv: untraceable expectation never PASS" "do not report it as PASS" "$RV_CONTENT"
```

- [ ] **Step 2: Run to verify the new assertions fail**

Run: `bash tests/test-validation-skill-content.sh < /dev/null`
Expected: 4 FAILs (the new assertions), everything else passing.

- [ ] **Step 3: Add the provenance rule to SKILL.md**

In `skills/runtime-validation/SKILL.md`, insert between the "### Tier 3: Generic Smoke Tests" block and "### Mandatory: Safety-Relevant Paths":

```markdown
### Expectation Provenance (MUST)

Every scenario's **expected outcome** MUST trace to one of the three source tiers above — `eval-pack`, `intent-truth`, or `generic-smoke` (the only values the report's Source column permits). The implementation under validation (diff, source code) MAY inform **which paths to exercise** and supplies **actual observations** — it MUST NOT define what counts as correct. Deriving "expected" from the code you are validating turns validation into confirmation of the implementation, bugs included.

If the only statement of expected behavior is the implementation itself, the scenario is at best `generic-smoke` — or a Coverage Gap flagged for human definition of expected behavior. A scenario whose expectation cannot be traced to a source tier is invalid: do not report it as PASS.
```

And replace the report-section line:

```markdown
**Source column values:** `eval-pack` (from `tests/fixtures/evals/*.json`), `intent-truth` (from specs/plans), `generic-smoke` (auto-generated).
```

with:

```markdown
**Source column values:** `eval-pack` (from `tests/fixtures/evals/*.json`), `intent-truth` (from specs/plans), `generic-smoke` (auto-generated). A row whose Source is not one of these three values had its expectation derived from somewhere else — usually the implementation — and must be re-derived from a valid source tier or dropped (see Expectation Provenance).
```

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/test-validation-skill-content.sh < /dev/null`
Expected: all assertions PASS, exit 0.

- [ ] **Step 5: Commit**

```bash
git add tests/test-validation-skill-content.sh skills/runtime-validation/SKILL.md
git commit -m "feat: expectation-provenance MUST rule in runtime-validation scenario derivation"
```

---

### Task 2: GIVEN/WHEN/THEN body check (design guard)

**Files:**
- Modify: `tests/test-routing.sh` — `_write_design_fixture` helper (~line 5509), `test_plan_completeness_tolerates_heading_variants` (~line 5661), plus 3 new tests after `test_plan_completeness_ignores_non_heading_mentions` (~line 5736)
- Modify: `hooks/skill-activation-hook.sh` — section-flag block (~line 1527) and `_DC_LINE_ACC` rendering (~line 1557), SKILL_EXPLAIN breadcrumb (~line 1570)

**Interfaces:**
- Consumes: existing `_seed_plan_state`, `_write_design_fixture_raw`, `run_hook`, `extract_context`, `assert_contains`/`assert_not_contains` helpers in `tests/test-routing.sh`.
- Produces: hook renders `[X]  Acceptance Scenarios (heading present but <2 GIVEN/WHEN/THEN scenarios — write 2-4 concrete GIVEN/WHEN/THEN scenarios)` for thin sections; `_write_design_fixture` emits contract-satisfying acceptance sections.

- [ ] **Step 1: Update fixtures + write the failing tests**

(a) In `_write_design_fixture`, after `printf 'Body for %s.\n\n' "${section}"` add:

```bash
            # Acceptance sections carry the 2 GIVEN/WHEN/THEN scenarios the
            # DESIGN->PLAN contract promises (validation-contract-hardening).
            case "${section}" in
                *cceptance*)
                    printf -- '- GIVEN a fixture WHEN the guard runs THEN it passes\n'
                    printf -- '- GIVEN another fixture WHEN it runs again THEN it still passes\n\n'
                    ;;
            esac
```

(b) In `test_plan_completeness_tolerates_heading_variants`, the acceptance heading is the LAST section in both raw fixtures, so append scenarios after each `_write_design_fixture_raw` call (before `_seed_plan_state`):

```bash
    printf -- '- GIVEN a fixture WHEN the guard runs THEN it passes\n- GIVEN another WHEN it reruns THEN it passes\n' >> "${design}"
```

(and the same `>> "${design2}"` after the second raw fixture).

(c) Add after `test_plan_completeness_ignores_non_heading_mentions`:

```bash
test_plan_completeness_gwt_thin_heading() {
    echo "-- test: DESIGN COMPLETENESS flags acceptance heading with <2 GWT scenarios --"
    setup_test_env
    install_registry

    local token="plan-guard-gwt-thin-$$"
    local design="${HOME}/design-gwt-thin.md"
    # Raw fixture: acceptance heading present but body has no GWT scenarios.
    _write_design_fixture_raw "${design}" \
        '## Capabilities Affected' \
        '## Out-of-Scope' \
        '## Acceptance Scenarios'
    _seed_plan_state "${token}" "fixture-slug" "${design}"

    printf '{"skill":"brainstorming","phase":"DESIGN"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output context
    output="$(run_hook "let us plan this out")"
    context="$(extract_context "${output}")"

    assert_contains "completeness header present" "DESIGN COMPLETENESS" "${context}"
    assert_contains "thin acceptance flagged" "heading present but <2 GIVEN/WHEN/THEN" "${context}"
    assert_not_contains "not the missing-heading message" "Acceptance Scenarios (missing" "${context}"
    assert_not_contains "no all-present verdict" "all sections present" "${context}"

    teardown_test_env
}
test_plan_completeness_gwt_thin_heading

test_plan_completeness_gwt_out_of_section_not_counted() {
    echo "-- test: DESIGN COMPLETENESS ignores GWT tokens outside the acceptance section --"
    setup_test_env
    install_registry

    local token="plan-guard-gwt-oos-$$"
    local design="${HOME}/design-gwt-oos.md"
    _write_design_fixture_raw "${design}" \
        '## Capabilities Affected' \
        '## Acceptance Scenarios' \
        '## Out-of-Scope'
    # GWT tokens land in the trailing Out-of-Scope section, not acceptance.
    printf -- '- GIVEN x WHEN y THEN z\n- GIVEN a WHEN b THEN c\n' >> "${design}"
    _seed_plan_state "${token}" "fixture-slug" "${design}"

    printf '{"skill":"brainstorming","phase":"DESIGN"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output context
    output="$(run_hook "let us plan this out")"
    context="$(extract_context "${output}")"

    assert_contains "thin acceptance flagged despite GWT elsewhere" "heading present but <2 GIVEN/WHEN/THEN" "${context}"

    teardown_test_env
}
test_plan_completeness_gwt_out_of_section_not_counted

test_plan_completeness_gwt_lowercase_not_counted() {
    echo "-- test: DESIGN COMPLETENESS does not count lowercase given/when/then prose --"
    setup_test_env
    install_registry

    local token="plan-guard-gwt-lower-$$"
    local design="${HOME}/design-gwt-lower.md"
    _write_design_fixture_raw "${design}" \
        '## Capabilities Affected' \
        '## Out-of-Scope' \
        '## Acceptance Scenarios'
    printf -- 'given the user clicks, when it loads, then we are happy. Repeated: given when then.\n' >> "${design}"
    _seed_plan_state "${token}" "fixture-slug" "${design}"

    printf '{"skill":"brainstorming","phase":"DESIGN"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output context
    output="$(run_hook "let us plan this out")"
    context="$(extract_context "${output}")"

    assert_contains "lowercase prose does not satisfy contract" "heading present but <2 GIVEN/WHEN/THEN" "${context}"

    teardown_test_env
}
test_plan_completeness_gwt_lowercase_not_counted
```

- [ ] **Step 2: Run to verify the new tests fail**

Run: `/bin/bash tests/test-routing.sh < /dev/null 2>&1 | grep -A6 "gwt\|GWT"`
Expected: the 3 new tests FAIL (current hook renders `[OK]`/`all sections present` on heading presence alone); pre-existing completeness tests still pass (fixture helpers now contract-complete).

- [ ] **Step 3: Implement the hook change**

In `hooks/skill-activation-hook.sh` replace:

```bash
      _DC_CAPS=0; _DC_OOS=0; _DC_ACC=0
      grep -Eiq '^#{2,3} .*capabilities[- ]affected' "$_DP_DESIGN" 2>/dev/null && _DC_CAPS=1
      grep -Eiq '^#{2,3} .*out[- ]of[- ]scope'       "$_DP_DESIGN" 2>/dev/null && _DC_OOS=1
      grep -Eiq '^#{2,3} .*acceptance[- ]scenarios'  "$_DP_DESIGN" 2>/dev/null && _DC_ACC=1
```

with:

```bash
      _DC_CAPS=0; _DC_OOS=0; _DC_ACC=0; _DC_ACC_HEAD=0; _DC_GWT=""
      grep -Eiq '^#{2,3} .*capabilities[- ]affected' "$_DP_DESIGN" 2>/dev/null && _DC_CAPS=1
      grep -Eiq '^#{2,3} .*out[- ]of[- ]scope'       "$_DP_DESIGN" 2>/dev/null && _DC_OOS=1
      grep -Eiq '^#{2,3} .*acceptance[- ]scenarios'  "$_DP_DESIGN" 2>/dev/null && _DC_ACC_HEAD=1
      _DC_ACC=$_DC_ACC_HEAD

      # G/W/T body check (validation-contract-hardening): the DESIGN->PLAN
      # contract promises 2-4 GIVEN/WHEN/THEN scenarios, so a bare heading
      # must not satisfy the check. When the heading exists, one awk pass
      # counts uppercase GIVEN/WHEN/THEN tokens inside the section (until
      # the next h2/h3; h4+ subsections stay inside). Case-sensitive so
      # lowercase prose ("when the user...") never counts. Contract holds
      # at min(GIVEN,WHEN,THEN) >= 2; upper bound not enforced. Fail-open:
      # awk failure or non-numeric output degrades to heading semantics.
      if [[ $_DC_ACC_HEAD -eq 1 ]]; then
        _DC_GWT="$(awk '
          /^##/ && !/^####/ {
            inacc = (tolower($0) ~ /acceptance[- ]scenarios/) ? 1 : 0
            next
          }
          inacc {
            if ($0 ~ /(^|[^A-Za-z])GIVEN([^A-Za-z]|$)/) g++
            if ($0 ~ /(^|[^A-Za-z])WHEN([^A-Za-z]|$)/)  w++
            if ($0 ~ /(^|[^A-Za-z])THEN([^A-Za-z]|$)/)  t++
          }
          END { m = g + 0; if (w + 0 < m) m = w + 0; if (t + 0 < m) m = t + 0; print m }
        ' "$_DP_DESIGN" 2>/dev/null || true)"
        if [[ "$_DC_GWT" =~ ^[0-9]+$ ]] && [[ "$_DC_GWT" -lt 2 ]]; then
          _DC_ACC=0
        fi
      fi
```

Replace the `_DC_LINE_ACC` if/else:

```bash
        if [[ $_DC_ACC -eq 1 ]]; then
          _DC_LINE_ACC='  [OK] Acceptance Scenarios'
        else
          _DC_LINE_ACC='  [X]  Acceptance Scenarios (missing — add `## Acceptance Scenarios` section)'
        fi
```

with:

```bash
        if [[ $_DC_ACC -eq 1 ]]; then
          _DC_LINE_ACC='  [OK] Acceptance Scenarios'
        elif [[ $_DC_ACC_HEAD -eq 1 ]]; then
          _DC_LINE_ACC='  [X]  Acceptance Scenarios (heading present but <2 GIVEN/WHEN/THEN scenarios — write 2-4 concrete GIVEN/WHEN/THEN scenarios)'
        else
          _DC_LINE_ACC='  [X]  Acceptance Scenarios (missing — add `## Acceptance Scenarios` section)'
        fi
```

And extend the breadcrumb line:

```bash
        echo "[skill-hook]   [design-guard] caps=${_DC_CAPS} oos=${_DC_OOS} acc=${_DC_ACC} gwt=${_DC_GWT:-n/a} bar=${_DC_BAR} path=${_DP_DESIGN}" >&2
```

- [ ] **Step 4: Syntax-check and run the suite under Bash 3.2**

Run: `/bin/bash -n hooks/skill-activation-hook.sh && /bin/bash tests/test-routing.sh < /dev/null`
Expected: syntax clean; all tests PASS including the 3 new ones.

- [ ] **Step 5: Commit**

```bash
git add tests/test-routing.sh hooks/skill-activation-hook.sh
git commit -m "feat: GIVEN/WHEN/THEN body check in PLAN-phase design guard (advisory, fail-open)"
```

---

### Task 3: Full suite, changelog, spec commit

**Files:**
- Modify: `CHANGELOG.md` (`[Unreleased]` section)
- Create (commit): `openspec/changes/validation-contract-hardening/**` (already written during DESIGN)

**Interfaces:**
- Consumes: Tasks 1-2 committed.
- Produces: green full suite; committed spec + changelog.

- [ ] **Step 1: Run the full suite**

Run: `bash tests/run-tests.sh < /dev/null`
Expected: all suites pass, exit 0.

- [ ] **Step 2: Changelog entry under `[Unreleased]`**

```markdown
### Added
- `validation-contract-hardening`: Expectation Provenance MUST rule in `runtime-validation` Step 2 (expected outcomes must trace to `eval-pack`/`intent-truth`/`generic-smoke`; the implementation never defines "correct"), and an advisory GIVEN/WHEN/THEN body check in the PLAN-phase design guard (bare `## Acceptance Scenarios` headings no longer satisfy the DESIGN→PLAN contract; fail-open, never denies).
```

- [ ] **Step 3: Commit spec + changelog**

```bash
git add openspec/changes/validation-contract-hardening CHANGELOG.md
git commit -m "docs: openspec change + changelog for validation-contract-hardening"
```
