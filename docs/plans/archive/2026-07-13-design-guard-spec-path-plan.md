# Design-Guard Spec-Path Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `[OK] Acceptance Scenarios` reachable for spec-driven changes by falling back to sibling `specs/*/spec.md` WHEN/THEN counting when the design-file check fails.

**Architecture:** One strictly-additive block in the DESIGN COMPLETENESS section of `hooks/skill-activation-hook.sh` — runs only when `_DC_ACC=0`, globs `<design_dir>/specs/*/spec.md`, counts aggregated uppercase WHEN/THEN tokens (GIVEN not required — OpenSpec template makes it optional), `min >= 2` flips to a distinct `[OK] ... (in sibling specs/)`. Spec: `openspec/changes/design-guard-spec-path/`.

**Tech Stack:** Bash 3.2 (macOS `/bin/bash`), BSD awk, existing test-routing.sh harness.

## Global Constraints

- Bash 3.2 / BSD-awk safe: no associative arrays, no awk interval expressions; `/bin/bash -n` + run suites under `/bin/bash` with `< /dev/null`.
- Guard stays advisory-only and fail-open: the new block may only flip `[X]→[OK]`; every error path degrades to the design-file verdict.
- Work in a per-feature worktree (main tree has unrelated staged files).
- Note: when caps+oos+acc are all satisfied the guard renders the "all sections present" one-liner, NOT per-line `[OK]` lines — tests for the sibling-specs annotation must leave one other section missing.

---

### Task 1: Spec-path fallback (TDD)

**Files:**
- Modify: `tests/test-routing.sh` (3 new tests after `test_plan_completeness_gwt_h3_grouping_closes_section`)
- Modify: `hooks/skill-activation-hook.sh` (after the G/W/T body-check block ~line 1560; `_DC_LINE_ACC` rendering; breadcrumb)

**Interfaces:**
- Consumes: `_seed_plan_state`, `_write_design_fixture_raw`, `run_hook`, `extract_context`, assert helpers; hook globals `_DC_ACC`, `_DC_ACC_HEAD`, `_DP_DESIGN`.
- Produces: `_DC_ACC_SPECS` (0/1), `_DC_SPEC_WT` (aggregated min count), message `  [OK] Acceptance Scenarios (in sibling specs/)`, breadcrumb field `gwt_specs=`.

- [ ] **Step 1: Write the three failing tests**

Insert after `test_plan_completeness_gwt_h3_grouping_closes_section` in `tests/test-routing.sh`:

