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

test_gh_runtime_failure_fails_loud() {
    echo "-- test: gh exits non-zero at runtime (e.g. unauthenticated) aborts bundle/dedup loudly, never a clean-looking empty bundle --"
    setup_test_env
    mkdir -p "${TEST_TMPDIR}/stub" "${TEST_TMPDIR}/repo"
    (cd "${TEST_TMPDIR}/repo" && git init -q && git -c user.email="test@example.com" -c user.name="Test" commit -q --allow-empty -m init)
    cat > "${TEST_TMPDIR}/stub/gh" <<'FAKEGH'
#!/bin/bash
echo "Not authenticated" >&2
exit 4
FAKEGH
    chmod +x "${TEST_TMPDIR}/stub/gh"
    local out rc
    out="$(cd "${TEST_TMPDIR}/repo" && PATH="${TEST_TMPDIR}/stub:${PATH}" /bin/bash "${MINE}" bundle 2>&1)"; rc=$?
    [ "$rc" -ne 0 ] && _record_pass "bundle: non-zero exit on gh runtime failure" || _record_fail "bundle: non-zero exit on gh runtime failure" "rc=$rc"
    assert_contains "bundle: ERROR printed" "ERROR" "$out"
    assert_contains "bundle: underlying gh failure surfaced (not swallowed)" "Not authenticated" "$out"

    out="$(cd "${TEST_TMPDIR}/repo" && PATH="${TEST_TMPDIR}/stub:${PATH}" /bin/bash "${MINE}" dedup somefp 2>&1)"; rc=$?
    [ "$rc" -ne 0 ] && _record_pass "dedup: non-zero exit on gh runtime failure" || _record_fail "dedup: non-zero exit on gh runtime failure" "rc=$rc"
    assert_contains "dedup: ERROR printed" "ERROR" "$out"
    teardown_test_env
}

test_empty_owner_login_fails_loud() {
    echo "-- test: gh succeeds (rc 0) but returns no owner login aborts ledger read loudly, does not silently degrade --"
    setup_test_env
    mkdir -p "${TEST_TMPDIR}/stub" "${TEST_TMPDIR}/repo"
    (cd "${TEST_TMPDIR}/repo" && git init -q && git -c user.email="test@example.com" -c user.name="Test" commit -q --allow-empty -m init)
    cat > "${TEST_TMPDIR}/stub/gh" <<'FAKEGH'
#!/bin/bash
case "$1 $2" in
    "repo view") echo '{"owner":{"login":""}}' ;;
    "issue list") echo '[]' ;;
    *) echo '{}' ;;
esac
exit 0
FAKEGH
    chmod +x "${TEST_TMPDIR}/stub/gh"
    local out rc
    out="$(cd "${TEST_TMPDIR}/repo" && PATH="${TEST_TMPDIR}/stub:${PATH}" /bin/bash "${MINE}" bundle 2>&1)"; rc=$?
    [ "$rc" -ne 0 ] && _record_pass "bundle: non-zero exit on empty owner login" || _record_fail "bundle: non-zero exit on empty owner login" "rc=$rc"
    assert_contains "bundle: ERROR mentions owner" "owner" "$out"
    teardown_test_env
}

test_garbage_json_fails_loud() {
    echo "-- test: gh succeeds (rc 0) but emits non-JSON — jq filter failure must abort loudly, never degrade to an empty bundle/ledger --"
    setup_test_env
    mkdir -p "${TEST_TMPDIR}/stub" "${TEST_TMPDIR}/repo"
    (cd "${TEST_TMPDIR}/repo" && git init -q && git -c user.email="test@example.com" -c user.name="Test" commit -q --allow-empty -m init)
    cat > "${TEST_TMPDIR}/stub/gh" <<'FAKEGH'
#!/bin/bash
case "$1 $2" in
    "repo view") echo '{"owner":{"login":"testowner"}}' ;;
    "issue list") echo '<html>502 Bad Gateway</html>' ;;
    *) echo '{}' ;;
