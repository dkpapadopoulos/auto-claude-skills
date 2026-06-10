#!/usr/bin/env bash
# test-run-behavioral-evals-variance.sh — Hermetic self-test for the --variance N
# mode added to tests/run-behavioral-evals.sh. Stubs `claude` via CLAUDE_BIN.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-run-behavioral-evals-variance.sh ==="

RUNNER="${PROJECT_ROOT}/tests/run-behavioral-evals.sh"

# Build a tmpdir with a stub claude that always returns CAST-matching output
TMPDIR_TEST="$(mktemp -d -t variance-self-test.XXXXXX)"
trap 'rm -rf "${TMPDIR_TEST}"' EXIT

# Stub claude — emits a 'result' field that matches every CAST assertion regex.
# Regression guard: the runner MUST deliver the prompt via stdin (current CLI
# parses --disallowedTools as variadic and swallows trailing positionals). If
# stdin carries no prompt, emit a non-matching result so every assertion fails
# loudly. read -t bounds the wait: with argv-passing (the regression) stdin is
# an open-but-silent inherited fd and a bare `cat` would deadlock the suite.
cat > "${TMPDIR_TEST}/claude" <<'STUBEOF'
#!/usr/bin/env bash
STDIN_PROMPT=""
IFS= read -r -d '' -t 5 STDIN_PROMPT || true
if [ -z "${STDIN_PROMPT}" ]; then
    cat <<JSONEOF
{
  "type": "result",
  "is_error": false,
  "duration_ms": 1000,
  "result": "REGRESSION: prompt did not arrive on stdin",
  "modelUsage": {
    "claude-test-stub": {"inputTokens": 0, "outputTokens": 0}
  }
}
JSONEOF
    exit 0
fi
cat <<JSONEOF
{
  "type": "result",
  "is_error": false,
  "duration_ms": 1000,
  "result": "alpha bravo charlie delta echo foxtrot golf hotel india",
  "modelUsage": {
    "claude-test-stub": {"inputTokens": 10, "outputTokens": 20}
  }
}
JSONEOF
STUBEOF
chmod +x "${TMPDIR_TEST}/claude"

ARTIFACTS_DIR_TEST="${TMPDIR_TEST}/artifacts"
REPORT_PATH_TEST="${TMPDIR_TEST}/variance-report.md"

# ---------------------------------------------------------------------------
# Variance mode (N=3) with all-pass stub
# ---------------------------------------------------------------------------
echo "-- variance N=3 happy path --"

ARTIFACTS_DIR="${ARTIFACTS_DIR_TEST}" \
BEHAVIORAL_EVALS=1 \
CLAUDE_BIN="${TMPDIR_TEST}/claude" \
bash "${RUNNER}" \
    --scenario variance-self-test \
    --pack "${PROJECT_ROOT}/tests/fixtures/behavioral-runner/scenarios.json" \
    --variance 3 \
    --variance-report "${REPORT_PATH_TEST}" \
    > "${TMPDIR_TEST}/run.log" 2>&1
runner_exit=$?

assert_equals "variance runner exits 0" "0" "${runner_exit}"

artifact_count="$(find "${ARTIFACTS_DIR_TEST}" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
assert_equals "3 iteration artifacts written" "3" "${artifact_count}"

assert_file_exists "variance report file written" "${REPORT_PATH_TEST}"

if [ -f "${REPORT_PATH_TEST}" ]; then
    report_content="$(cat "${REPORT_PATH_TEST}")"
    assert_contains "report has per-assertion table header" \
        "| # | Description | Pass | Fail | Pass rate | Classification |" \
        "${report_content}"

    # With stub-claude returning all-pass, every assertion classifies 'stable'
    stable_count="$(printf '%s' "${report_content}" | grep -c -F " stable " 2>/dev/null || true)"
    if [ "${stable_count:-0}" -ge 9 ]; then
        _record_pass "all 9 assertions classify as stable when stub passes all"
    else
        _record_fail "all 9 assertions classify as stable" "stable_count=${stable_count:-0}"
    fi

    assert_contains "report has PR2 placeholder" \
        "Pending — appended after PR2" \
        "${report_content}"
fi

# ---------------------------------------------------------------------------
# Argument validation: non-integer --variance
# ---------------------------------------------------------------------------
echo "-- guard: --variance abc --"