```bash
test_plan_completeness_specpath_satisfies_perline() {
    echo "-- test: DESIGN COMPLETENESS accepts scenarios from sibling specs/ (per-line render) --"
    setup_test_env
    install_registry

    local token="plan-guard-specpath-$$"
    local dir="${HOME}/change-specpath"
    mkdir -p "${dir}/specs/cap-a"
    # Spec-driven shape: design.md has caps but NO acceptance heading and NO
    # oos (oos missing keeps the per-line render so the annotation is visible).
    _write_design_fixture_raw "${dir}/design.md" '## Capabilities Affected'
    # GIVEN-less bold WHEN/THEN — the OpenSpec template shape (load-bearing:
    # requiring GIVEN would false-[X] template-conformant specs).
    cat > "${dir}/specs/cap-a/spec.md" << 'EOSPEC'
### Requirement: sample
#### Scenario: first
- **WHEN** a thing happens
- **THEN** an outcome is observed
#### Scenario: second
- **WHEN** another thing happens
- **THEN** another outcome is observed
EOSPEC
    _seed_plan_state "${token}" "fixture-slug" "${dir}/design.md"

    printf '{"skill":"brainstorming","phase":"DESIGN"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output context
    output="$(run_hook "let us plan this out")"
    context="$(extract_context "${output}")"

    assert_contains "acceptance satisfied via specs" \
        "Acceptance Scenarios (in sibling specs/)" "${context}"
    assert_not_contains "no missing-acceptance message" \
        "Acceptance Scenarios (missing" "${context}"
    assert_contains "oos still flagged" "Out-of-Scope (missing" "${context}"

    teardown_test_env
}
test_plan_completeness_specpath_satisfies_perline

test_plan_completeness_specpath_all_present() {
    echo "-- test: DESIGN COMPLETENESS all-present via sibling specs --"
    setup_test_env
    install_registry

    local token="plan-guard-specpath-all-$$"
    local dir="${HOME}/change-specpath-all"
    mkdir -p "${dir}/specs/cap-a"
    _write_design_fixture_raw "${dir}/design.md" \
        '## Capabilities Affected' \
        '## Out-of-Scope'
    cat > "${dir}/specs/cap-a/spec.md" << 'EOSPEC'
#### Scenario: first
- **WHEN** a thing happens
- **THEN** an outcome is observed
#### Scenario: second
- **WHEN** another thing happens
- **THEN** another outcome is observed
EOSPEC
    _seed_plan_state "${token}" "fixture-slug" "${dir}/design.md"

    printf '{"skill":"brainstorming","phase":"DESIGN"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output context
    output="$(run_hook "let us plan this out")"
    context="$(extract_context "${output}")"

    assert_contains "all sections present via specs" "all sections present" "${context}"
    assert_not_contains "nothing flagged missing" "(missing" "${context}"

    teardown_test_env
}
test_plan_completeness_specpath_all_present

test_plan_completeness_specpath_thin_specs_stay_flagged() {
    echo "-- test: DESIGN COMPLETENESS thin sibling specs do not flip the verdict --"
    setup_test_env
    install_registry

    local token="plan-guard-specpath-thin-$$"
    local dir="${HOME}/change-specpath-thin"
    mkdir -p "${dir}/specs/cap-a"
    _write_design_fixture_raw "${dir}/design.md" \
        '## Capabilities Affected' \
        '## Out-of-Scope'
    # Only ONE WHEN/THEN pair -> min(WHEN,THEN)=1 < 2 -> no flip.
    cat > "${dir}/specs/cap-a/spec.md" << 'EOSPEC'
#### Scenario: only
- **WHEN** a thing happens
- **THEN** an outcome is observed
EOSPEC
    _seed_plan_state "${token}" "fixture-slug" "${dir}/design.md"

    printf '{"skill":"brainstorming","phase":"DESIGN"}' \
        > "${HOME}/.claude/.skill-last-invoked-${token}"

    local output context
    output="$(run_hook "let us plan this out")"
    context="$(extract_context "${output}")"

    assert_contains "acceptance still flagged missing" \
        "Acceptance Scenarios (missing" "${context}"
    assert_not_contains "no specs annotation" "in sibling specs/" "${context}"

    teardown_test_env
}
test_plan_completeness_specpath_thin_specs_stay_flagged
```

(No new test for "no specs dir": every pre-existing design-guard fixture lacks a `specs/` sibling, so the entire existing test population locks that path.)

- [ ] **Step 2: Run to verify the new tests fail**

Run: `/bin/bash tests/test-routing.sh < /dev/null 2>&1 | grep -A5 "sibling specs"`
Expected: tests 1 and 2 FAIL (acceptance renders `(missing`); test 3 PASSES (locks current semantics as a guard).

- [ ] **Step 3: Implement the fallback**

In `hooks/skill-activation-hook.sh`, insert immediately after the closing `fi` of the G/W/T body-check block (the one ending `_DC_ACC=0; fi; fi`):

```bash
      # Spec-path fallback (design-guard-spec-path): in spec-driven mode the
      # scenarios live in sibling specs/<cap>/spec.md files, not design.md —
      # without this, [OK] is unreachable for spec-driven changes (measured:
      # 8/10 real docs permanently [X] in the PR #105 dogfood). Satisfied
      # when sibling specs carry >=2 aggregated WHEN/THEN pairs. GIVEN is
      # deliberately NOT required — the OpenSpec scenario template makes it
      # optional. Strictly additive: only flips [X]->[OK]; any error path
      # (no specs dir, empty glob, awk failure, non-numeric output)
      # degrades to the design-file verdict above.
      _DC_ACC_SPECS=0; _DC_SPEC_WT=""
      if [[ $_DC_ACC -eq 0 ]]; then
        _DP_DIR="${_DP_DESIGN%/*}"
        if [[ -d "${_DP_DIR}/specs" ]]; then
          _DC_SPEC_WT="$(cat "${_DP_DIR}"/specs/*/spec.md 2>/dev/null | awk '
            {
              if ($0 ~ /(^|[^A-Za-z])WHEN([^A-Za-z]|$)/) w++
              if ($0 ~ /(^|[^A-Za-z])THEN([^A-Za-z]|$)/) t++
            }
            END { m = w + 0; if (t + 0 < m) m = t + 0; print m }
          ' 2>/dev/null || true)"
          if [[ "$_DC_SPEC_WT" =~ ^[0-9]+$ ]] && [[ "$_DC_SPEC_WT" -ge 2 ]]; then
            _DC_ACC=1
            _DC_ACC_SPECS=1
          fi
        fi
      fi
```