esac
exit 0
FAKEGH
    chmod +x "${TEST_TMPDIR}/stub/gh"
    local out rc
    out="$(cd "${TEST_TMPDIR}/repo" && PATH="${TEST_TMPDIR}/stub:${PATH}" /bin/bash "${MINE}" bundle 2>&1)"; rc=$?
    [ "$rc" -ne 0 ] && _record_pass "bundle: non-zero exit on garbage JSON at gh rc 0" || _record_fail "bundle: non-zero exit on garbage JSON at gh rc 0" "rc=$rc"
    assert_contains "bundle: ERROR printed on garbage JSON" "ERROR" "$out"

    out="$(cd "${TEST_TMPDIR}/repo" && PATH="${TEST_TMPDIR}/stub:${PATH}" /bin/bash "${MINE}" dedup somefp 2>&1)"; rc=$?
    [ "$rc" -ne 0 ] && _record_pass "dedup: non-zero exit on garbage JSON at gh rc 0" || _record_fail "dedup: non-zero exit on garbage JSON at gh rc 0" "rc=$rc"
    assert_contains "dedup: ERROR printed on garbage JSON" "ERROR" "$out"
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

make_ledger_fixture() { # $1 = path; writes two run issues (bodies with json fences)
    cat > "$1" <<'EOF'
[
 {"number": 10, "author": {"login": "testowner"},
  "body": "Mine run 1\n```json\n{\"run\":\"2026-07-01\",\"presented\":[{\"fp\":\"aaaa000000000001\",\"title\":\"p1\",\"rank\":1,\"grade\":\"B\",\"meta\":false,\"decision\":\"rejected\",\"reason\":\"no\",\"issue\":null},{\"fp\":\"aaaa000000000002\",\"title\":\"p2\",\"rank\":2,\"grade\":\"C\",\"meta\":true,\"decision\":\"rejected\",\"reason\":\"no\",\"issue\":null},{\"fp\":\"aaaa000000000003\",\"title\":\"p3\",\"rank\":3,\"grade\":\"C\",\"meta\":false,\"decision\":\"rejected\",\"reason\":\"no\",\"issue\":null}]}\n```\n"},
 {"number": 12, "author": {"login": "testowner"},
  "body": "Mine run 2\n```json\n{\"run\":\"2026-07-08\",\"presented\":[{\"fp\":\"aaaa000000000004\",\"title\":\"p4\",\"rank\":1,\"grade\":\"B\",\"meta\":false,\"decision\":\"rejected\",\"reason\":\"no\",\"issue\":null},{\"fp\":\"aaaa000000000005\",\"title\":\"p5\",\"rank\":2,\"grade\":\"D\",\"meta\":false,\"decision\":\"rejected\",\"reason\":\"no\",\"issue\":null}]}\n```\n"}
]
EOF
}

init_fixture_repo() { # sets up ${TEST_TMPDIR}/repo as a real git repo (mechanical wiring for run_bundle/dedup)
    mkdir -p "${TEST_TMPDIR}/repo"
    (cd "${TEST_TMPDIR}/repo" && git init -q && git -c user.email="test@example.com" -c user.name="Test" commit -q --allow-empty -m init)
}

test_kill_math_tripped_and_alive() {
    echo "-- test: kill math — 0-of-5 tripped, 1-of-5 alive --"
    setup_test_env; make_fake_gh; init_fixture_repo; mkdir -p "${TEST_TMPDIR}/memory"
    FAKE_GH_LEDGER="${TEST_TMPDIR}/ledger.json"; make_ledger_fixture "${FAKE_GH_LEDGER}"
    local out; out="$(run_bundle)"
    assert_equals "presented cum" "5" "$(printf '%s' "$out" | jq -r '.ledger.presented')"
    assert_equals "tripped at 0-of-5" "tripped" "$(printf '%s' "$out" | jq -r '.kill.state')"
    # flip one of the first five to approved -> alive
    jq '.[0].body |= sub("\"decision\":\"rejected\",\"reason\":\"no\",\"issue\":null}]"; "\"decision\":\"approved\",\"reason\":\"yes\",\"issue\":77}]")' \
        "${FAKE_GH_LEDGER}" > "${FAKE_GH_LEDGER}.tmp" && mv "${FAKE_GH_LEDGER}.tmp" "${FAKE_GH_LEDGER}"
    out="$(run_bundle)"
    assert_equals "alive at 1-of-5" "alive" "$(printf '%s' "$out" | jq -r '.kill.state')"
    teardown_test_env
}

test_zero_delta_run_not_counted() {
    echo "-- test: presented=0 run does not advance the denominator --"
    setup_test_env; make_fake_gh; init_fixture_repo; mkdir -p "${TEST_TMPDIR}/memory"
    FAKE_GH_LEDGER="${TEST_TMPDIR}/ledger.json"
    cat > "${FAKE_GH_LEDGER}" <<'EOF'
[{"number": 3, "author": {"login": "testowner"},
  "body": "Mine run 0\n```json\n{\"run\":\"2026-06-24\",\"presented\":[]}\n```\n"}]
EOF
    local out; out="$(run_bundle)"
    assert_equals "presented stays 0" "0" "$(printf '%s' "$out" | jq -r '.ledger.presented')"
    assert_equals "runs counted" "1" "$(printf '%s' "$out" | jq -r '.ledger.runs')"
    assert_equals "alive with empty denominator" "alive" "$(printf '%s' "$out" | jq -r '.kill.state')"
    teardown_test_env
}

