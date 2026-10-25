#!/usr/bin/env bash
# test-push-gate-review-credit.sh — the push guard's REVIEW status credits a
# RETURNED reviewer that covers the push (openspec
# review-credit-from-evidence, decisions 2, 3 and 6), and nothing wider.
#
# The widening under test is one new leg, the LAST at each REVIEW site (the
# composition-chain gate and the global fail-closed gate): the branch ledger's
# `reviewer-returned` milestone, read through hooks/lib/credited-skills.sh,
# credits only when (a) the reviewer was matched by the ALLOWLISTED
# subagent_type arm, not the description word, and (b) its recorded sha is an
# ancestor of the pushed commit with no material source change since.
#
# Every widening is tested in BOTH arms, through the REAL guard and real repos
# (memory: fixing a false block can be a bypass): each "now passes" cell has a
# near-miss twin that must keep denying, and every deny asserts WHICH text
# fired, because a deny from some other gate would satisfy a bare "deny".
#
# Also pinned: the invocation-evidence leg reads its REVIEW proxies from the
# lib (code-review / review-pr / security-review credit; an uncredited name
# does not); a missing lib NARROWS credit to the four names credited before it
# existed and announces itself (#198); and the leg adds nothing when an
# existing leg already credited (byte-identical output).
#
# Bash 3.2 compatible. Sources test-helpers.sh.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
LEDGER_LIB="${PROJECT_ROOT}/hooks/lib/branch-ledger.sh"
CREDIT_LIB="${PROJECT_ROOT}/hooks/lib/credited-skills.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-push-gate-review-credit.sh ==="

if ! command -v jq >/dev/null 2>&1; then
    _record_pass "jq unavailable — every REVIEW leg is jq-gated; skipping"
    print_summary
    exit 0
fi

# An inherited bypass would turn every deny cell into an allow-vs-allow
# comparison.
unset ACSM_SKIP_PUSH_GATE

_GIT() { git -c user.email=t@t -c user.name=t "$@"; }

# _mk_repo — a throwaway NON-routing repo (no config/default-triggers.json, so
# routing-governance stays out of the way) with an `origin` and branch
# feature/x carrying three commits:
#   C1 adds src.sh       (material)
#   C2 adds docs/a.md    (docs only — not material)
#   C3 modifies src.sh   (material)
# origin/main is fetched so a mainline base resolves. Sets REPO, ORIGIN,
# BASE, C1, C2, C3. Requires setup_test_env first.
_mk_repo() {
    REPO="${TEST_TMPDIR}/repo"
    ORIGIN="${TEST_TMPDIR}/origin.git"
    git init -q --bare "${ORIGIN}"
    git init -q -b main "${REPO}"
    printf 'base\n' > "${REPO}/README.md"
    git -C "${REPO}" add README.md
    _GIT -C "${REPO}" commit -q -m base
    git -C "${REPO}" remote add origin "${ORIGIN}"
    git -C "${ORIGIN}" fetch -q "${REPO}" main:main
    git -C "${REPO}" fetch -q origin
    BASE="$(git -C "${REPO}" rev-parse main)"
    git -C "${REPO}" checkout -q -b feature/x
    printf 'echo one\n' > "${REPO}/src.sh"
    git -C "${REPO}" add src.sh
    _GIT -C "${REPO}" commit -q -m c1
    C1="$(git -C "${REPO}" rev-parse HEAD)"
    mkdir -p "${REPO}/docs"
    printf 'doc\n' > "${REPO}/docs/a.md"
    git -C "${REPO}" add docs/a.md
    _GIT -C "${REPO}" commit -q -m c2
    C2="$(git -C "${REPO}" rev-parse HEAD)"
    printf 'echo two\n' > "${REPO}/src.sh"
    git -C "${REPO}" add src.sh
    _GIT -C "${REPO}" commit -q -m c3
    C3="$(git -C "${REPO}" rev-parse HEAD)"
}

# _ledger <milestone> <sha|""> [tag] — written by the REAL producer, keyed from
# the repo's CURRENT branch (as the writer hooks key on their cwd+branch).
_ledger() {
    ( cd "${REPO}" && . "${LEDGER_LIB}" && \
        branch_ledger_record "$1" "${REPO}" "$2" "${3:-}" )
}

_TOK="session-conv-X"
_PAYLOAD='{"transcript_path":"/tmp/proj/conv-X.jsonl","tool_input":{"command":"git push origin HEAD"}}'

