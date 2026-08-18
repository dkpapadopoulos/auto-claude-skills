#!/usr/bin/env bash
# test-openspec-state.sh — Tests for OpenSpec session state persistence
# Bash 3.2 compatible. Sources test-helpers.sh for assertions.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

# Source the helper under test
. "${PROJECT_ROOT}/hooks/lib/openspec-state.sh"

echo "=== test-openspec-state.sh ==="

# ---------------------------------------------------------------------------
# 1. Hooks alone do not create state file
# ---------------------------------------------------------------------------
test_hooks_do_not_create_state() {
    echo "-- test: hooks alone do not create OpenSpec state file --"
    setup_test_env

    # Run session-start hook
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${PROJECT_ROOT}/hooks/session-start-hook.sh" >/dev/null 2>&1

    # Run routing hook with a prompt
    printf '{"userMessage":"ship this"}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${PROJECT_ROOT}/hooks/skill-activation-hook.sh" >/dev/null 2>&1

    # Assert no openspec state file was created
    local state_files
    state_files="$(ls "${HOME}/.claude/.skill-openspec-state-"* 2>/dev/null | wc -l | tr -d ' ')"
    assert_equals "no openspec state file created by hooks" "0" "${state_files}"

    teardown_test_env
}
test_hooks_do_not_create_state

# ---------------------------------------------------------------------------
# 2. mark_verified creates state file
# ---------------------------------------------------------------------------
test_mark_verified_creates_state() {
    echo "-- test: mark_verified creates state file --"
    setup_test_env

    local token="test-$$"
    openspec_state_mark_verified "$token" "opsx-core"

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"
    assert_equals "state file exists" "true" "$([ -f "$state_file" ] && echo true || echo false)"

    local verified
    verified="$(jq -r '.verification_seen' "$state_file" 2>/dev/null)"
    assert_equals "verification_seen is true" "true" "$verified"

    local surface
    surface="$(jq -r '.openspec_surface' "$state_file" 2>/dev/null)"
    assert_equals "openspec_surface is opsx-core" "opsx-core" "$surface"

    local changes_count
    changes_count="$(jq '.changes | length' "$state_file" 2>/dev/null)"
    assert_equals "changes map is empty" "0" "$changes_count"

    teardown_test_env
}
test_mark_verified_creates_state

# ---------------------------------------------------------------------------
# 3. upsert_change adds to changes map without overwriting
# ---------------------------------------------------------------------------
test_upsert_change_preserves_entries() {
    echo "-- test: upsert_change adds multiple entries --"
    setup_test_env

    local token="test-$$"
    # First: create state with verification
    openspec_state_mark_verified "$token" "opsx-core"

    # Add first change (with design_path)
    openspec_state_upsert_change "$token" "feature-a" "plans/a.md" "specs/a.md" "billing" "docs/plans/2026-04-15-feature-a-design.md"

    # Add second change (without design_path — backward compat)
    openspec_state_upsert_change "$token" "feature-b" "plans/b.md" "specs/b.md" "auth"

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"

    # Both entries should exist
    local count
    count="$(jq '.changes | length' "$state_file" 2>/dev/null)"
    assert_equals "two entries in changes map" "2" "$count"

    local a_plan
    a_plan="$(jq -r '.changes["feature-a"].sp_plan_path' "$state_file" 2>/dev/null)"
    assert_equals "feature-a plan preserved" "plans/a.md" "$a_plan"

    local b_cap
    b_cap="$(jq -r '.changes["feature-b"].capability_slug' "$state_file" 2>/dev/null)"
    assert_equals "feature-b capability preserved" "auth" "$b_cap"

    # Verification fields should still be intact
    local verified
    verified="$(jq -r '.verification_seen' "$state_file" 2>/dev/null)"
    assert_equals "verification still intact" "true" "$verified"

    # Canonical field names
    local design
    design="$(jq -r '.changes["feature-a"].design_path' "$state_file" 2>/dev/null)"
    assert_equals "design_path populated" "docs/plans/2026-04-15-feature-a-design.md" "$design"

    local plan_new
    plan_new="$(jq -r '.changes["feature-a"].plan_path' "$state_file" 2>/dev/null)"
    assert_equals "plan_path (canonical) populated" "plans/a.md" "$plan_new"

    local spec_new
    spec_new="$(jq -r '.changes["feature-a"].spec_path' "$state_file" 2>/dev/null)"
    assert_equals "spec_path (canonical) populated" "specs/a.md" "$spec_new"

    # Legacy aliases still readable
    local sp_plan
    sp_plan="$(jq -r '.changes["feature-a"].sp_plan_path' "$state_file" 2>/dev/null)"
    assert_equals "sp_plan_path (legacy) still set" "plans/a.md" "$sp_plan"

    teardown_test_env
}
test_upsert_change_preserves_entries