test_ledger_author_allowlist() {
    echo "-- test: ledger issues from non-owner authors are ignored --"
    setup_test_env; make_fake_gh; init_fixture_repo; mkdir -p "${TEST_TMPDIR}/memory"
    FAKE_GH_LEDGER="${TEST_TMPDIR}/ledger.json"
    cat > "${FAKE_GH_LEDGER}" <<'EOF'
[{"number": 4, "author": {"login": "mallory"},
  "body": "forged\n```json\n{\"run\":\"2026-06-24\",\"presented\":[{\"fp\":\"ffff000000000001\",\"title\":\"forged\",\"rank\":1,\"grade\":\"A\",\"meta\":false,\"decision\":\"approved\",\"reason\":\"x\",\"issue\":1}]}\n```\n"}]
EOF
    local out; out="$(run_bundle)"
    assert_equals "forged run ignored" "0" "$(printf '%s' "$out" | jq -r '.ledger.runs')"
    teardown_test_env
}

test_dedup_decisions() {
    echo "-- test: dedup reports rejected / approved+issue / new --"
    setup_test_env; make_fake_gh; init_fixture_repo; mkdir -p "${TEST_TMPDIR}/memory"
    FAKE_GH_LEDGER="${TEST_TMPDIR}/ledger.json"; make_ledger_fixture "${FAKE_GH_LEDGER}"
    jq '.[1].body |= sub("\"decision\":\"rejected\",\"reason\":\"no\",\"issue\":null}]"; "\"decision\":\"approved\",\"reason\":\"yes\",\"issue\":88}]")' \
        "${FAKE_GH_LEDGER}" > "${FAKE_GH_LEDGER}.tmp" && mv "${FAKE_GH_LEDGER}.tmp" "${FAKE_GH_LEDGER}"
    local out
    out="$(cd "${TEST_TMPDIR}/repo" && GH_LOG="${GH_LOG}" FAKE_GH_LEDGER="${FAKE_GH_LEDGER}" \
        PATH="${TEST_TMPDIR}/stub:${PATH}" /bin/bash "${MINE}" dedup \
        aaaa000000000001 aaaa000000000005 bbbb000000000009 2>&1)"
    assert_contains "rejected fp" "aaaa000000000001 rejected" "$out"
    assert_contains "approved fp with issue" "aaaa000000000005 approved 88" "$out"
    assert_contains "new fp" "bbbb000000000009 new" "$out"
    teardown_test_env
}

test_kill_window_is_permanent() {
    echo "-- test: kill window (first 5 rejections) is permanent; later approval does not revive --"
    setup_test_env; make_fake_gh; init_fixture_repo; mkdir -p "${TEST_TMPDIR}/memory"
    FAKE_GH_LEDGER="${TEST_TMPDIR}/ledger.json"
    cat > "${FAKE_GH_LEDGER}" <<'EOF'
[
 {"number": 10, "author": {"login": "testowner"},
  "body": "Mine run 1\n```json\n{\"run\":\"2026-07-01\",\"presented\":[{\"fp\":\"aaaa000000000001\",\"title\":\"p1\",\"rank\":1,\"grade\":\"B\",\"meta\":false,\"decision\":\"rejected\",\"reason\":\"no\",\"issue\":null},{\"fp\":\"aaaa000000000002\",\"title\":\"p2\",\"rank\":2,\"grade\":\"C\",\"meta\":true,\"decision\":\"rejected\",\"reason\":\"no\",\"issue\":null},{\"fp\":\"aaaa000000000003\",\"title\":\"p3\",\"rank\":3,\"grade\":\"C\",\"meta\":false,\"decision\":\"rejected\",\"reason\":\"no\",\"issue\":null}]}\n```\n"},
 {"number": 12, "author": {"login": "testowner"},
  "body": "Mine run 2\n```json\n{\"run\":\"2026-07-08\",\"presented\":[{\"fp\":\"aaaa000000000004\",\"title\":\"p4\",\"rank\":1,\"grade\":\"B\",\"meta\":false,\"decision\":\"rejected\",\"reason\":\"no\",\"issue\":null},{\"fp\":\"aaaa000000000005\",\"title\":\"p5\",\"rank\":2,\"grade\":\"D\",\"meta\":false,\"decision\":\"rejected\",\"reason\":\"no\",\"issue\":null}]}\n```\n"},
 {"number": 15, "author": {"login": "testowner"},
  "body": "Mine run 3\n```json\n{\"run\":\"2026-07-15\",\"presented\":[{\"fp\":\"aaaa000000000006\",\"title\":\"p6\",\"rank\":1,\"grade\":\"B\",\"meta\":false,\"decision\":\"approved\",\"reason\":\"yes\",\"issue\":99}]}\n```\n"}
]
EOF
    local out; out="$(run_bundle)"
    assert_equals "presented cumulative (5+1)" "6" "$(printf '%s' "$out" | jq -r '.ledger.presented')"
    assert_equals "approved count" "1" "$(printf '%s' "$out" | jq -r '.ledger.approved')"
    assert_equals "kill state stays tripped (first 5 window is permanent)" "tripped" "$(printf '%s' "$out" | jq -r '.kill.state')"
    teardown_test_env
}

