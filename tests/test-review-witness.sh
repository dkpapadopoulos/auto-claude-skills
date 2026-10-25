#!/usr/bin/env bash
# test-review-witness.sh — REVIEW shadow records carry the harness stamps, a
# `review_witness` and a `review_coverage` under predicate 3 / schema 3
# (openspec review-credit-from-evidence, decision 4; requirement "Shadow
# records carry harness ids, versions and review coverage").
#
# Every cell drives the REAL guard to the Check 1b record (chain contains
# REVIEW, REVIEW status satisfied, a push touching material source, no clean
# bound review verdict) in a throwaway repo, and reads the record the REAL
# producer wrote. The witness rule under test:
#   candidates, in order: reviewer-returned (allowlisted arm, through the lib)
#   > verdict (a clean review verdict) > invocation (REVIEW status credited by
#   a leg other than the reviewer leg); the first candidate whose coverage is
#   `covered` wins, else the first present, else none/none.
#
# Also pinned: computing the witness adds nothing to the guard's output; it
# runs only when a record is about to be written; out-of-vocabulary arguments
# are recorded as "invalid"; and a predicate-3 record round-trips through the
# real reader while predicate-2 records are reported and never pooled with it.
#
# Bash 3.2 compatible. Sources test-helpers.sh.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
LEDGER_LIB="${PROJECT_ROOT}/hooks/lib/branch-ledger.sh"
RS_LIB="${PROJECT_ROOT}/hooks/lib/review-shadow.sh"
READER="${PROJECT_ROOT}/scripts/review-shadow-adjudicate.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-review-witness.sh ==="

if ! command -v jq >/dev/null 2>&1; then
    _record_pass "jq unavailable — the REVIEW leg and its recorder are jq-gated; skipping"
    print_summary
    exit 0
fi

unset ACSM_SKIP_PUSH_GATE

_GIT() { git -c user.email=t@t -c user.name=t "$@"; }

# _mk_repo — a NON-routing repo with an origin and branch feature/x:
#   C1 adds src.sh (material), C2 adds docs/a.md (docs), C3 modifies src.sh.
# origin/main is fetched so the mainline base resolves (the material-source
# predicate needs it). Sets REPO, BASE, C1, C2, C3.
_mk_repo() {
    REPO="${TEST_TMPDIR}/repo"
    local _origin="${TEST_TMPDIR}/origin.git"
    git init -q --bare "${_origin}"
    git init -q -b main "${REPO}"
    printf 'base\n' > "${REPO}/README.md"
    git -C "${REPO}" add README.md
    _GIT -C "${REPO}" commit -q -m base
    git -C "${REPO}" remote add origin "${_origin}"
    git -C "${_origin}" fetch -q "${REPO}" main:main
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

# _ledger <milestone> <sha|""> [tag] — the REAL producer, keyed like the writers.
_ledger() {
    ( cd "${REPO}" && . "${LEDGER_LIB}" && \
        branch_ledger_record "$1" "${REPO}" "$2" "${3:-}" )
}

_TOK="session-conv-W"
_PAYLOAD='{"session_id":"sess-W1","tool_use_id":"toolu_01Wit","transcript_path":"/tmp/proj/conv-W.jsonl","tool_input":{"command":"git push origin HEAD"}}'
_AGENT="claude-code_2-1-308_harness"

# _chain [completed-json-array] — REVIEW and VERIFY in the chain.
_chain() {
    printf '{"chain":["requesting-code-review","verification-before-completion"],"completed":%s}\n' \
        "${1:-[]}" > "${HOME}/.claude/.skill-composition-state-${_TOK}"
}

# _verdict <json> — the session's review verdict artifact.
_verdict() {
    printf '%s\n' "$1" > "${HOME}/.claude/.skill-review-verdict-${_TOK}"
}

# _fresh — new sandbox HOME + repo; VERIFY satisfied at HEAD; chain present.
_fresh() {
    setup_test_env
    mkdir -p "${HOME}/.claude"
    _mk_repo
    _ledger verification-before-completion ""
    _chain
    RSLOG="${TEST_TMPDIR}/rs.jsonl"
    rm -f "${RSLOG}"
}

# _run [plugin-root] — the REAL guard, from inside the repo; prints its stdout.
_run() {
    ( cd "${REPO}" && printf '%s' "${_PAYLOAD}" | \
        env AI_AGENT="${_AGENT}" REVIEW_SHADOW_LOG="${RSLOG}" \
        CLAUDE_PLUGIN_ROOT="${1:-${PROJECT_ROOT}}" /bin/bash "${GUARD}" 2>/dev/null )
}
_decision() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null; }
_nrec() { if [ -f "${RSLOG}" ]; then wc -l < "${RSLOG}" | tr -d ' '; else echo 0; fi; }
# _wc — "<witness>/<coverage>" of the LAST record, or a marker when none.
_wc() {
    if [ -s "${RSLOG}" ]; then
        tail -1 "${RSLOG}" | jq -r '"\(.review_witness // "<absent>")/\(.review_coverage // "<absent>")"' 2>/dev/null
    else
        echo "<no record>"
    fi
}