# _chain — composition state with REVIEW and VERIFY in the chain, neither
# completed, so every REVIEW credit must come from another leg.
_chain() {
    printf '{"chain":["requesting-code-review","verification-before-completion"],"completed":[]}\n' \
        > "${HOME}/.claude/.skill-composition-state-${_TOK}"
}

# _evidence <json-array> — the session-local invocation-evidence file.
_evidence() {
    printf '%s\n' "$1" > "${HOME}/.claude/.skill-invocation-evidence-${_TOK}"
}

# _fresh — a new sandbox HOME + repo, VERIFY satisfied at HEAD, chain present.
_fresh() {
    setup_test_env
    mkdir -p "${HOME}/.claude"
    _mk_repo
    _ledger verification-before-completion ""
    _chain
}

# _run [plugin-root] — the REAL guard, from inside the repo.
_run() {
    ( cd "${REPO}" && printf '%s' "${_PAYLOAD}" | \
        CLAUDE_PLUGIN_ROOT="${1:-${PROJECT_ROOT}}" /bin/bash "${GUARD}" 2>/dev/null )
}
_decision() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null; }
_reason()   { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null; }
_ctx()      { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }

_CHAIN_DENY="requesting-code-review has not run"
_GLOBAL_DENY="PUSH GATE (fail-closed)"
_RR_NOTE="accepted via a returned reviewer"

# _assert_pass <label> <out> — no deny AND the guard said something (an empty
# output is also "no deny", and is what a guard that never ran prints).
_assert_pass() {
    assert_not_empty "$1: guard produced output" "$2"
    assert_equals "$1: no deny" "none" "$(_decision "$2")"
}
# _assert_deny <label> <out> <expected deny text>
_assert_deny() {
    assert_equals "$1: denied" "deny" "$(_decision "$2")"
    assert_contains "$1: denied by the expected gate" "$3" "$(_reason "$2")"
}

# ---------------------------------------------------------------------------
# R0: harness controls. With NO review evidence the push denies at the chain
# gate; with a requesting-code-review ledger record it passes. Without these
# two, every cell below could be measuring a broken fixture.
# ---------------------------------------------------------------------------
echo "--- R0: harness controls ---"
_fresh
_out="$(_run)"
_assert_deny "R0a no review evidence" "${_out}" "${_CHAIN_DENY}"
_ledger requesting-code-review ""
_out="$(_run)"
_assert_pass "R0b requesting-code-review ledger record at HEAD" "${_out}"
teardown_test_env

# ---------------------------------------------------------------------------
# R1-R6, R12, R13: the reviewer leg at the composition-chain gate.
# ---------------------------------------------------------------------------
echo "--- R1: allowlisted reviewer at HEAD credits ---"
_fresh
_ledger reviewer-returned "${C3}" "arm=allowlist"
_out="$(_run)"
_assert_pass "R1 allowlisted reviewer at HEAD, no other evidence" "${_out}"
assert_contains "R1 the acceptance is announced" "${_RR_NOTE}" "$(_ctx "${_out}")"
assert_contains "R1 the announcement names the reviewed sha" "${C3}" "$(_ctx "${_out}")"
# Both sites consult the leg here (the chain gate, then the global gate, which
# has no other review record either); the note must appear once.
assert_equals "R1 the announcement appears once though both gates consulted the leg" "1" \
    "$(_ctx "${_out}" | grep -o "${_RR_NOTE}" | wc -l | tr -d ' ')"
teardown_test_env

echo "--- R2: description-matched reviewer does not credit ---"
_fresh
_ledger reviewer-returned "${C3}" "arm=description"
_out="$(_run)"
_assert_deny "R2 description arm at HEAD" "${_out}" "${_CHAIN_DENY}"
teardown_test_env

echo "--- R3: legacy untagged reviewer does not credit ---"
_fresh
_ledger reviewer-returned "${C3}" ""
assert_equals "R3 fixture: the record really is two-field" "2" \
    "$( ( cd "${REPO}" && . "${LEDGER_LIB}" && cat "$(branch_ledger_dir "${REPO}")/reviewer-returned" ) | awk '{print NF}')"
_out="$(_run)"
_assert_deny "R3 legacy two-field record at HEAD" "${_out}" "${_CHAIN_DENY}"
teardown_test_env