test_upsert_change_empty_args_preserve_prior_values() {
    echo "-- test: upsert with empty args preserves prior non-empty fields --"
    setup_test_env

    local token="test-$$"
    openspec_state_upsert_change "$token" "my-feature" "plans/real.md" "specs/real.md" "billing" "docs/plans/real-design.md"

    # Re-upsert with empty plan/spec/cap — simulates a caller that only wants to set design_path
    openspec_state_upsert_change "$token" "my-feature" "" "" "" "docs/plans/new-design.md"

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"

    local plan
    plan="$(jq -r '.changes["my-feature"].plan_path' "$state_file" 2>/dev/null)"
    assert_equals "plan_path preserved on empty arg" "plans/real.md" "$plan"

    local spec
    spec="$(jq -r '.changes["my-feature"].spec_path' "$state_file" 2>/dev/null)"
    assert_equals "spec_path preserved on empty arg" "specs/real.md" "$spec"

    local cap
    cap="$(jq -r '.changes["my-feature"].capability_slug' "$state_file" 2>/dev/null)"
    assert_equals "capability_slug preserved on empty arg" "billing" "$cap"

    local design
    design="$(jq -r '.changes["my-feature"].design_path' "$state_file" 2>/dev/null)"
    assert_equals "design_path updated when arg provided" "docs/plans/new-design.md" "$design"

    teardown_test_env
}
test_upsert_change_empty_args_preserve_prior_values

# ---------------------------------------------------------------------------
# 4. write_provenance produces valid source.json
# ---------------------------------------------------------------------------
test_write_provenance_produces_source_json() {
    echo "-- test: write_provenance produces valid source.json --"
    setup_test_env

    local token="test-$$"
    openspec_state_mark_verified "$token" "opsx-core"
    openspec_state_upsert_change "$token" "my-feature" "plans/my.md" "specs/my.md" "my-cap" "docs/plans/my-design.md"

    local archive_dir="${HOME}/test-archive"
    mkdir -p "$archive_dir"

    openspec_write_provenance "$archive_dir" "$token" "my-feature"

    local source_json="${archive_dir}/superpowers/source.json"
    assert_equals "source.json exists" "true" "$([ -f "$source_json" ] && echo true || echo false)"

    # Validate schema
    local schema_version
    schema_version="$(jq -r '.schema_version' "$source_json" 2>/dev/null)"
    assert_equals "schema_version is 1" "1" "$schema_version"

    local plan
    plan="$(jq -r '.sp_plan_path' "$source_json" 2>/dev/null)"
    assert_equals "sp_plan_path populated" "plans/my.md" "$plan"

    # Canonical fields in provenance
    local plan_canonical
    plan_canonical="$(jq -r '.plan_path' "$source_json" 2>/dev/null)"
    assert_equals "plan_path (canonical) in provenance" "plans/my.md" "$plan_canonical"

    local design_prov
    design_prov="$(jq -r '.design_path' "$source_json" 2>/dev/null)"
    assert_equals "design_path in provenance" "docs/plans/my-design.md" "$design_prov"

    local cap
    cap="$(jq -r '.capability_slug' "$source_json" 2>/dev/null)"
    assert_equals "capability_slug populated" "my-cap" "$cap"

    local surface
    surface="$(jq -r '.openspec_surface' "$source_json" 2>/dev/null)"
    assert_equals "openspec_surface from state" "opsx-core" "$surface"

    # base_commit should be non-null (we're in a git repo)
    local commit
    commit="$(jq -r '.base_commit' "$source_json" 2>/dev/null)"
    assert_not_contains "base_commit not null" "null" "$commit"

    teardown_test_env
}
test_write_provenance_produces_source_json

# ---------------------------------------------------------------------------
# REVIEW-before-SHIP guard tests
# ---------------------------------------------------------------------------

GUARD_HOOK="${PROJECT_ROOT}/hooks/openspec-guard.sh"

# Helper: run the guard hook with a git commit command and given state files
run_guard() {
    local session_token="$1"
    local phase="$2"
    local comp_state="$3"  # JSON string for composition state, or empty

    # Create session token
    printf '%s' "${session_token}" > "${HOME}/.claude/.skill-session-token"

    # Create signal file with phase
    jq -n --arg p "${phase}" '{skill:"test",phase:$p}' \
        > "${HOME}/.claude/.skill-last-invoked-${session_token}"

    # Create composition state if provided
    if [ -n "${comp_state}" ]; then
        printf '%s' "${comp_state}" > "${HOME}/.claude/.skill-composition-state-${session_token}"
    fi

    # Feed a git commit command to the hook
    printf '{"tool_input":{"command":"git commit -m test"}}' | \
        bash "${GUARD_HOOK}" 2>/dev/null
}