# _expect_record <label> <out> <witness/coverage> — the guard did not deny,
# wrote exactly one record, and that record names the expected witness.
_expect_record() {
    assert_equals "$1: no deny" "none" "$(_decision "$2")"
    assert_equals "$1: exactly one REVIEW record written" "1" "$(_nrec)"
    assert_equals "$1: witness/coverage" "$3" "$(_wc)"
}

_PLUGIN_VERSION="$(jq -r '.version // ""' "${PROJECT_ROOT}/.claude-plugin/plugin.json" 2>/dev/null)"

# ---------------------------------------------------------------------------
# W0: harness controls. A clean verdict bound to HEAD writes NO record (the
# leg does not fire); without it the same state writes one. Without these the
# cells below could be reading a fixture that never reached Check 1b.
# ---------------------------------------------------------------------------
echo "--- W0: harness controls ---"
_fresh
_ledger requesting-code-review ""
_verdict "{\"verdict\":\"clean\",\"reviewed_head_sha\":\"${C3}\"}"
_out="$(_run)"
assert_equals "W0a clean verdict at HEAD: no deny" "none" "$(_decision "${_out}")"
assert_equals "W0a clean verdict at HEAD: no record" "0" "$(_nrec)"
rm -f "${HOME}/.claude/.skill-review-verdict-${_TOK}"
_out="$(_run)"
assert_equals "W0b no verdict: one record" "1" "$(_nrec)"
teardown_test_env

# ---------------------------------------------------------------------------
# W1-W6: the witness rule.
# ---------------------------------------------------------------------------
echo "--- W1: only an allowlisted reviewer at HEAD ---"
_fresh
_ledger reviewer-returned "${C3}" "arm=allowlist"
_out="$(_run)"
_expect_record "W1" "${_out}" "reviewer-returned/covered"
teardown_test_env

echo "--- W2: stale reviewer + own ledger at HEAD ---"
_fresh
_ledger reviewer-returned "${C1}" "arm=allowlist"
_ledger requesting-code-review ""
_out="$(_run)"
_expect_record "W2" "${_out}" "invocation/covered"
teardown_test_env

echo "--- W3: stale reviewer + stale ledger ---"
_fresh
_ledger reviewer-returned "${C1}" "arm=allowlist"
_ledger requesting-code-review "${C1}"
_out="$(_run)"
_expect_record "W3" "${_out}" "reviewer-returned/uncovered"
teardown_test_env

echo "--- W3b: covering reviewer outranks a covering invocation ---"
_fresh
_ledger reviewer-returned "${C3}" "arm=allowlist"
_ledger requesting-code-review ""
_out="$(_run)"
_expect_record "W3b" "${_out}" "reviewer-returned/covered"
teardown_test_env