Replace the `_DC_LINE_ACC` rendering chain's first branch:

```bash
        if [[ $_DC_ACC -eq 1 ]]; then
          _DC_LINE_ACC='  [OK] Acceptance Scenarios'
```

with:

```bash
        if [[ $_DC_ACC -eq 1 ]] && [[ ${_DC_ACC_SPECS:-0} -eq 1 ]]; then
          _DC_LINE_ACC='  [OK] Acceptance Scenarios (in sibling specs/)'
        elif [[ $_DC_ACC -eq 1 ]]; then
          _DC_LINE_ACC='  [OK] Acceptance Scenarios'
```

And extend the breadcrumb:

```bash
        echo "[skill-hook]   [design-guard] caps=${_DC_CAPS} oos=${_DC_OOS} acc=${_DC_ACC} gwt=${_DC_GWT:-n/a} gwt_closed_by_heading=${_DC_GWT_CLOSED:-n/a} gwt_filewide=${_DC_GWT_FILE:-n/a} gwt_specs=${_DC_SPEC_WT:-n/a} bar=${_DC_BAR} path=${_DP_DESIGN}" >&2
```

- [ ] **Step 4: Verify green under Bash 3.2**

Run: `/bin/bash -n hooks/skill-activation-hook.sh && /bin/bash tests/test-routing.sh < /dev/null`
Expected: syntax clean; all tests pass including the 3 new ones.

- [ ] **Step 5: Commit**

```bash
git add tests/test-routing.sh hooks/skill-activation-hook.sh
git commit -m "feat: design guard accepts acceptance scenarios from sibling spec-driven specs/"
```

---

### Task 2: Corpus validation, changelog, ship prep

**Files:**
- Modify: `CHANGELOG.md` (`[Unreleased]`)
- Commit: `openspec/changes/design-guard-spec-path/**` (needs `git add -f`, openspec/ is gitignored)

**Interfaces:**
- Consumes: Task 1 committed.
- Produces: dogfood corpus re-run evidence; green full suite; committed spec + changelog.

- [ ] **Step 1: Re-run the dogfood corpus**

Re-run the sandboxed corpus loop from the dogfood session (fixture registry, per-doc state seed, hook from this worktree) over `openspec/changes/*/design.md`.
Expected: active spec-driven changes whose specs carry >=2 WHEN/THEN pairs now render `[OK] Acceptance Scenarios (in sibling specs/)` (or `all sections present` where caps+oos also exist); docs with genuinely thin specs stay `[X]`.

- [ ] **Step 2: Full suite**

Run: `bash tests/run-tests.sh < /dev/null`
Expected: 85/85 files pass.

- [ ] **Step 3: Changelog entry under `[Unreleased]` → `### Fixed`**

```markdown
- **Design guard: `[OK] Acceptance Scenarios` is now reachable in spec-driven mode.** The PR #105 dogfood measured 8/10 real design docs rendering a permanent `[X]` because spec-driven changes keep scenarios in sibling `specs/<cap>/spec.md` files the guard never read. When the design-file check fails, the guard now counts aggregated uppercase WHEN/THEN tokens across `<design_dir>/specs/*/spec.md` (GIVEN not required — the OpenSpec scenario template makes it optional) and `min >= 2` renders a distinct `[OK] Acceptance Scenarios (in sibling specs/)`. Strictly additive and fail-open: only flips `[X]→[OK]`; errors degrade to the design-file verdict. Spec: `openspec/changes/design-guard-spec-path/`. Capability: `skill-routing`.
```

- [ ] **Step 4: Commit spec + changelog**

```bash
git add CHANGELOG.md && git add -f openspec/changes/design-guard-spec-path
git commit -m "docs: openspec change + changelog for design-guard-spec-path"
```
