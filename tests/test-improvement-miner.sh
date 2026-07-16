#!/bin/bash
# test-improvement-miner.sh — unit tests for skills/improvement-miner/
# (content-coverage gate: this file references skills/improvement-miner/)
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MINE="${REPO_ROOT}/skills/improvement-miner/scripts/mine-evidence.sh"

test_fingerprint_stable_and_distinct() {
    echo "-- test: fingerprint is stable across calls, distinct across ids --"
    setup_test_env
    local a b c
    a="$(/bin/bash "${MINE}" fingerprint memory feedback_bash_ere_no_pcre_quantifiers)"
    b="$(/bin/bash "${MINE}" fingerprint memory feedback_bash_ere_no_pcre_quantifiers)"
    c="$(/bin/bash "${MINE}" fingerprint memory feedback_jq_separator_escapes)"
    assert_equals "same input same fp" "$a" "$b"
    [ "$a" != "$c" ] && _record_pass "distinct ids same fp" || _record_fail "distinct ids same fp" "a=$a, c=$c"
    assert_equals "fp length 16" "16" "${#a}"
    teardown_test_env
}

test_missing_gh_fails_loud() {
    echo "-- test: missing gh aborts non-zero with ERROR --"
    setup_test_env
    # stub dir contains jq+shasum+git passthroughs but NO gh; PATH restricted
    local out rc
    mkdir -p "${TEST_TMPDIR}/stub"
    for t in jq shasum git sed grep cut sort ls cat dirname basename mktemp printf; do
        p="$(command -v "$t" 2>/dev/null)" && ln -s "$p" "${TEST_TMPDIR}/stub/$t" 2>/dev/null
    done
    out="$(cd "${TEST_TMPDIR}" && PATH="${TEST_TMPDIR}/stub" /bin/bash "${MINE}" bundle 2>&1)"; rc=$?
    [ "$rc" -ne 0 ] && _record_pass "expected non-zero exit" || _record_fail "expected non-zero exit" "rc=$rc"
    assert_contains "ERROR mentions gh" "gh" "$out"
    teardown_test_env
}

make_fake_gh() {
    # fake gh: logs argv, serves canned JSON per subcommand from env-pointed files
    mkdir -p "${TEST_TMPDIR}/stub"
    GH_LOG="${TEST_TMPDIR}/gh.log"
    cat > "${TEST_TMPDIR}/stub/gh" <<'FAKEGH'
#!/bin/bash
echo "$*" >> "${GH_LOG}"
case "$1 $2" in
    "repo view") echo '{"owner":{"login":"testowner"}}' ;;
    "issue list")
        case "$*" in
            *improvement-miner-run*) cat "${FAKE_GH_LEDGER:-/dev/null}" 2>/dev/null || echo '[]' ;;
            *) cat "${FAKE_GH_EVALS:-/dev/null}" 2>/dev/null || echo '[]' ;;
        esac ;;
    *) echo '{}' ;;
esac
exit 0
FAKEGH
    chmod +x "${TEST_TMPDIR}/stub/gh"
    export GH_LOG
}

run_bundle() { # runs bundle from the fixture repo with stubbed gh first in PATH
    ( cd "${TEST_TMPDIR}/repo" && \
      IMPROVEMENT_MINER_MEMORY_DIR="${TEST_TMPDIR}/memory" \
      GH_LOG="${GH_LOG}" FAKE_GH_LEDGER="${FAKE_GH_LEDGER:-}" FAKE_GH_EVALS="${FAKE_GH_EVALS:-}" \
      PATH="${TEST_TMPDIR}/stub:${PATH}" /bin/bash "${MINE}" bundle 2>&1 )
}