test_review_completed_no_warning() {
    echo "-- test: REVIEW completed — no review warning --"
    setup_test_env
    mkdir -p "${HOME}/.claude"

    # Fake a git repo so openspec check doesn't error
    mkdir -p "${TEST_TMPDIR}/repo/.git"
    cd "${TEST_TMPDIR}/repo"
    git init -q

    local comp='{"chain":["brainstorming","writing-plans","executing-plans","requesting-code-review","verification-before-completion","openspec-ship","finishing-a-development-branch"],"current_index":6,"completed":["brainstorming","writing-plans","executing-plans","requesting-code-review","verification-before-completion","openspec-ship"],"updated_at":"2026-03-30T10:00:00Z"}'

    local output
    output="$(run_guard "test-review-ok-$$" "SHIP" "${comp}")"

    assert_not_contains "no REVIEW warning" "REVIEW GUARD" "${output}"

    teardown_test_env
}
test_review_completed_no_warning

test_review_skipped_emits_warning() {
    echo "-- test: REVIEW skipped — emits warning --"
    setup_test_env
    mkdir -p "${HOME}/.claude"

    mkdir -p "${TEST_TMPDIR}/repo/.git"
    cd "${TEST_TMPDIR}/repo"
    git init -q

    # completed list is missing requesting-code-review
    local comp='{"chain":["brainstorming","writing-plans","executing-plans","requesting-code-review","verification-before-completion"],"current_index":4,"completed":["brainstorming","writing-plans","executing-plans"],"updated_at":"2026-03-30T10:00:00Z"}'

    local output
    output="$(run_guard "test-review-skip-$$" "SHIP" "${comp}")"

    assert_contains "REVIEW warning present" "REVIEW GUARD" "${output}"

    teardown_test_env
}
test_review_skipped_emits_warning

test_no_composition_state_no_warning() {
    echo "-- test: no composition state — no review warning --"
    setup_test_env
    mkdir -p "${HOME}/.claude"

    mkdir -p "${TEST_TMPDIR}/repo/.git"
    cd "${TEST_TMPDIR}/repo"
    git init -q

    local output
    output="$(run_guard "test-no-comp-$$" "SHIP" "")"

    assert_not_contains "no REVIEW warning without comp state" "REVIEW GUARD" "${output}"

    teardown_test_env
}
test_no_composition_state_no_warning

test_non_ship_phase_skips_guard() {
    echo "-- test: non-SHIP phase — guard exits early --"
    setup_test_env
    mkdir -p "${HOME}/.claude"

    mkdir -p "${TEST_TMPDIR}/repo/.git"
    cd "${TEST_TMPDIR}/repo"
    git init -q

    local comp='{"chain":["brainstorming","writing-plans"],"current_index":1,"completed":["brainstorming"],"updated_at":"2026-03-30T10:00:00Z"}'

    local output
    output="$(run_guard "test-non-ship-$$" "IMPLEMENT" "${comp}")"

    assert_not_contains "no warning on non-SHIP phase" "REVIEW GUARD" "${output}"

    teardown_test_env
}
test_non_ship_phase_skips_guard

# ---------------------------------------------------------------------------
# Push review gate tests (state-aware push blocking)
# ---------------------------------------------------------------------------

# Helper: run the guard hook with a git push command and given state files
# NOTE (#198): test-helpers.sh:31 exports CLAUDE_PLUGIN_ROOT="${TEST_HOME}/.claude",
# a directory that contains no plugin — so the guard invoked here loads NONE of its
# gate-enforcement libs and no gate actually runs. The "allows" cases below therefore
# exercise a fully DEGRADED guard, not the allow path of a working one. That is a
# pre-existing weakness of this harness, left as-is because pointing the root at the
# real tree would change what every setup_test_env test exercises.
#
# What changed with #198 is only that the degradation is now ANNOUNCED, so the string
# "PUSH GATE" legitimately appears on an allow. The property these cases mean to pin
# is the DECISION, so they assert on the decision channel: an advisory never carries a
# permissionDecision, and a block always does.
run_push_guard() {
    local session_token="$1"
    local phase="$2"
    local comp_state="$3"  # JSON string for composition state, or empty

    # Create session token
    printf '%s' "${session_token}" > "${HOME}/.claude/.skill-session-token"

    # Create signal file with phase
    jq -n --arg p "${phase}" '{skill:"test",phase:$p}' \
        > "${HOME}/.claude/.skill-last-invoked-${session_token}"

    # Create composition state if provided
    if [ -n "${comp_state}" ]; then
        printf '%s' "${comp_state}" > "${HOME}/.claude/.skill-composition-state-${session_token}"
    fi

    # Feed a git push command to the hook.
    #
    # CLAUDE_PLUGIN_ROOT is set EXPLICITLY at the real tree. setup_test_env
    # exports it at "${TEST_HOME}/.claude", a directory with no plugin in it —
    # correct for tests that build fake plugin trees there, wrong here: the
    # guard then loads NONE of its gate-enforcement libs, so these cases were
    # exercising a fully degraded guard rather than the push gate. Surfaced by
    # the #198 degradation advisory, which announced the dead root out loud.
    printf '{"tool_input":{"command":"git push"}}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD_HOOK}" 2>/dev/null
}

