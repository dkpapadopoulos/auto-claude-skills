#!/usr/bin/env bash
# test-push-gate-status-bridge.sh — Regression: issue #131, STATUS-layer
# cross-location evidence resolution.
#
# The push gate's STATUS layer (REVIEW/VERIFY milestones) false-blocked under
# concurrent-session token scattering + worktree/cwd splits (PR #130 live
# repro): milestones landed in locations the gate never read. Fixes under
# test:
#   1. skill-completion-hook.sh records gating milestones to the branch-ledger
#      even when no composition state exists for the resolved token.
#   2. openspec-guard.sh accepts same-token .skill-invocation-evidence-<token>
#      records (real-Skill-return-only writer) as a session-local fallback.
#   3. branch_ledger_bridge_has accepts sibling-ledger milestones ONLY when
#      the recorded SHA is HEAD or a branch-local ancestor of HEAD — mainline
#      or unrelated SHAs never bridge (no over-acceptance).
#
# Issue #133 follow-up (soft SHA-binding + advisory dedup), also under test:
#   4. skill-completion-hook.sh records "<skill> <sha>" to the sidecar
#      .skill-invocation-evidence-sha-<token> (the main JSON string array is
#      shared with phase-evidence.sh and stays format-frozen).
#   5. The guard's invocation-evidence leg PREFERS branch-bound sidecar
#      records (same binding rule as the ledger bridge) but NEVER requires
#      them — a hard SHA requirement would re-break the #130 repro.
#   6. The invocation-evidence advisory is appended once per milestone even
#      when both the chain block and the global gate consult the leg.
#
# Bash 3.2 compatible. Sources test-helpers.sh.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
COMPLETION="${PROJECT_ROOT}/hooks/skill-completion-hook.sh"
LEDGER_LIB="${PROJECT_ROOT}/hooks/lib/branch-ledger.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-push-gate-status-bridge.sh ==="

# Every evidence leg under test is jq-gated (writer and reader); without jq
# the gate falls open by design ("jq optional at runtime") — skip.
if ! command -v jq >/dev/null 2>&1; then
    _record_pass "jq unavailable — evidence legs are jq-gated; skipping"
    print_summary
    exit 0
fi

# _mk_repo <dir> — throwaway repo: main (2 commits) + feature/x (2 commits,
# so feature/x~1 is a branch-local NON-HEAD ancestor — the bridge's central
# accept path). NOT a routing repo (no config/default-triggers.json), so the
# guard's routing-governance gate stays out of the way and the STATUS layer
# is isolated. Prints nothing; callers read back SHAs with git -C.
_mk_repo() {
    git init -q -b main "$1" &&
    git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base &&
    git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m main2 &&
    git -C "$1" checkout -q -b feature/x &&
    git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m local1 &&
    git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m local2
}