test_malformed_fence_skipped() {
    echo "-- test: malformed json fences gracefully skipped, script continues with exit 0 --"
    setup_test_env; make_fake_gh; init_fixture_repo; mkdir -p "${TEST_TMPDIR}/memory"
    FAKE_GH_LEDGER="${TEST_TMPDIR}/ledger.json"
    cat > "${FAKE_GH_LEDGER}" <<'EOF'
[
 {"number": 5, "author": {"login": "testowner"},
  "body": "Mine run with no fence\nJust plain text body, no json fence."},
 {"number": 7, "author": {"login": "testowner"},
  "body": "Mine run with broken fence\n```json\n{\"run\":\"2026-07-01\",\"presented\":[{\"fp\":\"broken\",\"title\":\"bad\",\"rank\":1,\"grade\":\"B\",\"meta\":false,\"decision\":\"rejected\"\n```\n"},
 {"number": 9, "author": {"login": "testowner"},
  "body": "Mine run valid\n```json\n{\"run\":\"2026-07-09\",\"presented\":[{\"fp\":\"cccc000000000001\",\"title\":\"valid\",\"rank\":1,\"grade\":\"A\",\"meta\":false,\"decision\":\"rejected\",\"reason\":\"ok\",\"issue\":null}]}\n```\n"}
]
EOF
    local out rc; out="$(run_bundle)"; rc=$?
    assert_equals "exit code is 0 (no abort on malformed)" "0" "$rc"
    assert_equals "runs counted (only valid issue)" "1" "$(printf '%s' "$out" | jq -r '.ledger.runs')"
    assert_equals "presented from valid issue only" "1" "$(printf '%s' "$out" | jq -r '.ledger.presented')"
    teardown_test_env
}

run_select() { printf '%s' "$1" | /bin/bash "${MINE}" select 2>&1; }

test_select_contract_gate_and_meta_cap() {
    echo "-- test: select — missing contract withheld; 3rd meta (worst grade) trimmed --"
    setup_test_env
    local input out
    input='[
      {"fp":"f1","title":"meta B","grade":"B","meta":true,"contract_complete":true,"end_user":false},
      {"fp":"f2","title":"user C","grade":"C","meta":false,"contract_complete":true,"end_user":true},
      {"fp":"f3","title":"meta C","grade":"C","meta":true,"contract_complete":true,"end_user":false},
      {"fp":"f4","title":"meta D","grade":"D","meta":true,"contract_complete":true,"end_user":false},
      {"fp":"f5","title":"no contract","grade":"A","meta":false,"contract_complete":false,"end_user":true}
    ]'
    out="$(run_select "${input}")"
    assert_equals "f5 withheld missing_contract" "missing_contract" "$(printf '%s' "$out" | jq -r '.withheld[] | select(.fp=="f5") | .reason')"
    assert_equals "f4 withheld meta_cap" "meta_cap" "$(printf '%s' "$out" | jq -r '.withheld[] | select(.fp=="f4") | .reason')"
    assert_equals "presented count" "3" "$(printf '%s' "$out" | jq -r '.presented | length')"
    assert_contains "order preserved, f1 first" '"f1"' "$(printf '%s' "$out" | jq -c '[.presented[].fp]')"
    teardown_test_env
}