test_push_gate_blocks_unverified() {
    echo "-- test: push gate blocks when verification not completed --"
    setup_test_env
    mkdir -p "${HOME}/.claude"

    mkdir -p "${TEST_TMPDIR}/repo/.git"
    cd "${TEST_TMPDIR}/repo"
    git init -q

    # verification-before-completion in chain but NOT in completed
    local comp='{"chain":["brainstorming","writing-plans","executing-plans","requesting-code-review","verification-before-completion"],"current_index":3,"completed":["brainstorming","writing-plans","executing-plans"],"updated_at":"2026-04-16T10:00:00Z"}'

    local output
    output="$(run_push_guard "test-push-block-$$" "IMPLEMENT" "${comp}")"

    assert_contains "push gate blocks" "PUSH GATE" "${output}"
    assert_contains "push gate denies" "deny" "${output}"

    teardown_test_env
}
test_push_gate_blocks_unverified

test_push_gate_allows_verified() {
    echo "-- test: push gate allows when verification completed --"
    setup_test_env
    mkdir -p "${HOME}/.claude"

    mkdir -p "${TEST_TMPDIR}/repo/.git"
    cd "${TEST_TMPDIR}/repo"
    git init -q

    # verification-before-completion IS in completed
    local comp='{"chain":["brainstorming","writing-plans","executing-plans","requesting-code-review","verification-before-completion","openspec-ship"],"current_index":5,"completed":["brainstorming","writing-plans","executing-plans","requesting-code-review","verification-before-completion"],"updated_at":"2026-04-16T10:00:00Z"}'

    local output
    output="$(run_push_guard "test-push-allow-$$" "SHIP" "${comp}")"

    assert_not_contains "push gate allows" "permissionDecision" "${output}"
    assert_not_contains "push gate no deny" "deny" "${output}"

    teardown_test_env
}
test_push_gate_allows_verified

test_push_gate_denies_adhoc_push_without_evidence() {
    echo "-- test: push gate denies ad-hoc push (no composition, no evidence) --"
    setup_test_env
    mkdir -p "${HOME}/.claude"

    mkdir -p "${TEST_TMPDIR}/repo/.git"
    cd "${TEST_TMPDIR}/repo"
    git init -q

    local output
    output="$(run_push_guard "test-push-adhoc-$$" "IMPLEMENT" "")"

    # This case asserted the OPPOSITE until the harness root was fixed: it was
    # named "allows ad-hoc push" and passed only because the guard ran with no
    # libs loaded and no gate at all. The global fail-closed gate deliberately
    # closed that hole — a push from a non-driven session used to be allowed
    # unconditionally, and is not any more — so the old expectation had been
    # obsolete since that gate landed, silently.
    assert_contains "ad-hoc push with no evidence is denied" "deny" "${output:-<empty>}"
    assert_contains "deny names the missing review milestone" \
        "requesting-code-review" "${output:-<empty>}"
    assert_contains "deny names the missing verify milestone" \
        "verification-before-completion" "${output:-<empty>}"

    teardown_test_env
}
test_push_gate_denies_adhoc_push_without_evidence

test_push_gate_allows_no_verification_in_chain() {
    echo "-- test: push gate allows when verification not in chain --"
    setup_test_env
    mkdir -p "${HOME}/.claude"

    mkdir -p "${TEST_TMPDIR}/repo/.git"
    cd "${TEST_TMPDIR}/repo"
    git init -q

    # chain without verification-before-completion
    local comp='{"chain":["brainstorming","writing-plans"],"current_index":1,"completed":["brainstorming"],"updated_at":"2026-04-16T10:00:00Z"}'

    local output
    output="$(run_push_guard "test-push-nochain-$$" "PLAN" "${comp}")"

    # Leaving verification out of the CHAIN does not exempt the push: the
    # global fail-closed gate is chain-independent and still requires evidence
    # for this branch. Previously asserted as an allow, which only held because
    # the guard was running with no libs.
    assert_contains "chain without verification is still denied" "deny" "${output:-<empty>}"
    assert_contains "deny names verification-before-completion" \
        "verification-before-completion" "${output:-<empty>}"

    teardown_test_env
}
test_push_gate_allows_no_verification_in_chain

# Push gate must also enforce REVIEW completion, not just VERIFY. In the canonical
# SDLC chain REVIEW precedes VERIFY, and memory_feedback_never_skip_review_ship_tdd
# enshrines that REVIEW is mandatory — so pushing with REVIEW incomplete (even if
# VERIFY is somehow complete) should be blocked.
test_push_gate_blocks_unreviewed() {
    echo "-- test: push gate blocks when requesting-code-review not completed --"
    setup_test_env
    mkdir -p "${HOME}/.claude"

    mkdir -p "${TEST_TMPDIR}/repo/.git"
    cd "${TEST_TMPDIR}/repo"
    git init -q

    # REVIEW in chain, NOT completed. VERIFY also in chain, not yet reached.
    local comp='{"chain":["brainstorming","writing-plans","executing-plans","requesting-code-review","verification-before-completion"],"current_index":2,"completed":["brainstorming","writing-plans","executing-plans"],"updated_at":"2026-04-18T10:00:00Z"}'

    local output
    output="$(run_push_guard "test-push-noreview-$$" "IMPLEMENT" "${comp}")"

    assert_contains "push gate blocks unreviewed" "PUSH GATE" "${output}"
    assert_contains "push gate denies unreviewed" "deny" "${output}"
    assert_contains "message mentions REVIEW" "requesting-code-review" "${output}"

    teardown_test_env
}
test_push_gate_blocks_unreviewed