echo "--- W3c: a docs-only delta since the reviewed sha is still covered ---"
_fresh
# Move HEAD to a docs-only commit on top of C3: the reviewer at C3 covers it.
printf 'more\n' >> "${REPO}/docs/a.md"
git -C "${REPO}" add docs/a.md
_GIT -C "${REPO}" commit -q -m c4
_ledger verification-before-completion ""
_ledger reviewer-returned "${C3}" "arm=allowlist"
_ledger requesting-code-review "${C1}"
_out="$(_run)"
_expect_record "W3c" "${_out}" "reviewer-returned/covered"
teardown_test_env

echo "--- W4: description-arm reviewer at HEAD + ledger at HEAD ---"
_fresh
_ledger reviewer-returned "${C3}" "arm=description"
_ledger requesting-code-review ""
_out="$(_run)"
_expect_record "W4" "${_out}" "invocation/covered"
teardown_test_env

echo "--- W5: only .completed (no ledger, no sidecar) ---"
_fresh
_chain '["requesting-code-review"]'
_out="$(_run)"
_expect_record "W5" "${_out}" "invocation/cannot-check"
teardown_test_env

echo "--- W5b: a reviewer recorded with no dispatch sha does not witness ---"
# The lib refuses a `-` sha (F3: never substitute a later HEAD), so such a
# reviewer is not a reviewer-returned witness; the invocation still is.
_fresh
_chain '["requesting-code-review"]'
_ledger reviewer-returned "-" "arm=allowlist"
_out="$(_run)"
_expect_record "W5b" "${_out}" "invocation/cannot-check"
teardown_test_env

echo "--- W6: .completed + a clean verdict at a non-branch commit ---"
_fresh
_chain '["requesting-code-review"]'
_verdict "{\"verdict\":\"clean\",\"reviewed_head_sha\":\"${BASE}\"}"
_out="$(_run)"
_expect_record "W6" "${_out}" "verdict/uncovered"
assert_equals "W6 the record's reason is unbound" "unbound" \
    "$(tail -1 "${RSLOG}" 2>/dev/null | jq -r '.reason' 2>/dev/null)"
teardown_test_env

echo "--- W6b: a not-clean verdict is not a verdict witness ---"
_fresh
_chain '["requesting-code-review"]'
_verdict "{\"verdict\":\"blocking\",\"reviewed_head_sha\":\"${C3}\"}"
_out="$(_run)"
_expect_record "W6b" "${_out}" "invocation/cannot-check"
teardown_test_env

echo "--- W6c: verdict outranks an uncovered invocation, a covering one outranks it ---"
_fresh
_ledger requesting-code-review "${C1}"
_verdict "{\"verdict\":\"clean\",\"reviewed_head_sha\":\"${BASE}\"}"
_out="$(_run)"
_expect_record "W6c uncovered invocation" "${_out}" "verdict/uncovered"
_ledger requesting-code-review ""
rm -f "${RSLOG}"
_out="$(_run)"
_expect_record "W6c covering invocation" "${_out}" "invocation/covered"
teardown_test_env

# ---------------------------------------------------------------------------
# W7: every record carries the versions and the four stamps.
# ---------------------------------------------------------------------------
echo "--- W7: versions and stamps ---"
_fresh
_ledger reviewer-returned "${C1}" "arm=allowlist"
_ledger requesting-code-review ""
_run >/dev/null
_chain '["requesting-code-review"]'
_run >/dev/null
assert_equals "W7 two records written" "2" "$(_nrec)"
assert_equals "W7 every record: schema_version 3, predicate_version 3" "3|3 3|3" \
    "$(jq -r '"\(.schema_version)|\(.predicate_version)"' "${RSLOG}" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
assert_equals "W7 every record: session_id and tool_use_id from the payload" \
    "sess-W1|toolu_01Wit sess-W1|toolu_01Wit" \
    "$(jq -r '"\(.session_id)|\(.tool_use_id)"' "${RSLOG}" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