echo "--- R4/R5: coverage is ancestor AND no material change since ---"
_fresh
_ledger reviewer-returned "${C1}" "arm=allowlist"
_out="$(_run)"
_assert_deny "R4 reviewed C1, material change (C3) since" "${_out}" "${_CHAIN_DENY}"
teardown_test_env

_fresh
git -C "${REPO}" reset -q --hard "${C2}"
_ledger verification-before-completion ""
_ledger reviewer-returned "${C1}" "arm=allowlist"
_out="$(_run)"
_assert_pass "R5 reviewed C1, only docs (C2) since" "${_out}"
assert_contains "R5 the acceptance is announced" "${_RR_NOTE}" "$(_ctx "${_out}")"
teardown_test_env

echo "--- R6: a sha that is not an ancestor does not credit ---"
_fresh
git -C "${REPO}" checkout -q -b side main
printf 'x\n' > "${REPO}/side.sh"
git -C "${REPO}" add side.sh
_GIT -C "${REPO}" commit -q -m side
_SIDE="$(git -C "${REPO}" rev-parse HEAD)"
git -C "${REPO}" checkout -q feature/x
_ledger reviewer-returned "${_SIDE}" "arm=allowlist"
_out="$(_run)"
_assert_deny "R6 reviewed a sibling-branch commit" "${_out}" "${_CHAIN_DENY}"
teardown_test_env

echo "--- R6b: an unknown-commit sha (the '-' sentinel) does not credit ---"
_fresh
_ledger reviewer-returned "-" "arm=allowlist"
assert_contains "R6b fixture: the record carries the '-' sentinel" "- " \
    "$( ( cd "${REPO}" && . "${LEDGER_LIB}" && cat "$(branch_ledger_dir "${REPO}")/reviewer-returned" ) )"
_out="$(_run)"
_assert_deny "R6b '-' sha (dispatch-time commit unknown)" "${_out}" "${_CHAIN_DENY}"
teardown_test_env

echo "--- R12: a reviewer recorded under another branch's ledger key ---"
_fresh
git -C "${REPO}" checkout -q -b task/1
_ledger reviewer-returned "${C3}" "arm=allowlist"
git -C "${REPO}" checkout -q feature/x
_out="$(_run)"
_assert_deny "R12 reviewer on task/1, push from feature/x" "${_out}" "${_CHAIN_DENY}"
teardown_test_env

echo "--- R13: a merge bringing in material source un-covers the review ---"
_fresh
_ledger reviewer-returned "${C3}" "arm=allowlist"
_out="$(_run)"
_assert_pass "R13 control: covering reviewer before the merge" "${_out}"
git -C "${REPO}" checkout -q main
printf 'lib\n' > "${REPO}/lib.sh"
git -C "${REPO}" add lib.sh
_GIT -C "${REPO}" commit -q -m mainlib
git -C "${REPO}" checkout -q feature/x
_GIT -C "${REPO}" merge -q --no-edit main
_ledger verification-before-completion ""
_out="$(_run)"
_assert_deny "R13 merge of main adding lib.sh after the review" "${_out}" "${_CHAIN_DENY}"
teardown_test_env

# ---------------------------------------------------------------------------
# R7: the global fail-closed gate (no composition state at all).
# ---------------------------------------------------------------------------
echo "--- R7: the global fail-closed gate ---"
_fresh
rm -f "${HOME}/.claude/.skill-composition-state-${_TOK}"
_out="$(_run)"
_assert_deny "R7 control: no review evidence, no composition state" "${_out}" "${_GLOBAL_DENY}"
_ledger reviewer-returned "${C3}" "arm=allowlist"
_out="$(_run)"
_assert_pass "R7a covering allowlisted reviewer, no composition state" "${_out}"
assert_contains "R7a the acceptance is announced" "${_RR_NOTE}" "$(_ctx "${_out}")"
_ledger reviewer-returned "${C1}" "arm=allowlist"
_out="$(_run)"
_assert_deny "R7b reviewer at C1 with material change since" "${_out}" "${_GLOBAL_DENY}"
_ledger reviewer-returned "${C3}" "arm=description"
_out="$(_run)"
_assert_deny "R7c description arm at HEAD" "${_out}" "${_GLOBAL_DENY}"
_ledger reviewer-returned "-" "arm=allowlist"
_out="$(_run)"
_assert_deny "R7d '-' sha" "${_out}" "${_GLOBAL_DENY}"
_ledger reviewer-returned "${C3}" ""
_out="$(_run)"
_assert_deny "R7e legacy untagged record" "${_out}" "${_GLOBAL_DENY}"
teardown_test_env