test_push_gate_allows_reviewed_without_verify_in_chain() {
    echo "-- test: push gate allows when review done and verification not in chain --"
    setup_test_env
    mkdir -p "${HOME}/.claude"

    mkdir -p "${TEST_TMPDIR}/repo/.git"
    cd "${TEST_TMPDIR}/repo"
    git init -q

    # REVIEW in chain and completed. VERIFY not in chain at all. Push should be allowed.
    local comp='{"chain":["brainstorming","writing-plans","executing-plans","requesting-code-review"],"current_index":3,"completed":["brainstorming","writing-plans","executing-plans","requesting-code-review"],"updated_at":"2026-04-18T10:00:00Z"}'

    local output
    output="$(run_push_guard "test-push-reviewonly-$$" "REVIEW" "${comp}")"

    # A completed REVIEW satisfies its own leg but not the VERIFY leg, so the
    # deny must name ONLY the missing one. That asymmetry is the useful signal
    # here and was unobservable while the guard ran with no libs.
    assert_contains     "review-only chain is still denied" "deny" "${output:-<empty>}"
    assert_contains     "deny names the missing verify milestone" \
        "verification-before-completion" "${output:-<empty>}"
    assert_not_contains "deny does NOT name the satisfied review milestone" \
        "requires requesting-code-review" "${output:-}"

    teardown_test_env
}
test_push_gate_allows_reviewed_without_verify_in_chain

# ---------------------------------------------------------------------------
# 5. set_discovery_path creates/merges discovery_path
# ---------------------------------------------------------------------------
test_set_discovery_path_creates_entry() {
    echo "-- test: set_discovery_path creates change entry --"
    setup_test_env

    local token="test-$$"
    # No prior state — should create file and change entry
    openspec_state_set_discovery_path "$token" "my-feature" "docs/plans/2026-04-17-my-feature-discovery.md"

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"
    assert_equals "state file exists" "true" "$([ -f "$state_file" ] && echo true || echo false)"

    local dp
    dp="$(jq -r '.changes["my-feature"].discovery_path' "$state_file" 2>/dev/null)"
    assert_equals "discovery_path set" "docs/plans/2026-04-17-my-feature-discovery.md" "$dp"

    teardown_test_env
}
test_set_discovery_path_creates_entry

test_set_discovery_path_merges_without_overwrite() {
    echo "-- test: set_discovery_path merges without overwriting existing fields --"
    setup_test_env

    local token="test-$$"
    # Pre-populate with upsert_change
    openspec_state_mark_verified "$token" "opsx-core"
    openspec_state_upsert_change "$token" "my-feature" "plans/my.md" "specs/my.md" "billing" "docs/plans/my-design.md"

    # Now set discovery_path — should merge, not overwrite
    openspec_state_set_discovery_path "$token" "my-feature" "docs/plans/my-discovery.md"

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"

    local dp
    dp="$(jq -r '.changes["my-feature"].discovery_path' "$state_file" 2>/dev/null)"
    assert_equals "discovery_path merged" "docs/plans/my-discovery.md" "$dp"

    local design
    design="$(jq -r '.changes["my-feature"].design_path' "$state_file" 2>/dev/null)"
    assert_equals "design_path preserved after merge" "docs/plans/my-design.md" "$design"

    local plan
    plan="$(jq -r '.changes["my-feature"].plan_path' "$state_file" 2>/dev/null)"
    assert_equals "plan_path preserved after merge" "plans/my.md" "$plan"

    local verified
    verified="$(jq -r '.verification_seen' "$state_file" 2>/dev/null)"
    assert_equals "verification still intact after merge" "true" "$verified"

    teardown_test_env
}
test_set_discovery_path_merges_without_overwrite

test_set_discovery_path_noop_on_empty_token() {
    echo "-- test: set_discovery_path no-op on empty token --"
    setup_test_env

    openspec_state_set_discovery_path "" "slug" "path.md"

    local state_files
    state_files="$(ls "${HOME}/.claude/.skill-openspec-state-"* 2>/dev/null | wc -l | tr -d ' ')"
    assert_equals "no state file created on empty token" "0" "${state_files}"

    teardown_test_env
}
test_set_discovery_path_noop_on_empty_token