assert_equals "W7 every record: cc_version from AI_AGENT" "2.1.308 2.1.308" \
    "$(jq -r '.cc_version' "${RSLOG}" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
assert_not_empty "W7 fixture: the plugin manifest has a version" "${_PLUGIN_VERSION}"
assert_equals "W7 every record: acs_version from the manifest" "${_PLUGIN_VERSION} ${_PLUGIN_VERSION}" \
    "$(jq -r '.acs_version' "${RSLOG}" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
assert_equals "W7 every record carries all eight new fields" "true true" \
    "$(jq -r '[has("session_id"),has("tool_use_id"),has("cc_version"),has("acs_version"),
              has("review_witness"),has("review_coverage"),has("schema_version"),has("predicate_version")]
              | all' "${RSLOG}" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
teardown_test_env

# ---------------------------------------------------------------------------
# W8: computing the witness adds NOTHING to the guard's output. In the W2
# state the reviewer leg is never consulted, so a reviewer file present or
# absent must leave stdout byte-identical — including a COVERING reviewer,
# which the reviewer leg (_rr_ok) would have announced had the witness reused
# it.
# ---------------------------------------------------------------------------
echo "--- W8: the witness adds no advisory ---"
_fresh
_ledger requesting-code-review ""
_out_none="$(_run)"
_ledger reviewer-returned "${C1}" "arm=allowlist"
_out_stale="$(_run)"
_ledger reviewer-returned "${C3}" "arm=allowlist"
_out_cov="$(_run)"
assert_not_empty "W8 the guard produced output (control)" "${_out_none}"
assert_equals "W8 stale reviewer present vs absent: stdout identical" "${_out_none}" "${_out_stale}"
assert_equals "W8 covering reviewer present vs absent: stdout identical" "${_out_none}" "${_out_cov}"
assert_equals "W8 three records, witnesses differ (the reviewer WAS read)" \
    "invocation/covered invocation/covered reviewer-returned/covered" \
    "$(jq -r '"\(.review_witness)/\(.review_coverage)"' "${RSLOG}" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
assert_not_contains "W8 no reviewer-leg announcement" "accepted via a returned reviewer" "${_out_cov}"
teardown_test_env

# ---------------------------------------------------------------------------
# W9: the recorder's vocabulary. Out-of-vocabulary -> "invalid"; omitted ->
# "none". Driven through the real lib, read back with jq.
# ---------------------------------------------------------------------------
echo "--- W9: recorder vocabulary ---"
setup_test_env
_W9="${TEST_TMPDIR}/w9.jsonl"
( set -u; . "${RS_LIB}" 2>/dev/null
  REVIEW_SHADOW_LOG="${_W9}" review_shadow_record "t" "${PROJECT_ROOT}" "absent" "push" "HEAD" "" "bogus" "covered"
  REVIEW_SHADOW_LOG="${_W9}" review_shadow_record "t" "${PROJECT_ROOT}" "absent" "push" "HEAD" "" "verdict" "sideways"
  REVIEW_SHADOW_LOG="${_W9}" review_shadow_record "t" "${PROJECT_ROOT}" "absent" "push" "HEAD" ""
  REVIEW_SHADOW_LOG="${_W9}" review_shadow_record "t" "${PROJECT_ROOT}" "absent" "push" "HEAD" "" "" ""
  for _w in reviewer-returned verdict invocation none; do
      for _c in covered uncovered cannot-check none; do
          REVIEW_SHADOW_LOG="${_W9}" review_shadow_record "t" "${PROJECT_ROOT}" "absent" "push" "HEAD" "" "${_w}" "${_c}"
      done
  done ) >/dev/null 2>&1