# ---------------------------------------------------------------------------
# R8: the lib missing NARROWS credit and announces itself (#198).
# A copy of the plugin tree without credited-skills.sh; every other lib intact.
# ---------------------------------------------------------------------------
echo "--- R8: credited-skills.sh missing ---"
_fresh
_NOLIB="${TEST_TMPDIR}/nolib"
mkdir -p "${_NOLIB}"
cp -R "${PROJECT_ROOT}/hooks" "${_NOLIB}/hooks"
cp -R "${PROJECT_ROOT}/config" "${_NOLIB}/config" 2>/dev/null || true
rm -f "${_NOLIB}/hooks/lib/credited-skills.sh"
if [ -f "${_NOLIB}/hooks/lib/branch-ledger.sh" ] && [ ! -f "${_NOLIB}/hooks/lib/credited-skills.sh" ]; then
    _record_pass "R8 fixture: copy has the ledger lib and lacks credited-skills.sh"
else
    _record_fail "R8 fixture: copy has the ledger lib and lacks credited-skills.sh" "copy is wrong"
fi
_ledger reviewer-returned "${C3}" "arm=allowlist"
_out="$(_run "${_NOLIB}")"
_assert_deny "R8a covering reviewer, lib missing" "${_out}" "${_CHAIN_DENY}"
_out="$(_run)"
_assert_pass "R8a control: same state, lib present" "${_out}"
rm -f "$( cd "${REPO}" && . "${LEDGER_LIB}" && branch_ledger_dir "${REPO}" )/reviewer-returned"
_evidence '["code-review"]'
_out="$(_run "${_NOLIB}")"
_assert_deny "R8b invocation evidence code-review, lib missing" "${_out}" "${_CHAIN_DENY}"
_out="$(_run)"
_assert_pass "R8b control: code-review evidence, lib present" "${_out}"
_evidence '["agent-team-review"]'
_out="$(_run "${_NOLIB}")"
_assert_pass "R8c agent-team-review evidence (one of the four), lib missing" "${_out}"
assert_contains "R8c the degradation is announced" "credited-skills.sh did not load" "$(_ctx "${_out}")"
assert_contains "R8c …and says it can only add a deny" "can only add a deny, never remove one" "$(_ctx "${_out}")"
_out="$(_run)"
assert_not_contains "R8c control: no degradation note with the lib present" \
    "credited-skills.sh did not load" "$(_ctx "${_out}")"
teardown_test_env

# ---------------------------------------------------------------------------
# R9: invocation evidence reads its REVIEW proxies from the lib.
# ---------------------------------------------------------------------------
echo "--- R9: invocation-evidence proxies come from the lib ---"
for _nm in security-review code-review review-pr requesting-code-review subagent-driven-development agent-team-execution agent-team-review; do
    _fresh
    _evidence "[\"${_nm}\"]"
    _out="$(_run)"
    _assert_pass "R9 invocation evidence [${_nm}]" "${_out}"
    assert_contains "R9 [${_nm}] acceptance is announced" "session-local invocation evidence" "$(_ctx "${_out}")"
    teardown_test_env
done
for _nm in simplify verification-before-completion code-reviewer; do
    _fresh
    _evidence "[\"${_nm}\"]"
    _out="$(_run)"
    _assert_deny "R9 control: invocation evidence [${_nm}] does not credit REVIEW" "${_out}" "${_CHAIN_DENY}"
    teardown_test_env
done
# A scalar file merely containing a credited name must not credit (the type
# guard the four-name jq carried).
_fresh
printf '"security-review"\n' > "${HOME}/.claude/.skill-invocation-evidence-${_TOK}"
_out="$(_run)"
_assert_deny "R9 control: a scalar evidence file does not credit" "${_out}" "${_CHAIN_DENY}"
teardown_test_env

# ---------------------------------------------------------------------------
# R10: the leg adds nothing when an existing leg already credited.
# ---------------------------------------------------------------------------
echo "--- R10: the reviewer leg is inert when another leg credits ---"
_fresh
_ledger requesting-code-review ""
_without="$(_run)"
assert_equals "R10 control: output is stable across runs" "${_without}" "$(_run)"
_ledger reviewer-returned "${C3}" "arm=allowlist"
_with="$(_run)"
_assert_pass "R10 both ledger record and covering reviewer" "${_with}"
assert_equals "R10 output byte-identical with and without the reviewer record" "${_without}" "${_with}"
assert_not_contains "R10 the reviewer note is absent" "${_RR_NOTE}" "$(_ctx "${_with}")"
teardown_test_env