# ---------------------------------------------------------------------------
# 6. set_hypotheses creates/merges hypotheses array on change entry
# ---------------------------------------------------------------------------
test_set_hypotheses_creates_entry() {
    echo "-- test: set_hypotheses creates change entry with hypotheses --"
    setup_test_env

    local token="test-$$"
    local hyps='[{"id":"H1","description":"thing works","metric":"ctr","baseline":"0.1","target":"0.2","window":"2w"}]'
    openspec_state_set_hypotheses "$token" "my-feature" "$hyps"

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"
    assert_equals "state file exists" "true" "$([ -f "$state_file" ] && echo true || echo false)"

    local id
    id="$(jq -r '.changes["my-feature"].hypotheses[0].id' "$state_file" 2>/dev/null)"
    assert_equals "H1 id stored" "H1" "$id"

    local count
    count="$(jq '.changes["my-feature"].hypotheses | length' "$state_file" 2>/dev/null)"
    assert_equals "one hypothesis" "1" "$count"

    teardown_test_env
}
test_set_hypotheses_creates_entry

test_set_hypotheses_merges_without_overwrite() {
    echo "-- test: set_hypotheses preserves discovery_path/design_path --"
    setup_test_env

    local token="test-$$"
    openspec_state_set_discovery_path "$token" "my-feature" "docs/plans/disc.md"
    openspec_state_upsert_change "$token" "my-feature" "plans/p.md" "specs/s.md" "cap" "docs/plans/d.md"

    local hyps='[{"id":"H1","description":"x","metric":"m","baseline":null,"target":null,"window":null}]'
    openspec_state_set_hypotheses "$token" "my-feature" "$hyps"

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"

    local dp
    dp="$(jq -r '.changes["my-feature"].discovery_path' "$state_file" 2>/dev/null)"
    assert_equals "discovery_path preserved" "docs/plans/disc.md" "$dp"

    local design
    design="$(jq -r '.changes["my-feature"].design_path' "$state_file" 2>/dev/null)"
    assert_equals "design_path preserved" "docs/plans/d.md" "$design"

    local id
    id="$(jq -r '.changes["my-feature"].hypotheses[0].id' "$state_file" 2>/dev/null)"
    assert_equals "hypotheses merged" "H1" "$id"

    teardown_test_env
}
test_set_hypotheses_merges_without_overwrite

test_set_hypotheses_invalid_json_noop() {
    echo "-- test: set_hypotheses no-op on invalid JSON --"
    setup_test_env

    local token="test-$$"
    openspec_state_set_hypotheses "$token" "slug" "not json {{"

    local state_files
    state_files="$(ls "${HOME}/.claude/.skill-openspec-state-"* 2>/dev/null | wc -l | tr -d ' ')"
    assert_equals "no state file on invalid JSON" "0" "${state_files}"

    teardown_test_env
}
test_set_hypotheses_invalid_json_noop

test_set_hypotheses_rejects_non_array_shape() {
    echo "-- test: set_hypotheses rejects valid JSON that isn't an array --"
    setup_test_env

    local token="test-$$"
    # Valid JSON but not an array — should be rejected since outcome-review iterates
    openspec_state_set_hypotheses "$token" "slug" '{"id":"H1"}'
    openspec_state_set_hypotheses "$token" "slug" '"a string"'
    openspec_state_set_hypotheses "$token" "slug" '42'
    openspec_state_set_hypotheses "$token" "slug" 'null'

    local state_files
    state_files="$(ls "${HOME}/.claude/.skill-openspec-state-"* 2>/dev/null | wc -l | tr -d ' ')"
    assert_equals "non-array shapes rejected" "0" "${state_files}"

    teardown_test_env
}
test_set_hypotheses_rejects_non_array_shape

test_set_hypotheses_empty_inputs_noop() {
    echo "-- test: set_hypotheses no-op on empty token/slug/json --"
    setup_test_env

    openspec_state_set_hypotheses "" "slug" "[]"
    openspec_state_set_hypotheses "t" "" "[]"
    openspec_state_set_hypotheses "t" "slug" ""

    local state_files
    state_files="$(ls "${HOME}/.claude/.skill-openspec-state-"* 2>/dev/null | wc -l | tr -d ' ')"
    assert_equals "no state file on empty inputs" "0" "${state_files}"

    teardown_test_env
}
test_set_hypotheses_empty_inputs_noop

# ---------------------------------------------------------------------------
# 7. write_learn_baseline — writes ~/.claude/.skill-learn-baselines/<slug>.json
# ---------------------------------------------------------------------------
test_write_learn_baseline_skipped_without_ship() {
    echo "-- test: write_learn_baseline skips when no ship signal --"
    setup_test_env

    local token="test-$$"
    local hyps='[{"id":"H1","description":"x","metric":"m","baseline":null,"target":null,"window":null}]'
    openspec_state_set_hypotheses "$token" "my-feature" "$hyps"
    # No archive dir, no archived_at → no ship signal
    openspec_state_write_learn_baseline "$token" "my-feature"

    local baseline_file="${HOME}/.claude/.skill-learn-baselines/my-feature.json"
    assert_equals "baseline file not created" "false" "$([ -f "$baseline_file" ] && echo true || echo false)"

    teardown_test_env
}
test_write_learn_baseline_skipped_without_ship