ARTIFACTS_DIR="${ARTIFACTS_DIR_TEST}" \
BEHAVIORAL_EVALS=1 \
CLAUDE_BIN="${TMPDIR_TEST}/claude" \
bash "${RUNNER}" \
    --scenario variance-self-test \
    --pack "${PROJECT_ROOT}/tests/fixtures/behavioral-runner/scenarios.json" \
    --variance abc \
    > "${TMPDIR_TEST}/bad.log" 2>&1
bad_exit=$?

assert_equals "non-integer --variance rejected with exit 2" "2" "${bad_exit}"

# ---------------------------------------------------------------------------
# Argument validation: --variance 0
# ---------------------------------------------------------------------------
echo "-- guard: --variance 0 --"

ARTIFACTS_DIR="${ARTIFACTS_DIR_TEST}" \
BEHAVIORAL_EVALS=1 \
CLAUDE_BIN="${TMPDIR_TEST}/claude" \
bash "${RUNNER}" \
    --scenario variance-self-test \
    --pack "${PROJECT_ROOT}/tests/fixtures/behavioral-runner/scenarios.json" \
    --variance 0 \
    > "${TMPDIR_TEST}/zero.log" 2>&1
zero_exit=$?

assert_equals "--variance 0 rejected with exit 2" "2" "${zero_exit}"

# ---------------------------------------------------------------------------
# Single-run regression (default --variance 1) still works after refactor
# ---------------------------------------------------------------------------
echo "-- regression: single-run mode --"

ARTIFACTS_DIR="${ARTIFACTS_DIR_TEST}/single" \
BEHAVIORAL_EVALS=1 \
CLAUDE_BIN="${TMPDIR_TEST}/claude" \
bash "${RUNNER}" \
    --scenario variance-self-test \
    --pack "${PROJECT_ROOT}/tests/fixtures/behavioral-runner/scenarios.json" \
    > "${TMPDIR_TEST}/single.log" 2>&1
single_exit=$?

assert_equals "single-run mode exits 0 on all-pass output" "0" "${single_exit}"

# ---------------------------------------------------------------------------
# Report rendering: an assertion whose `text` regex contains `|` must not bleed
# the regex into the Description column. The counter field is tab-delimited, so
# a regex like "alpha|bravo|charlie" must not be split on `|`. Regression for
# the model-routing catch-detector (a `|`-heavy alternation).
# ---------------------------------------------------------------------------
echo "-- report: pipe in assertion regex renders description cleanly --"

PIPE_PACK="${TMPDIR_TEST}/pipe-pack.json"
cat > "${PIPE_PACK}" <<'PACKEOF'
[
  {
    "id": "pipe-regex-scenario",
    "prompt": "noop",
    "expected_behavior": "n/a",
    "assertions": [
      { "kind": "text", "description": "UNIQUEDESC masking insight detector", "text": "alpha|bravo|charlie" }
    ]
  }
]
PACKEOF
PIPE_REPORT="${TMPDIR_TEST}/pipe-report.md"

ARTIFACTS_DIR="${ARTIFACTS_DIR_TEST}/pipe" \
BEHAVIORAL_EVALS=1 \
CLAUDE_BIN="${TMPDIR_TEST}/claude" \
bash "${RUNNER}" \
    --scenario pipe-regex-scenario \
    --pack "${PIPE_PACK}" \
    --variance 2 \
    --variance-report "${PIPE_REPORT}" \
    > "${TMPDIR_TEST}/pipe.log" 2>&1

assert_file_exists "pipe-regex variance report written" "${PIPE_REPORT}"
if [ -f "${PIPE_REPORT}" ]; then
    pipe_report="$(cat "${PIPE_REPORT}")"
    assert_contains "Description column shows the full description" \
        "UNIQUEDESC masking insight detector" "${pipe_report}"
    # The regex alternatives must NOT appear in the report — if they do, the
    # counter field was split on `|` and the regex bled into Description.
    assert_not_contains "regex alternative 'bravo' did not bleed into report" \
        "bravo" "${pipe_report}"
    assert_not_contains "regex alternative 'charlie' did not bleed into report" \
        "charlie" "${pipe_report}"
fi

print_summary