# ---------------------------------------------------------------------------
# R11: structure (ruling F6). Every existing REVIEW leg stays where and as it
# was; the reviewer leg is added ONCE per site, immediately after that site's
# last existing REVIEW leg (_bridge_has).
# ---------------------------------------------------------------------------
echo "--- R11: the reviewer leg is the last leg at both sites ---"
_line_after() {   # <fixed-string> — prints the line after the unique match
    awk -v n="$1" 'f { print; exit } index($0, n) { f = 1 }' "${GUARD}"
}
_count_fixed() { grep -cF -- "$1" "${GUARD}"; }
_CHAIN_LEGS='jq -e '"'"'.completed | index("requesting-code-review")'"'"' "${_COMP_STATE}" >/dev/null 2>&1 && _review_completed=true
_ledger_has "requesting-code-review" && _review_completed=true
[ "${_review_completed}" = "false" ] && _invoc_ok "requesting-code-review" && _review_completed=true
[ "${_review_completed}" = "false" ] && _bridge_has "requesting-code-review" && _review_completed=true
[ "${_review_completed}" = "false" ] && _rr_ok && _review_completed=true'
_got="$(grep -F '_review_completed=true' "${GUARD}" | sed 's/^[[:space:]]*//')"
assert_equals "R11a the chain site: four existing legs unchanged, reviewer leg last" "${_CHAIN_LEGS}" "${_got}"
assert_equals "R11b the global site: the line after the review bridge leg is the reviewer leg" \
    '[ "${_g_review}" = "false" ] && _rr_ok && _g_review=true' \
    "$(_line_after '[ "${_g_review}" = "false" ] && _bridge_has "requesting-code-review"' | sed 's/^[[:space:]]*//')"
for _leg in 'branch_ledger_has "requesting-code-review"         "${_proot}" && _g_review=true' \
            'jq -e '"'"'.completed | index("requesting-code-review")'"'"'         "${_COMP_STATE}" >/dev/null 2>&1 && _g_review=true' \
            '[ "${_g_review}" = "false" ] && _invoc_ok "requesting-code-review"         && _g_review=true' \
            '[ "${_g_review}" = "false" ] && _bridge_has "requesting-code-review"         && _g_review=true'; do
    assert_equals "R11c existing global leg present verbatim: ${_leg%% &&*}" "1" "$(_count_fixed "${_leg}")"
done
assert_equals "R11d _g_review=true has exactly five legs" "5" "$(_count_fixed '_g_review=true')"
assert_equals "R11e _rr_ok is called at exactly two sites" "2" "$(grep -c '&& _rr_ok &&' "${GUARD}")"

# ---------------------------------------------------------------------------
# R14: the guard probes the lib on its LAST definition, so a load that stopped
# part way reads as "not loaded".
# ---------------------------------------------------------------------------
echo "--- R14: the probe symbol is the lib's last definition ---"
_LAST="$(grep -E '^[a-z_]+\(\) \{' "${CREDIT_LIB}" | tail -1 | sed 's/().*//')"
_PROBE="$(grep -A3 'credited-skills.sh"' "${GUARD}" | grep -o 'command -v [a-z_]*' | head -1 | sed 's/command -v //')"
assert_not_empty "R14 found the lib's last definition" "${_LAST}"
assert_equals "R14 the guard's probe names it" "${_LAST}" "${_PROBE}"

# ---------------------------------------------------------------------------
# R15: the shared-list obligations (CLAUDE.md "Obligations that no rule file
# can deliver"): a new guard-sourced gate lib joins _GATE_ENFORCE_LIBS, and the
# #192 runtime matrix covers it.
# ---------------------------------------------------------------------------
echo "--- R15: gate-lib obligations ---"
_GEL="$(grep '^_GATE_ENFORCE_LIBS=' "${PROJECT_ROOT}/hooks/session-start-hook.sh")"
assert_contains "R15a _GATE_ENFORCE_LIBS lists credited-skills.sh" "hooks/lib/credited-skills.sh" "${_GEL}"
assert_contains "R15b the #192 runtime matrix covers credited-skills.sh" "credited-skills.sh" \
    "$(grep '^_LIBS=' "${SCRIPT_DIR}/test-hook-source-guard-runtime.sh")"

print_summary