_w9() { sed -n "${1}p" "${_W9}" 2>/dev/null | jq -r '"\(.review_witness)/\(.review_coverage)"' 2>/dev/null; }
assert_equals "W9 bogus witness is recorded as invalid" "invalid/covered" "$(_w9 1)"
assert_equals "W9 bogus coverage is recorded as invalid" "verdict/invalid" "$(_w9 2)"
assert_equals "W9 omitted arguments are recorded as none" "none/none" "$(_w9 3)"
assert_equals "W9 explicitly empty arguments are recorded as invalid" "invalid/invalid" "$(_w9 4)"
_W9_IN="$(for _w in reviewer-returned verdict invocation none; do for _c in covered uncovered cannot-check none; do printf '%s/%s ' "${_w}" "${_c}"; done; done | sed 's/ $//')"
assert_equals "W9 every in-vocabulary pair is recorded verbatim" "${_W9_IN}" \
    "$(sed -n '5,20p' "${_W9}" 2>/dev/null | jq -r '"\(.review_witness)/\(.review_coverage)"' 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
assert_equals "W9 the lib exports predicate 3 and schema 3" "3|3" \
    "$( ( set -u; . "${RS_LIB}" 2>/dev/null; printf '%s|%s' "${REVIEW_SHADOW_SCHEMA_VERSION:-}" "${REVIEW_SHADOW_PREDICATE_VERSION:-}" ) )"
teardown_test_env

# ---------------------------------------------------------------------------
# W10: fail-open. Without credited-skills.sh the reviewer cannot be read and
# coverage cannot be measured: the record is still written, the invocation
# witness is cannot-check, the decision is unchanged.
# ---------------------------------------------------------------------------
echo "--- W10: credited-skills.sh absent ---"
_fresh
_ledger requesting-code-review ""
_ledger reviewer-returned "${C3}" "arm=allowlist"
_ALT="${TEST_TMPDIR}/plugin"
mkdir -p "${_ALT}"
cp -R "${PROJECT_ROOT}/hooks" "${PROJECT_ROOT}/scripts" "${PROJECT_ROOT}/config" "${PROJECT_ROOT}/.claude-plugin" "${_ALT}/" 2>/dev/null
rm -f "${_ALT}/hooks/lib/credited-skills.sh"
_out="$( ( cd "${REPO}" && printf '%s' "${_PAYLOAD}" | \
    env AI_AGENT="${_AGENT}" REVIEW_SHADOW_LOG="${RSLOG}" \
    CLAUDE_PLUGIN_ROOT="${_ALT}" /bin/bash "${_ALT}/hooks/openspec-guard.sh" 2>/dev/null ) )"
_expect_record "W10" "${_out}" "invocation/cannot-check"
teardown_test_env