test_write_learn_baseline_skipped_without_hypotheses() {
    echo "-- test: write_learn_baseline skips when no hypotheses --"
    setup_test_env

    local token="test-$$"
    # Create archive dir signal (ship event) but no hypotheses
    local proj
    proj="${TEST_TMPDIR}/repo"
    mkdir -p "${proj}/openspec/changes/archive/my-feature" "${proj}/.git"
    cd "$proj"
    git init -q
    openspec_state_mark_verified "$token" "none"
    openspec_state_write_learn_baseline "$token" "my-feature"

    local baseline_file="${HOME}/.claude/.skill-learn-baselines/my-feature.json"
    assert_equals "baseline not created without hypotheses" "false" "$([ -f "$baseline_file" ] && echo true || echo false)"

    teardown_test_env
}
test_write_learn_baseline_skipped_without_hypotheses

test_write_learn_baseline_writes_on_archive_signal() {
    echo "-- test: write_learn_baseline writes when archive dir exists --"
    setup_test_env

    local token="test-$$"
    # Set up git repo + archive dir
    local proj
    proj="${TEST_TMPDIR}/repo"
    mkdir -p "${proj}/openspec/changes/archive/my-feature" "${proj}/.git"
    cd "$proj"
    git init -q
    # Write hypotheses to state
    local hyps='[{"id":"H1","description":"thing","metric":"ctr","baseline":"0.1","target":"0.2","window":"2w"}]'
    openspec_state_set_hypotheses "$token" "my-feature" "$hyps"

    openspec_state_write_learn_baseline "$token" "my-feature"

    local baseline_file="${HOME}/.claude/.skill-learn-baselines/my-feature.json"
    assert_equals "baseline file created" "true" "$([ -f "$baseline_file" ] && echo true || echo false)"

    # Check canonical fields
    local slug
    slug="$(jq -r '.slug' "$baseline_file" 2>/dev/null)"
    assert_equals "slug recorded" "my-feature" "$slug"

    local hyp_count
    hyp_count="$(jq '.hypotheses | length' "$baseline_file" 2>/dev/null)"
    assert_equals "hypotheses recorded" "1" "$hyp_count"

    local shipped_at
    shipped_at="$(jq -r '.shipped_at' "$baseline_file" 2>/dev/null)"
    assert_not_contains "shipped_at populated" "null" "$shipped_at"

    local schema
    schema="$(jq -r '.schema_version' "$baseline_file" 2>/dev/null)"
    assert_equals "schema_version present" "1" "$schema"

    teardown_test_env
}
test_write_learn_baseline_writes_on_archive_signal

test_write_learn_baseline_extracts_jira_ticket() {
    echo "-- test: write_learn_baseline extracts Jira ticket from discovery file --"
    setup_test_env

    local token="test-$$"
    local proj
    proj="${TEST_TMPDIR}/repo"
    mkdir -p "${proj}/openspec/changes/archive/my-feature" "${proj}/.git" "${proj}/docs/plans"
    cd "$proj"
    git init -q
    # Discovery file with Jira ticket
    printf '# Discovery\n\nLinked to ABC-1234 for context.\n' > "${proj}/docs/plans/disc.md"
    openspec_state_set_discovery_path "$token" "my-feature" "docs/plans/disc.md"
    local hyps='[{"id":"H1","description":"x","metric":"m","baseline":null,"target":null,"window":null}]'
    openspec_state_set_hypotheses "$token" "my-feature" "$hyps"

    openspec_state_write_learn_baseline "$token" "my-feature"

    local baseline_file="${HOME}/.claude/.skill-learn-baselines/my-feature.json"
    local jira
    jira="$(jq -r '.jira_ticket' "$baseline_file" 2>/dev/null)"
    assert_equals "jira extracted" "ABC-1234" "$jira"

    local discovery_path
    discovery_path="$(jq -r '.discovery_path' "$baseline_file" 2>/dev/null)"
    assert_equals "discovery_path recorded" "docs/plans/disc.md" "$discovery_path"

    teardown_test_env
}
test_write_learn_baseline_extracts_jira_ticket