test_select_cap_and_end_user_warning() {
    echo "-- test: select — cap 5 preserves rank order; all-meta report warns --"
    setup_test_env
    local input out
    input='[
      {"fp":"m1","title":"m1","grade":"A","meta":true,"contract_complete":true,"end_user":false},
      {"fp":"m2","title":"m2","grade":"A","meta":true,"contract_complete":true,"end_user":false},
      {"fp":"u1","title":"u1","grade":"B","meta":false,"contract_complete":true,"end_user":false},
      {"fp":"u2","title":"u2","grade":"B","meta":false,"contract_complete":true,"end_user":false},
      {"fp":"u3","title":"u3","grade":"B","meta":false,"contract_complete":true,"end_user":false},
      {"fp":"u4","title":"u4","grade":"B","meta":false,"contract_complete":true,"end_user":false}
    ]'
    out="$(run_select "${input}")"
    assert_equals "cap withholds 6th" "cap" "$(printf '%s' "$out" | jq -r '.withheld[] | select(.fp=="u4") | .reason')"
    assert_equals "warning emitted" "no_end_user_facing" "$(printf '%s' "$out" | jq -r '.warnings[0]')"
    teardown_test_env
}

test_select_null_grade_degrades() {
    echo "-- test: select — null grade ranks worst (9), no crash, withheld by meta_cap --"
    setup_test_env
    local input out rc
    input='[
      {"fp":"f1","title":"meta A","grade":"A","meta":true,"contract_complete":true,"end_user":false},
      {"fp":"f2","title":"meta B","grade":"B","meta":true,"contract_complete":true,"end_user":false},
      {"fp":"f3","title":"meta null","grade":null,"meta":true,"contract_complete":true,"end_user":false}
    ]'
    out="$(run_select "${input}")"; rc=$?
    assert_equals "select exits 0 (no crash)" "0" "$rc"
    assert_equals "null-grade withheld meta_cap" "meta_cap" "$(printf '%s' "$out" | jq -r '.withheld[] | select(.fp=="f3") | .reason')"
    assert_equals "presented count is 2 (f1, f2)" "2" "$(printf '%s' "$out" | jq -r '.presented | length')"
    teardown_test_env
}

test_select_meta_tie_keeps_earlier() {
    echo "-- test: select — same grade (C) keeps earlier input position, not key order --"
    setup_test_env
    local input out fps
    input='[
      {"fp":"t1","title":"meta 1","grade":"C","meta":true,"contract_complete":true,"end_user":false},
      {"fp":"t2","title":"meta 2","grade":"C","meta":true,"contract_complete":true,"end_user":false},
      {"fp":"t3","title":"meta 3","grade":"C","meta":true,"contract_complete":true,"end_user":false}
    ]'
    out="$(run_select "${input}")"
    fps="$(printf '%s' "$out" | jq -c '[.presented[].fp]')"
    assert_equals "fp order is t1,t2" '["t1","t2"]' "$fps"
    assert_equals "t3 withheld meta_cap" "meta_cap" "$(printf '%s' "$out" | jq -r '.withheld[] | select(.fp=="t3") | .reason')"
    teardown_test_env
}

test_skill_md_content() {
    echo "-- test: SKILL.md exists with required contract anchors --"
    local skill="${REPO_ROOT}/skills/improvement-miner/SKILL.md"
    assert_file_exists "SKILL.md exists" "${skill}"
    if [ ! -f "${skill}" ]; then
        return
    fi
    local body; body="$(cat "${skill}")"
    assert_contains "frontmatter description present" "description:" "${body}"
    assert_contains "invokes bundle mode" "mine-evidence.sh" "${body}"
    assert_contains "kill refusal step present" "decommission recommended" "${body}"
    assert_contains "A/B contract fields named" "pinned" "${body}"
    assert_contains "ledger fence contract documented" '```json' "${body}"
    assert_contains "run label documented" "improvement-miner-run" "${body}"
    assert_contains "no-push invariant stated" "no code, no pushes" "${body}"
}

test_fingerprint_stable_and_distinct
test_missing_gh_fails_loud
test_gh_runtime_failure_fails_loud
test_empty_owner_login_fails_loud
test_garbage_json_fails_loud
test_bundle_local_sources
test_bundle_gate_status_present
test_eval_reports_author_allowlist
test_comments_never_requested
test_kill_math_tripped_and_alive
test_zero_delta_run_not_counted
test_ledger_author_allowlist
test_dedup_decisions
test_kill_window_is_permanent
test_malformed_fence_skipped
test_select_contract_gate_and_meta_cap
test_select_cap_and_end_user_warning
test_select_null_grade_degrades
test_select_meta_tie_keeps_earlier
test_skill_md_content

print_summary