# ---------------------------------------------------------------------------
# W11: the witness runs ONLY when a record is about to be written. A git shim
# logs argv; the coverage measurement's distinctive call is
# `diff --no-renames --name-only`, issued by nothing else the guard runs. On
# the no-record path (W0a: clean bound verdict) it must be absent with a
# covering reviewer present; on the record path the same shim must see it
# (positive control), and at most twice (one coverage measurement per
# candidate with a sha).
# ---------------------------------------------------------------------------
echo "--- W11: no witness work on a no-record path ---"
_fresh
_ledger requesting-code-review "${C1}"
_ledger reviewer-returned "${C2}" "arm=allowlist"
_SHIM="${TEST_TMPDIR}/shim"
mkdir -p "${_SHIM}"
_REALGIT="$(command -v git)"
cat > "${_SHIM}/git" <<SHIM
#!/bin/bash
printf '%s\n' "\$*" >> "${_SHIM}/calls"
exec "${_REALGIT}" "\$@"
SHIM
chmod +x "${_SHIM}/git"
_shim_run() {
    ( cd "${REPO}" && printf '%s' "${_PAYLOAD}" | \
        env PATH="${_SHIM}:${PATH}" AI_AGENT="${_AGENT}" REVIEW_SHADOW_LOG="${RSLOG}" \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${GUARD}" >/dev/null 2>&1 )
}
_cov_calls() { grep -c -- 'diff --no-renames --name-only' "${_SHIM}/calls" 2>/dev/null | tr -d ' '; }
_verdict "{\"verdict\":\"clean\",\"reviewed_head_sha\":\"${C3}\"}"
: > "${_SHIM}/calls"
_shim_run
assert_equals "W11 no-record path: no record" "0" "$(_nrec)"
assert_not_empty "W11 the shim intercepted the guard's git calls (control)" "$(cat "${_SHIM}/calls" 2>/dev/null)"
assert_equals "W11 no-record path: no coverage measurement" "0" "$(_cov_calls)"
rm -f "${HOME}/.claude/.skill-review-verdict-${_TOK}"
: > "${_SHIM}/calls"
_shim_run
assert_equals "W11 record path: one record" "1" "$(_nrec)"
assert_equals "W11 record path: reviewer and invocation both uncovered" "reviewer-returned/uncovered" "$(_wc)"
_n="$(_cov_calls)"
if [ "${_n:-0}" -ge 1 ] && [ "${_n:-0}" -le 2 ]; then
    _record_pass "W11 record path: 1-2 coverage measurements (${_n})"
else
    _record_fail "W11 record path: 1-2 coverage measurements" "got ${_n:-0}"
fi
teardown_test_env

# ---------------------------------------------------------------------------
# W12: real producer -> real reader. A predicate-3 record written by the guard
# is adjudicable; predicate-2 records written by the predicate-2 producer (the
# same lib with its constants moved back) are reported as other-predicate and
# never pooled into the predicate-3 episodes.
# ---------------------------------------------------------------------------
echo "--- W12: round trip through the reader ---"
_fresh
_ledger requesting-code-review ""
_run >/dev/null
_RADJ="${TEST_TMPDIR}/adj.jsonl"
_rd() { REVIEW_SHADOW_LOG="${RSLOG}" REVIEW_ADJUDICATION_LOG="${_RADJ}" /bin/bash "${READER}" "$@" < /dev/null 2>&1; }
_st="$(_rd --status)"
assert_contains "W12 the reader adjudicates predicate 3" "adjudicable predicate_version: 3" "${_st}"
_nx="$(_rd --next)"
assert_contains "W12 --next offers the guard's record" \
    "$(tail -1 "${RSLOG}" | jq -r '.record_id')" "${_nx}"
# Two predicate-2 records from the predicate-2 producer.
_P2="${TEST_TMPDIR}/rs-p2.sh"
sed -e 's/^REVIEW_SHADOW_SCHEMA_VERSION=.*/REVIEW_SHADOW_SCHEMA_VERSION=2/' \
    -e 's/^REVIEW_SHADOW_PREDICATE_VERSION=.*/REVIEW_SHADOW_PREDICATE_VERSION=2/' "${RS_LIB}" > "${_P2}"
assert_equals "W12 fixture: the predicate-2 producer says 2" "2" \
    "$( ( . "${_P2}" 2>/dev/null; printf '%s' "${REVIEW_SHADOW_PREDICATE_VERSION:-}" ) )"
( . "${_P2}" 2>/dev/null
  REVIEW_SHADOW_LOG="${RSLOG}" review_shadow_record "tok-old" "${REPO}" "absent" "push" "HEAD" "/tmp/x.jsonl"
  REVIEW_SHADOW_LOG="${RSLOG}" review_shadow_record "tok-old" "${REPO}" "absent" "push" "HEAD" "/tmp/x.jsonl" ) >/dev/null 2>&1
assert_equals "W12 three records in the corpus" "3" "$(_nrec)"
_st2="$(_rd --status)"
assert_contains "W12 predicate-2 records are reported as excluded" \
    "EXCLUDED — other-predicate : 2 record(s)" "${_st2}"
_ep() { printf '%s\n' "$1" | sed -n 's/^episodes (adjudicable) *: *\([0-9][0-9]*\).*/\1/p' | head -1; }
assert_equals "W12 one adjudicable episode before the predicate-2 records" "1" "$(_ep "${_st}")"
assert_equals "W12 predicate-2 records do not enter the predicate-3 episodes" "1" "$(_ep "${_st2}")"
teardown_test_env

print_summary
