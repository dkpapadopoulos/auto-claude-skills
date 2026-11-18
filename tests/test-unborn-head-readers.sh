#!/usr/bin/env bash
# test-unborn-head-readers.sh — #435 item 2: the readers of HEAD on the push
# gate's reading side.
#
# In a repository with no commits a bare `git rev-parse HEAD` PRINTS the word
# HEAD before failing, so `$(git rev-parse HEAD 2>/dev/null || true)` holds
# "HEAD", not "". #432 made the ledger and verdict readers refuse a recorded
# value that is not a full object name, so that word could no longer earn
# credit; the four sites below now do not produce it either.
#
# What this file can and cannot show. The guard's output for a push from such
# a repository was byte-identical before and after the change in the four
# evidence states below (measured against the base guard, 2026-11-18), so the
# behavioural cells pin the outcome and do NOT go red if a site is reverted.
# The static cells are the ones a revert fails. The two states that are not
# denied are the chain's own `.completed` satisfying REVIEW and VERIFY, which
# predates this change and needs no commit.
#
# Bash 3.2 compatible.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
LEDGER_LIB="${PROJECT_ROOT}/hooks/lib/branch-ledger.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-unborn-head-readers.sh ==="

if ! command -v jq >/dev/null 2>&1; then
    _record_pass "jq unavailable — the push gate is jq-gated; skipping"
    print_summary
    exit 0
fi

unset ACSM_SKIP_PUSH_GATE

# ---------------------------------------------------------------------------
# S: no reading-side site resolves HEAD with the bare form. Comment lines are
# dropped first, since the comments at these sites name the bare form.
# ---------------------------------------------------------------------------
echo "--- S: static ---"
_code() { grep -v '^[[:space:]]*#' "$1"; }
for _f in hooks/openspec-guard.sh scripts/gate-status.sh hooks/lib/review-verdict.sh; do
    _bare="$(_code "${PROJECT_ROOT}/${_f}" | grep -cE 'rev-parse HEAD([^~^]|$)')"
    assert_equals "S ${_f}: no bare rev-parse HEAD" "0" "${_bare}"
done
assert_equals "S the guard resolves HEAD with --verify --quiet at both sites" "2" \
    "$(_code "${GUARD}" | grep -cE 'rev-parse --verify --quiet HEAD')"
assert_equals "S gate-status.sh resolves HEAD with --verify --quiet" "1" \
    "$(_code "${PROJECT_ROOT}/scripts/gate-status.sh" | grep -cE 'rev-parse --verify --quiet HEAD')"
assert_equals "S review-verdict.sh resolves HEAD with --verify --quiet" "1" \
    "$(_code "${PROJECT_ROOT}/hooks/lib/review-verdict.sh" | grep -cE 'rev-parse --verify --quiet HEAD')"

# ---------------------------------------------------------------------------
# P: the premise, on this git. If a future git stops printing the word, the
# cells above guard nothing and this says so.
# ---------------------------------------------------------------------------
echo "--- P: premise ---"
setup_test_env
mkdir -p "${HOME}/.claude"
REPO="${TEST_TMPDIR}/unborn"
git init -q -b main "${REPO}" 2>/dev/null || git init -q "${REPO}"
assert_equals "P a bare rev-parse HEAD prints the word in a repo with no commits" "HEAD" \
    "$(git -C "${REPO}" rev-parse HEAD 2>/dev/null || true)"
assert_equals "P --verify --quiet prints nothing there" "" \
    "$(git -C "${REPO}" rev-parse --verify --quiet HEAD 2>/dev/null || true)"

# ---------------------------------------------------------------------------
# U: a push from that repository gets the decision it got before, in each
# evidence state, and no message names the word HEAD as a commit.
# ---------------------------------------------------------------------------
echo "--- U: the real guard, repo with no commits ---"
_TOK="session-conv-U"
_PAYLOAD='{"session_id":"sess-U1","tool_use_id":"toolu_01Unb","transcript_path":"/tmp/proj/conv-U.jsonl","tool_input":{"command":"git push origin HEAD"}}'
_chain() {
    printf '{"chain":["requesting-code-review","verification-before-completion"],"completed":%s}\n' \
        "$1" > "${HOME}/.claude/.skill-composition-state-${_TOK}"
}
_run() {
    ( cd "${REPO}" && printf '%s' "${_PAYLOAD}" | \
        env PUSH_GATE_CAPTURE_DISABLE=1 CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${GUARD}" 2>/dev/null )
}
_cell() { # <label> <expected decision: deny|none>
    local _o _d; _o="$(_run)"
    if [ -n "${_o}" ]; then
        _d="$(printf '%s' "${_o}" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null)"
    else
        _d="none"
    fi
    assert_equals "U $1: decision is $2" "$2" "${_d}"
    case "${_o}" in
        *"HEAD is HEAD"*|*"at HEAD,"*) _record_fail "U $1: no message names the word HEAD as a commit" "got: ${_o}" ;;
        *) _record_pass "U $1: no message names the word HEAD as a commit" ;;
    esac
}
_chain '[]'
_cell "no evidence" deny
( cd "${REPO}" && . "${LEDGER_LIB}" \
    && branch_ledger_record requesting-code-review "${REPO}" "" \
    && branch_ledger_record verification-before-completion "${REPO}" "" )
_cell "ledger milestones recorded with no commit" deny
_chain '["requesting-code-review","verification-before-completion"]'
_cell "chain completed, ledger milestones recorded" none
rm -rf "${HOME}/.claude/.skill-branch-ledger-"*
_cell "chain completed, no ledger" none

# gate-status.sh reads the same repository without printing the word as a sha.
_gs="$( cd "${REPO}" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${PROJECT_ROOT}/scripts/gate-status.sh" < /dev/null 2>&1 )"
case "${_gs}" in
    *"PUSH GATE STATUS"*) _record_pass "U gate-status.sh runs in a repo with no commits" ;;
    *) _record_fail "U gate-status.sh runs in a repo with no commits" "got: ${_gs}" ;;
esac
case "${_gs}" in
    *"sha HEAD"*|*"(= HEAD)"*) _record_fail "U gate-status.sh does not report the word HEAD as a verified sha" "got: ${_gs}" ;;
    *) _record_pass "U gate-status.sh does not report the word HEAD as a verified sha" ;;
esac
teardown_test_env

print_summary