test_bundle_local_sources() {
    echo "-- test: bundle collects baselines, notes absent gate-status, indexes memory --"
    setup_test_env; make_fake_gh
    mkdir -p "${TEST_TMPDIR}/repo/tests/baselines" "${TEST_TMPDIR}/memory"
    (cd "${TEST_TMPDIR}/repo" && git init -q && git -c user.email="test@example.com" -c user.name="Test" commit -q --allow-empty -m init)
    echo '{}' > "${TEST_TMPDIR}/repo/tests/baselines/x.baseline.json"
    printf -- '---\nname: feedback-sample\ndescription: a sample feedback fact\nmetadata:\n  type: feedback\n---\nbody\n' \
        > "${TEST_TMPDIR}/memory/feedback_sample.md"
    printf -- '---\nname: parked-thing\ndescription: parked with revival criteria\nmetadata:\n  type: project\n---\nRevival criterion: X\n' \
        > "${TEST_TMPDIR}/memory/project_parked_thing.md"
    local out; out="$(run_bundle)"
    assert_contains "baseline listed" "tests/baselines/x.baseline.json" "$out"
    assert_equals "gate-status absent noted" "false" "$(printf '%s' "$out" | jq -r '.gate_status.available')"
    assert_equals "feedback kind" "feedback" "$(printf '%s' "$out" | jq -r '.memory_index[] | select(.file=="feedback_sample.md") | .kind')"
    assert_equals "revival kind" "revival" "$(printf '%s' "$out" | jq -r '.memory_index[] | select(.file=="project_parked_thing.md") | .kind')"
    assert_equals "description extracted" "a sample feedback fact" "$(printf '%s' "$out" | jq -r '.memory_index[] | select(.file=="feedback_sample.md") | .description')"
    teardown_test_env
}

test_bundle_gate_status_present() {
    echo "-- test: bundle runs gate-status.sh live when present --"
    setup_test_env; make_fake_gh
    mkdir -p "${TEST_TMPDIR}/repo/scripts" "${TEST_TMPDIR}/memory"
    (cd "${TEST_TMPDIR}/repo" && git init -q && git -c user.email="test@example.com" -c user.name="Test" commit -q --allow-empty -m init)
    printf '#!/bin/bash\necho GATE-REPORT-MARKER\nexit 0\n' > "${TEST_TMPDIR}/repo/scripts/gate-status.sh"
    chmod +x "${TEST_TMPDIR}/repo/scripts/gate-status.sh"
    local out; out="$(run_bundle)"
    assert_equals "gate-status available" "true" "$(printf '%s' "$out" | jq -r '.gate_status.available')"
    assert_contains "gate-status output captured" "GATE-REPORT-MARKER" "$(printf '%s' "$out" | jq -r '.gate_status.output')"
    teardown_test_env
}

test_eval_reports_author_allowlist() {
    echo "-- test: non-allowlisted author excluded from eval_reports --"
    setup_test_env; make_fake_gh
    mkdir -p "${TEST_TMPDIR}/repo" "${TEST_TMPDIR}/memory"
    (cd "${TEST_TMPDIR}/repo" && git init -q && git -c user.email="test@example.com" -c user.name="Test" commit -q --allow-empty -m init)
    FAKE_GH_EVALS="${TEST_TMPDIR}/evals.json"
    cat > "${FAKE_GH_EVALS}" <<'EOF'
[
 {"number": 94, "title": "Behavioral eval regression: incident-analysis",
  "body": "SAFE-BOT-BODY", "author": {"login": "github-actions"}},
 {"number": 95, "title": "Behavioral eval regression: fake",
  "body": "MALICIOUS-INJECTED-BODY", "author": {"login": "mallory"}}
]
EOF
    local out; out="$(run_bundle)"
    assert_contains "bot-authored body present" "SAFE-BOT-BODY" "$out"
    assert_not_contains "third-party body excluded" "MALICIOUS-INJECTED-BODY" "$out"
    teardown_test_env
}

test_comments_never_requested() {
    echo "-- test: gh is never asked for comment fields --"
    setup_test_env; make_fake_gh
    mkdir -p "${TEST_TMPDIR}/repo" "${TEST_TMPDIR}/memory"
    (cd "${TEST_TMPDIR}/repo" && git init -q && git -c user.email="test@example.com" -c user.name="Test" commit -q --allow-empty -m init)
    run_bundle > /dev/null
    local log; log="$(cat "${GH_LOG}" 2>/dev/null)"
    assert_not_contains "no comments field in any gh call" "comments" "${log}"
    teardown_test_env
}

test_fingerprint_stable_and_distinct
test_missing_gh_fails_loud
test_bundle_local_sources
test_bundle_gate_status_present
test_eval_reports_author_allowlist
test_comments_never_requested

print_summary