test_write_learn_baseline_jira_ignores_false_positives() {
    echo "-- test: Jira extraction ignores HTTP-2/UTF-8/SHA-256 noise before the real ticket --"
    setup_test_env

    local token="test-$$"
    local proj
    proj="${TEST_TMPDIR}/repo"
    mkdir -p "${proj}/openspec/changes/archive/my-feature" "${proj}/.git" "${proj}/docs/plans"
    cd "$proj"
    git init -q
    # Discovery file: technical jargon appears BEFORE the Jira ticket
    printf '# Discovery\n\nUses HTTP-2 and SHA-256 per ISO-8601. Tracked as PROJ-4567.\n' \
        > "${proj}/docs/plans/disc.md"
    openspec_state_set_discovery_path "$token" "my-feature" "docs/plans/disc.md"
    local hyps='[{"id":"H1","description":"x","metric":"m","baseline":null,"target":null,"window":null}]'
    openspec_state_set_hypotheses "$token" "my-feature" "$hyps"

    openspec_state_write_learn_baseline "$token" "my-feature"

    local baseline_file="${HOME}/.claude/.skill-learn-baselines/my-feature.json"
    local jira
    jira="$(jq -r '.jira_ticket' "$baseline_file" 2>/dev/null)"
    # Must pick the real ticket (PROJ-4567), not HTTP-2 / SHA-256 / ISO-8601
    assert_equals "real Jira ticket selected over noise" "PROJ-4567" "$jira"

    teardown_test_env
}
test_write_learn_baseline_jira_ignores_false_positives

test_write_learn_baseline_uses_archived_at_from_state() {
    echo "-- test: write_learn_baseline uses archived_at from state when set --"
    setup_test_env

    local token="test-$$"
    local proj
    proj="${TEST_TMPDIR}/repo"
    mkdir -p "${proj}/.git" # intentionally no archive dir — only archived_at signals ship
    cd "$proj"
    git init -q

    local hyps='[{"id":"H1","description":"x","metric":"m","baseline":null,"target":null,"window":null}]'
    openspec_state_set_hypotheses "$token" "my-feature" "$hyps"
    openspec_state_mark_archived "$token" "my-feature" "2026-01-15T09:30:00Z"

    openspec_state_write_learn_baseline "$token" "my-feature"

    local baseline_file="${HOME}/.claude/.skill-learn-baselines/my-feature.json"
    assert_equals "baseline created via archived_at signal" "true" \
        "$([ -f "$baseline_file" ] && echo true || echo false)"

    local shipped_at
    shipped_at="$(jq -r '.shipped_at' "$baseline_file" 2>/dev/null)"
    assert_equals "shipped_at matches archived_at" "2026-01-15T09:30:00Z" "$shipped_at"

    teardown_test_env
}
test_write_learn_baseline_uses_archived_at_from_state

test_write_learn_baseline_noop_on_empty_token() {
    echo "-- test: write_learn_baseline no-op on empty token/slug --"
    setup_test_env

    openspec_state_write_learn_baseline "" "slug"
    openspec_state_write_learn_baseline "t" ""

    local baseline_count
    baseline_count="$(ls "${HOME}/.claude/.skill-learn-baselines/"*.json 2>/dev/null | wc -l | tr -d ' ')"
    assert_equals "no baseline on empty inputs" "0" "$baseline_count"

    teardown_test_env
}
test_write_learn_baseline_noop_on_empty_token

# ---------------------------------------------------------------------------
# 8. consolidation-stop hook auto-writes learn baseline
# ---------------------------------------------------------------------------
test_consolidation_stop_writes_baseline() {
    echo "-- test: consolidation-stop hook writes learn baseline on ship --"
    setup_test_env

    local token="stop-test-$$"
    # Create session token file
    printf '%s' "$token" > "${HOME}/.claude/.skill-session-token"

    # Create project with archive dir signal
    local proj
    proj="${TEST_TMPDIR}/repo"
    mkdir -p "${proj}/openspec/changes/archive/shipped-feature" "${proj}/.git"
    cd "$proj"
    git init -q
    git commit --allow-empty -q -m "init" 2>/dev/null || true

    # Populate session state with hypotheses
    local hyps='[{"id":"H1","description":"x","metric":"m","baseline":null,"target":null,"window":null}]'
    openspec_state_set_hypotheses "$token" "shipped-feature" "$hyps"

    # Write freshen consolidation marker so hook doesn't bail early on that
    local _proj_hash
    _proj_hash="$(printf '%s' "${proj}" | shasum | cut -d' ' -f1)"
    touch "${HOME}/.claude/.context-stack-consolidated-${_proj_hash}"

    # Run the consolidation-stop hook
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "${PROJECT_ROOT}/hooks/consolidation-stop.sh" >/dev/null 2>&1

    local baseline_file="${HOME}/.claude/.skill-learn-baselines/shipped-feature.json"
    assert_equals "consolidation-stop wrote baseline" "true" "$([ -f "$baseline_file" ] && echo true || echo false)"

    teardown_test_env
}
test_consolidation_stop_writes_baseline

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=============================="
echo "Tests run:    ${TESTS_RUN}"
echo "Tests passed: ${TESTS_PASSED}"
echo "Tests failed: ${TESTS_FAILED}"
echo "=============================="
if [ "${TESTS_FAILED}" -gt 0 ]; then
    echo ""
    echo "Failures:"
    printf '%s' "${FAIL_MESSAGES}"
    exit 1
else
    echo "All tests passed."
fi