# run_guard_in <repo-dir> — guard sees a git push from inside <repo-dir> with
# transcript-derived token session-conv-X.
_PAYLOAD='{"transcript_path":"/tmp/proj/conv-X.jsonl","tool_input":{"command":"git push origin HEAD"}}'
_TOK="session-conv-X"
run_guard_in() {
    ( cd "$1" && printf '%s' "${_PAYLOAD}" | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${GUARD}" 2>/dev/null )
}

# ---------------------------------------------------------------------------
# U: branch_ledger_bridge_has unit checks (lib-level binding rules)
# ---------------------------------------------------------------------------
echo "--- U: branch_ledger_bridge_has binding ---"
setup_test_env
mkdir -p "${HOME}/.claude"
REPO="${TEST_TMPDIR}/repo"
_mk_repo "${REPO}"
BASE_SHA="$(git -C "${REPO}" rev-parse main)"
LOCAL_SHA="$(git -C "${REPO}" rev-parse feature/x)"
# shellcheck disable=SC1090
. "${LEDGER_LIB}"
if ! command -v branch_ledger_bridge_has >/dev/null 2>&1; then
    _record_fail "U0: branch_ledger_bridge_has exists in branch-ledger.sh" "function not defined"
else
    _record_pass "U0: branch_ledger_bridge_has exists in branch-ledger.sh"
    _SIB="${HOME}/.claude/.skill-branch-ledger-foreignkey000000000000000000000000000000"
    mkdir -p "${_SIB}"

    printf '%s 2026-01-01T00:00:00Z\n' "${LOCAL_SHA}" > "${_SIB}/requesting-code-review"
    if branch_ledger_bridge_has "requesting-code-review" "${REPO}"; then
        _record_pass "U1: branch-local SHA (== HEAD) bridges"
    else
        _record_fail "U1: branch-local SHA (== HEAD) bridges" "returned non-zero"
    fi

    printf '%s 2026-01-01T00:00:00Z\n' "${BASE_SHA}" > "${_SIB}/requesting-code-review"
    if branch_ledger_bridge_has "requesting-code-review" "${REPO}"; then
        _record_fail "U2: mainline-base SHA does NOT bridge" "over-accepted mainline evidence"
    else
        _record_pass "U2: mainline-base SHA does NOT bridge"
    fi

    printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef 2026-01-01T00:00:00Z\n' > "${_SIB}/requesting-code-review"
    if branch_ledger_bridge_has "requesting-code-review" "${REPO}"; then
        _record_fail "U3: unknown SHA does NOT bridge" "over-accepted unrelated evidence"
    else
        _record_pass "U3: unknown SHA does NOT bridge"
    fi

    rm -f "${_SIB}/requesting-code-review"
    if branch_ledger_bridge_has "verification-before-completion" "${REPO}"; then
        _record_fail "U4: absent milestone does NOT bridge" "accepted with no evidence"
    else
        _record_pass "U4: absent milestone does NOT bridge"
    fi

    # U5: the central ancestor-accept path — a branch-local commit that is
    # NOT HEAD (feature/x~1) must bridge via the merge-base logic, not the
    # exact-HEAD short-circuit.
    ANC_SHA="$(git -C "${REPO}" rev-parse feature/x~1)"
    printf '%s 2026-01-01T00:00:00Z\n' "${ANC_SHA}" > "${_SIB}/requesting-code-review"
    if branch_ledger_bridge_has "requesting-code-review" "${REPO}" >/dev/null; then
        _record_pass "U5: branch-local NON-HEAD ancestor bridges"
    else
        _record_fail "U5: branch-local NON-HEAD ancestor bridges" "returned non-zero"
    fi
fi
teardown_test_env

# U6: no mainline base resolvable (single branch, no remote) — the bridge
# degrades to exact-HEAD-only: ancestors must NOT bridge, HEAD must.
echo "--- U6: no-mainline-base degradation ---"
setup_test_env
mkdir -p "${HOME}/.claude"
REPO="${TEST_TMPDIR}/lone"
git init -q -b work "${REPO}"
git -C "${REPO}" -c user.email=t@t -c user.name=t commit -q --allow-empty -m one
git -C "${REPO}" -c user.email=t@t -c user.name=t commit -q --allow-empty -m two
# shellcheck disable=SC1090
. "${LEDGER_LIB}"
_SIB="${HOME}/.claude/.skill-branch-ledger-foreignkey000000000000000000000000000000"
mkdir -p "${_SIB}"
printf '%s 2026-01-01T00:00:00Z\n' "$(git -C "${REPO}" rev-parse HEAD~1)" > "${_SIB}/requesting-code-review"
if branch_ledger_bridge_has "requesting-code-review" "${REPO}" >/dev/null; then
    _record_fail "U6a: no-base repo — ancestor does NOT bridge (exact-HEAD only)" "over-accepted"
else
    _record_pass "U6a: no-base repo — ancestor does NOT bridge (exact-HEAD only)"
fi
printf '%s 2026-01-01T00:00:00Z\n' "$(git -C "${REPO}" rev-parse HEAD)" > "${_SIB}/requesting-code-review"
if branch_ledger_bridge_has "requesting-code-review" "${REPO}" >/dev/null; then
    _record_pass "U6b: no-base repo — exact HEAD still bridges"
else
    _record_fail "U6b: no-base repo — exact HEAD still bridges" "returned non-zero"
fi
teardown_test_env

# U7: @{upstream} must not shadow the mainline base (review finding #2). A
# feature branch tracking origin/<itself> (standard `git push -u`) with
# origin/HEAD unset (remote-add + fetch, not clone) makes
# merge-base HEAD @{upstream} the branch's own pushed tip — consulting it
# before mainline refs excludes legitimately branch-local commits.
echo "--- U7: upstream self-tracking does not shadow mainline base ---"
setup_test_env
mkdir -p "${HOME}/.claude"
REPO="${TEST_TMPDIR}/up"; BARE="${TEST_TMPDIR}/bare.git"
git init -q --bare "${BARE}"
git init -q -b main "${REPO}"
git -C "${REPO}" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
git -C "${REPO}" remote add origin "${BARE}"
git -C "${REPO}" push -q origin main
git -C "${REPO}" checkout -q -b feature/y
git -C "${REPO}" -c user.email=t@t -c user.name=t commit -q --allow-empty -m f1
git -C "${REPO}" push -q -u origin feature/y 2>/dev/null
git -C "${REPO}" -c user.email=t@t -c user.name=t commit -q --allow-empty -m f2
# origin/HEAD is deliberately unset (remote-add, not clone). Milestone at f1:
# branch-local (not on main), pushed (== upstream tip).
F1_SHA="$(git -C "${REPO}" rev-parse feature/y~1)"
# shellcheck disable=SC1090
. "${LEDGER_LIB}"
_SIB="${HOME}/.claude/.skill-branch-ledger-foreignkey000000000000000000000000000000"
mkdir -p "${_SIB}"
printf '%s 2026-01-01T00:00:00Z\n' "${F1_SHA}" > "${_SIB}/requesting-code-review"
if branch_ledger_bridge_has "requesting-code-review" "${REPO}" >/dev/null; then
    _record_pass "U7: pushed branch-local commit bridges despite self-tracking upstream"
else
    _record_fail "U7: pushed branch-local commit bridges despite self-tracking upstream" \
        "@{upstream} shadowed the mainline base"
fi
teardown_test_env

# ---------------------------------------------------------------------------
# H: completion hook records gating milestones WITHOUT composition state
# ---------------------------------------------------------------------------
echo "--- H: state-independent gating-milestone ledger write ---"
setup_test_env
mkdir -p "${HOME}/.claude"
REPO="${TEST_TMPDIR}/repo"
_mk_repo "${REPO}"
# No .skill-composition-state-* exists for the token — the scattering case.
( cd "${REPO}" && printf '%s' '{"transcript_path":"/tmp/proj/conv-X.jsonl","tool_input":{"skill":"superpowers:requesting-code-review"},"tool_response":{"content":"ok"}}' | \
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${COMPLETION}" >/dev/null 2>&1 ) || true
# Resolve the dir the same way the hook does — from inside the repo, letting
# git report the toplevel (macOS mktemp paths are symlinks: /var vs
# /private/var — a logical-path key would miss the hook's physical-path key).
_DIR="$( cd "${REPO}" && . "${LEDGER_LIB}" && branch_ledger_dir )"
if [ -n "${_DIR}" ] && [ -f "${_DIR}/requesting-code-review" ]; then
    _record_pass "H1: milestone recorded to branch-ledger despite missing composition state"
else
    _record_fail "H1: milestone recorded to branch-ledger despite missing composition state" \
        "no ledger record under ${_DIR:-<unresolved>}"
fi
assert_file_exists "H2: invocation evidence written (existing behavior)" \
    "${HOME}/.claude/.skill-invocation-evidence-${_TOK}"
teardown_test_env

# ---------------------------------------------------------------------------
# G: guard-level scenarios (fail-closed global gate)
# ---------------------------------------------------------------------------
echo "--- G: guard evidence legs ---"

# G1 baseline: no evidence anywhere -> DENY (fail-closed preserved)
setup_test_env
mkdir -p "${HOME}/.claude"
REPO="${TEST_TMPDIR}/repo"
_mk_repo "${REPO}"
G1="$(run_guard_in "${REPO}")"
assert_contains "G1: no evidence => fail-closed deny preserved" '"deny"' "${G1:-<empty>}"
teardown_test_env

# G2: the PR #130 repro — ledger + .completed empty, but the SAME token's
# invocation evidence carries both gating skills -> must ALLOW
setup_test_env
mkdir -p "${HOME}/.claude"
REPO="${TEST_TMPDIR}/repo"
_mk_repo "${REPO}"
printf '%s' '["requesting-code-review","verification-before-completion"]' \
    > "${HOME}/.claude/.skill-invocation-evidence-${_TOK}"
G2="$(run_guard_in "${REPO}")"
assert_not_contains "G2: same-token invocation evidence satisfies the gate (repro rescue)" '"deny"' "${G2:-}"
assert_contains "G2: invocation-leg acceptance is advisory-noted, never silent" 'invocation evidence' "${G2:-<empty>}"
teardown_test_env

# G2b: a corrupt evidence file holding a JSON *string* (not array) whose text
# merely CONTAINS the milestone names must not satisfy the gate — jq's
# index() on strings is substring search (review finding #4).
setup_test_env
mkdir -p "${HOME}/.claude"
REPO="${TEST_TMPDIR}/repo"
_mk_repo "${REPO}"
printf '%s' '"requesting-code-review-and-verification-before-completion-notes"' \
    > "${HOME}/.claude/.skill-invocation-evidence-${_TOK}"
G2B="$(run_guard_in "${REPO}")"
assert_contains "G2b: non-array evidence file does NOT satisfy the gate" '"deny"' "${G2B:-<empty>}"
teardown_test_env

# G3: invocation evidence with only non-gating skills -> deny stands
setup_test_env
mkdir -p "${HOME}/.claude"
REPO="${TEST_TMPDIR}/repo"
_mk_repo "${REPO}"
printf '%s' '["brainstorming","writing-plans"]' \
    > "${HOME}/.claude/.skill-invocation-evidence-${_TOK}"
G3="$(run_guard_in "${REPO}")"
assert_contains "G3: non-gating invocation evidence does NOT satisfy the gate" '"deny"' "${G3:-<empty>}"
teardown_test_env

# G4: review-embedding proxy (agent-team-execution) credits the REVIEW leg,
# matching the ledger writer's crediting; verify leg via the literal skill.
setup_test_env
mkdir -p "${HOME}/.claude"
REPO="${TEST_TMPDIR}/repo"
_mk_repo "${REPO}"
printf '%s' '["agent-team-execution","verification-before-completion"]' \
    > "${HOME}/.claude/.skill-invocation-evidence-${_TOK}"
G4="$(run_guard_in "${REPO}")"
assert_not_contains "G4: review-embedding proxy credits REVIEW leg" '"deny"' "${G4:-}"
teardown_test_env

# G5: cross-location ledger bridge — milestones only under a foreign key,
# recorded at the push branch's local HEAD -> ALLOW + advisory
setup_test_env
mkdir -p "${HOME}/.claude"
REPO="${TEST_TMPDIR}/repo"
_mk_repo "${REPO}"
LOCAL_SHA="$(git -C "${REPO}" rev-parse feature/x)"
_SIB="${HOME}/.claude/.skill-branch-ledger-foreignkey000000000000000000000000000000"
mkdir -p "${_SIB}"
printf '%s 2026-01-01T00:00:00Z\n' "${LOCAL_SHA}" > "${_SIB}/requesting-code-review"
printf '%s 2026-01-01T00:00:00Z\n' "${LOCAL_SHA}" > "${_SIB}/verification-before-completion"
G5="$(run_guard_in "${REPO}")"
assert_not_contains "G5: branch-bound foreign-key ledger evidence bridges" '"deny"' "${G5:-}"
assert_contains "G5: bridge acceptance surfaces an advisory" 'cross-location' "${G5:-<empty>}"
assert_contains "G5: bridge advisory names the recorded SHA" "${LOCAL_SHA}" "${G5:-<empty>}"
teardown_test_env

# G6: foreign-key ledger evidence at the MAINLINE base SHA -> deny stands
setup_test_env
mkdir -p "${HOME}/.claude"
REPO="${TEST_TMPDIR}/repo"
_mk_repo "${REPO}"
BASE_SHA="$(git -C "${REPO}" rev-parse main)"
_SIB="${HOME}/.claude/.skill-branch-ledger-foreignkey000000000000000000000000000000"
mkdir -p "${_SIB}"
printf '%s 2026-01-01T00:00:00Z\n' "${BASE_SHA}" > "${_SIB}/requesting-code-review"
printf '%s 2026-01-01T00:00:00Z\n' "${BASE_SHA}" > "${_SIB}/verification-before-completion"
G6="$(run_guard_in "${REPO}")"
assert_contains "G6: mainline-SHA foreign evidence does NOT bridge (no over-acceptance)" '"deny"' "${G6:-<empty>}"
teardown_test_env

# G7: chain block — composition state lists both gates, .completed empty, but
# invocation evidence has them (skill returned before the chain re-anchor).
setup_test_env
mkdir -p "${HOME}/.claude"
REPO="${TEST_TMPDIR}/repo"
_mk_repo "${REPO}"
jq -n '{chain:["requesting-code-review","verification-before-completion"],completed:[],current_index:0}' \
    > "${HOME}/.claude/.skill-composition-state-${_TOK}"
printf '%s' '["requesting-code-review","verification-before-completion"]' \
    > "${HOME}/.claude/.skill-invocation-evidence-${_TOK}"
G7="$(run_guard_in "${REPO}")"
assert_not_contains "G7: chain block honors same-token invocation evidence" '"deny"' "${G7:-}"
teardown_test_env

# ---------------------------------------------------------------------------
# U8: branch_ledger_sha_is_branch_local — extracted binding predicate
# (issue #133). Same rules the bridge enforces, callable per-SHA so the
# guard's invocation leg can reuse it without duplicating base resolution.
# ---------------------------------------------------------------------------
echo "--- U8: branch_ledger_sha_is_branch_local predicate ---"
setup_test_env
mkdir -p "${HOME}/.claude"
REPO="${TEST_TMPDIR}/repo"
_mk_repo "${REPO}"
BASE_SHA="$(git -C "${REPO}" rev-parse main)"
HEAD_SHA="$(git -C "${REPO}" rev-parse feature/x)"
ANC_SHA="$(git -C "${REPO}" rev-parse feature/x~1)"
# shellcheck disable=SC1090
. "${LEDGER_LIB}"
if ! command -v branch_ledger_sha_is_branch_local >/dev/null 2>&1; then
    _record_fail "U8a: branch_ledger_sha_is_branch_local exists in branch-ledger.sh" "function not defined"
else
    _record_pass "U8a: branch_ledger_sha_is_branch_local exists in branch-ledger.sh"
    _MB="$(_branch_ledger_mainline_base "${REPO}")" || _MB=""
    if branch_ledger_sha_is_branch_local "${HEAD_SHA}" "${REPO}" "${HEAD_SHA}" "${_MB}"; then
        _record_pass "U8b: exact HEAD is branch-local"
    else
        _record_fail "U8b: exact HEAD is branch-local" "returned non-zero"
    fi
    if branch_ledger_sha_is_branch_local "${ANC_SHA}" "${REPO}" "${HEAD_SHA}" "${_MB}"; then
        _record_pass "U8c: branch-local NON-HEAD ancestor is branch-local"
    else
        _record_fail "U8c: branch-local NON-HEAD ancestor is branch-local" "returned non-zero"
    fi
    if branch_ledger_sha_is_branch_local "${BASE_SHA}" "${REPO}" "${HEAD_SHA}" "${_MB}"; then
        _record_fail "U8d: mainline-base SHA is NOT branch-local" "over-accepted mainline SHA"
    else
        _record_pass "U8d: mainline-base SHA is NOT branch-local"
    fi
    if branch_ledger_sha_is_branch_local "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "${REPO}" "${HEAD_SHA}" "${_MB}"; then
        _record_fail "U8e: unknown SHA is NOT branch-local" "over-accepted unrelated SHA"
    else
        _record_pass "U8e: unknown SHA is NOT branch-local"
    fi
    # Empty base (no mainline resolvable) => exact-HEAD only, like the bridge.
    if branch_ledger_sha_is_branch_local "${ANC_SHA}" "${REPO}" "${HEAD_SHA}" ""; then
        _record_fail "U8f: empty base — ancestor NOT accepted (exact-HEAD only)" "over-accepted"
    else
        _record_pass "U8f: empty base — ancestor NOT accepted (exact-HEAD only)"
    fi
    if branch_ledger_sha_is_branch_local "${HEAD_SHA}" "${REPO}" "${HEAD_SHA}" ""; then
        _record_pass "U8g: empty base — exact HEAD still accepted"
    else
        _record_fail "U8g: empty base — exact HEAD still accepted" "returned non-zero"
    fi
fi
teardown_test_env

# ---------------------------------------------------------------------------
# H3: completion hook writes the "<skill> <sha>" sidecar (issue #133)
# ---------------------------------------------------------------------------
echo "--- H3: sidecar SHA record write ---"
setup_test_env
mkdir -p "${HOME}/.claude"
REPO="${TEST_TMPDIR}/repo"
_mk_repo "${REPO}"
HEAD_SHA="$(git -C "${REPO}" rev-parse HEAD)"
( cd "${REPO}" && printf '%s' '{"transcript_path":"/tmp/proj/conv-X.jsonl","tool_input":{"skill":"superpowers:requesting-code-review"},"tool_response":{"content":"ok"}}' | \
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${COMPLETION}" >/dev/null 2>&1 ) || true
_SIDECAR="${HOME}/.claude/.skill-invocation-evidence-sha-${_TOK}"
if [ -f "${_SIDECAR}" ] && grep -qxF "requesting-code-review ${HEAD_SHA}" "${_SIDECAR}" 2>/dev/null; then
    _record_pass "H3a: sidecar records '<skill> <sha>' at the recording cwd's HEAD"
else
    _record_fail "H3a: sidecar records '<skill> <sha>' at the recording cwd's HEAD" \
        "no 'requesting-code-review ${HEAD_SHA}' line in ${_SIDECAR}"
fi
# The main evidence file must stay a plain JSON string array (shared with
# phase-evidence.sh) — the sidecar must never change its format.
if jq -e 'type=="array" and (map(type=="string") | all)' \
    "${HOME}/.claude/.skill-invocation-evidence-${_TOK}" >/dev/null 2>&1; then
    _record_pass "H3b: main evidence file format unchanged (plain string array)"
else
    _record_fail "H3b: main evidence file format unchanged (plain string array)" \
        "main file is no longer a plain string array"
fi
# Re-running the hook at the same HEAD must not duplicate the sidecar line.
( cd "${REPO}" && printf '%s' '{"transcript_path":"/tmp/proj/conv-X.jsonl","tool_input":{"skill":"superpowers:requesting-code-review"},"tool_response":{"content":"ok"}}' | \
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${COMPLETION}" >/dev/null 2>&1 ) || true
_N="$(grep -cxF "requesting-code-review ${HEAD_SHA}" "${_SIDECAR}" 2>/dev/null || printf '0')"
if [ "${_N}" = "1" ]; then
    _record_pass "H3c: identical '<skill> <sha>' pair not duplicated"
else
    _record_fail "H3c: identical '<skill> <sha>' pair not duplicated" "count=${_N}, want 1"
fi
teardown_test_env

# ---------------------------------------------------------------------------
# D: advisory dedup — chain block + global gate both consult the invocation
# leg; the advisory must appear ONCE per milestone (PR #134 review disposition)
# ---------------------------------------------------------------------------
echo "--- D: invocation-evidence advisory dedup ---"
setup_test_env
mkdir -p "${HOME}/.claude"
REPO="${TEST_TMPDIR}/repo"
_mk_repo "${REPO}"
jq -n '{chain:["requesting-code-review","verification-before-completion"],completed:[],current_index:0}' \
    > "${HOME}/.claude/.skill-composition-state-${_TOK}"
printf '%s' '["requesting-code-review","verification-before-completion"]' \
    > "${HOME}/.claude/.skill-invocation-evidence-${_TOK}"
D1="$(run_guard_in "${REPO}")"
assert_not_contains "D1a: chain + global gate both satisfied (allow)" '"deny"' "${D1:-}"
_N="$(printf '%s' "${D1:-}" | grep -o 'requesting-code-review accepted via session-local invocation evidence' | wc -l | tr -d '[:space:]')"
if [ "${_N}" = "1" ]; then
    _record_pass "D1b: REVIEW invocation advisory appears exactly once"
else
    _record_fail "D1b: REVIEW invocation advisory appears exactly once" "count=${_N}, want 1"
fi
_N="$(printf '%s' "${D1:-}" | grep -o 'verification-before-completion accepted via session-local invocation evidence' | wc -l | tr -d '[:space:]')"
if [ "${_N}" = "1" ]; then
    _record_pass "D1c: VERIFY invocation advisory appears exactly once"
else
    _record_fail "D1c: VERIFY invocation advisory appears exactly once" "count=${_N}, want 1"
fi
teardown_test_env

# ---------------------------------------------------------------------------
# G8-G10: soft SHA-binding at the guard (issue #133)
# ---------------------------------------------------------------------------
echo "--- G8: bound sidecar record upgrades the advisory ---"
setup_test_env
mkdir -p "${HOME}/.claude"
REPO="${TEST_TMPDIR}/repo"
_mk_repo "${REPO}"
LOCAL_SHA="$(git -C "${REPO}" rev-parse feature/x)"
printf '%s' '["requesting-code-review","verification-before-completion"]' \
    > "${HOME}/.claude/.skill-invocation-evidence-${_TOK}"
printf 'requesting-code-review %s\nverification-before-completion %s\n' "${LOCAL_SHA}" "${LOCAL_SHA}" \
    > "${HOME}/.claude/.skill-invocation-evidence-sha-${_TOK}"
G8="$(run_guard_in "${REPO}")"
assert_not_contains "G8a: bound invocation evidence satisfies the gate" '"deny"' "${G8:-}"
assert_contains "G8b: advisory says the record is branch-bound" 'SHA-bound' "${G8:-<empty>}"
assert_contains "G8c: advisory names the recorded SHA" "${LOCAL_SHA}" "${G8:-<empty>}"
assert_not_contains "G8d: unbound-advisory text is replaced, not appended" 'not branch-bound' "${G8:-}"
teardown_test_env

# G9: sidecar SHA from the mainline base (a different-branch recording) must
# NOT block — binding is SOFT: acceptance stands, the unbound advisory stays.
# A hard SHA requirement here would re-break the #130 repro (the recording
# cwd's SHA is unrelated to the push branch when session cwd != worktree).
# The sidecar also carries garbage lines (extra fields, missing SHA, unknown
# skill) — the reader must tolerate them without denying or crashing.
echo "--- G9: unbound sidecar record still accepted (soft binding) ---"
setup_test_env
mkdir -p "${HOME}/.claude"
REPO="${TEST_TMPDIR}/repo"
_mk_repo "${REPO}"
BASE_SHA="$(git -C "${REPO}" rev-parse main)"
printf '%s' '["requesting-code-review","verification-before-completion"]' \
    > "${HOME}/.claude/.skill-invocation-evidence-${_TOK}"
{
    printf 'not json at all\n'
    printf 'requesting-code-review\n'
    printf 'requesting-code-review %s trailing junk fields\n' "${BASE_SHA}"
    printf 'verification-before-completion %s\n' "${BASE_SHA}"
} > "${HOME}/.claude/.skill-invocation-evidence-sha-${_TOK}"
G9="$(run_guard_in "${REPO}")"
assert_not_contains "G9a: unbound sidecar SHA does NOT deny (soft binding)" '"deny"' "${G9:-}"
assert_contains "G9b: unbound acceptance keeps the not-branch-bound advisory" 'not branch-bound' "${G9:-<empty>}"
teardown_test_env

# G11: red-team pin of the CRITICAL invariant — the sidecar alone (even with
# a perfectly branch-bound SHA) must NEVER satisfy the gate. Acceptance
# authority is the main string array only; the sidecar merely annotates.
echo "--- G11: sidecar alone does not satisfy the gate ---"
setup_test_env
mkdir -p "${HOME}/.claude"
REPO="${TEST_TMPDIR}/repo"
_mk_repo "${REPO}"
LOCAL_SHA="$(git -C "${REPO}" rev-parse feature/x)"
# NO main invocation-evidence array — only the sidecar, bound to HEAD.
printf 'requesting-code-review %s\nverification-before-completion %s\n' "${LOCAL_SHA}" "${LOCAL_SHA}" \
    > "${HOME}/.claude/.skill-invocation-evidence-sha-${_TOK}"
G11="$(run_guard_in "${REPO}")"
assert_contains "G11: bound sidecar WITHOUT the main array still denies" '"deny"' "${G11:-<empty>}"
teardown_test_env

# G10: review-embedding proxy name in the sidecar binds the REVIEW leg —
# the sidecar lookup honors the same proxy list as _invoc_has (PAIRED).
echo "--- G10: proxy sidecar record binds the REVIEW leg ---"
setup_test_env
mkdir -p "${HOME}/.claude"
REPO="${TEST_TMPDIR}/repo"
_mk_repo "${REPO}"
LOCAL_SHA="$(git -C "${REPO}" rev-parse feature/x)"
printf '%s' '["agent-team-execution","verification-before-completion"]' \
    > "${HOME}/.claude/.skill-invocation-evidence-${_TOK}"
printf 'agent-team-execution %s\nverification-before-completion %s\n' "${LOCAL_SHA}" "${LOCAL_SHA}" \
    > "${HOME}/.claude/.skill-invocation-evidence-sha-${_TOK}"
G10="$(run_guard_in "${REPO}")"
assert_not_contains "G10a: proxy-bound evidence satisfies the gate" '"deny"' "${G10:-}"
assert_contains "G10b: REVIEW advisory is branch-bound via the proxy record" 'SHA-bound' "${G10:-<empty>}"
teardown_test_env

print_summary
