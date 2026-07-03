#!/usr/bin/env bash
# test-run-behavioral-evals.sh — Hermetic self-tests for the behavioral eval runner.
# Bash 3.2 compatible. No network, no real claude invocation.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUNNER="${PROJECT_ROOT}/tests/run-behavioral-evals.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-run-behavioral-evals.sh ==="

# ---------------------------------------------------------------------------
# Guard: missing BEHAVIORAL_EVALS env var
# ---------------------------------------------------------------------------
echo "-- guard: missing BEHAVIORAL_EVALS --"

unset BEHAVIORAL_EVALS
output="$(bash "${RUNNER}" --scenario anything 2>&1)"
exit_code=$?

assert_equals "exits with code 2 when BEHAVIORAL_EVALS is unset" "2" "${exit_code}"
assert_contains "prints opt-in notice naming BEHAVIORAL_EVALS" "BEHAVIORAL_EVALS" "${output}"

# ---------------------------------------------------------------------------
# Guard: missing claude binary
# ---------------------------------------------------------------------------
echo "-- guard: missing claude binary --"

BEHAVIORAL_EVALS=1 CLAUDE_BIN=/nonexistent/claude-xyz \
    output="$(bash "${RUNNER}" --scenario well-formed-scenario \
              --pack tests/fixtures/behavioral-runner/scenarios.json 2>&1)"
exit_code=$?

assert_equals "exits with code 2 when claude binary missing" "2" "${exit_code}"
assert_contains "names the missing binary in error" "claude" "${output}"

# ---------------------------------------------------------------------------
# Guard: missing --scenario argument
# ---------------------------------------------------------------------------
echo "-- guard: missing --scenario --"

output="$(BEHAVIORAL_EVALS=1 bash "${RUNNER}" 2>&1)"
exit_code=$?

assert_equals "exits with code 2 when --scenario is missing" "2" "${exit_code}"
assert_contains "error names the missing flag" "--scenario" "${output}"

# ---------------------------------------------------------------------------
# Guard: scenario id not found in pack
# ---------------------------------------------------------------------------
echo "-- guard: scenario id not in pack --"

output="$(BEHAVIORAL_EVALS=1 bash "${RUNNER}" \
          --scenario does-not-exist \
          --pack tests/fixtures/behavioral-runner/scenarios.json 2>&1)"
exit_code=$?

assert_equals "exits with code 2 when scenario id unknown" "2" "${exit_code}"
assert_contains "error names the unknown id" "does-not-exist" "${output}"

# ---------------------------------------------------------------------------
# Guard: scenario malformed (missing assertions field)
# ---------------------------------------------------------------------------
echo "-- guard: malformed scenario --"

output="$(BEHAVIORAL_EVALS=1 bash "${RUNNER}" \
          --scenario malformed-missing-assertions \
          --pack tests/fixtures/behavioral-runner/scenarios.json 2>&1)"
exit_code=$?

assert_equals "exits with code 2 when scenario is malformed" "2" "${exit_code}"
assert_contains "error names the missing field" "assertions" "${output}"

# ---------------------------------------------------------------------------
# Invocation: stubbed claude returns a response that matches the assertion
# ---------------------------------------------------------------------------
echo "-- invocation: stubbed claude pass case --"

# Build a canned response that satisfies the 'well-formed-scenario' assertion
# (regex: "exit.code|termination")
CANNED_RESPONSE_FILE="${TMPDIR:-/tmp}/acs-mock-response-$$.txt"
trap 'rm -f "${CANNED_RESPONSE_FILE}"' EXIT
cat > "${CANNED_RESPONSE_FILE}" <<'EOF'
Investigation: the pods are in CrashLoopBackOff with exit code 137,
indicating an OOMKilled termination. Check previous container logs.
EOF

output="$(MOCK_RESPONSE_FILE="${CANNED_RESPONSE_FILE}" \
BEHAVIORAL_EVALS=1 \
CLAUDE_BIN="${PROJECT_ROOT}/tests/fixtures/behavioral-runner/mock-claude.sh" \
ARTIFACTS_DIR="${TMPDIR:-/tmp}/acs-artifacts-$$" \
SKILL_PATH="${PROJECT_ROOT}/skills/incident-analysis/SKILL.md" \
bash "${RUNNER}" \
  --scenario well-formed-scenario \
  --pack "${PROJECT_ROOT}/tests/fixtures/behavioral-runner/scenarios.json" 2>&1)"
exit_code=$?

assert_equals "exits 0 when invocation completes and assertions pass" "0" "${exit_code}"
assert_contains "output reports PASS for the matching assertion" "PASS" "${output}"
assert_contains "output names the matched scenario id" "well-formed-scenario" "${output}"

# ---------------------------------------------------------------------------
# Directive injection: --directive-file content reaches the constructed prompt.
# This is the mechanism that drives the db-gate-race B1/B2 treatment arms; a
# silent break here would make all arms identical with no error. Assert the
# directive body is injected (and wrapped in the activation_directive block).
# ---------------------------------------------------------------------------
echo "-- directive: --directive-file content is injected into the prompt --"

DIRECTIVE_FILE_T="${TMPDIR:-/tmp}/acs-directive-$$.md"
STDIN_CAPTURE="${TMPDIR:-/tmp}/acs-stdin-$$.txt"
printf 'ZZ_UNIQUE_DIRECTIVE_MARKER_9137 walk the checklist\n' > "${DIRECTIVE_FILE_T}"
# Re-list accumulated temp paths so an abnormal exit before the inline cleanup
# below does not leak these (matches the trap-accumulation pattern used at the
# section boundaries at lines ~218/259).
trap 'rm -f "${CANNED_RESPONSE_FILE}" "${DIRECTIVE_FILE_T}" "${STDIN_CAPTURE}"' EXIT

# Exit code is intentionally NOT asserted here (hence >/dev/null); the observable
# under test is the captured stdin (STDIN_CAPTURE), asserted below.
MOCK_RESPONSE_FILE="${CANNED_RESPONSE_FILE}" \
MOCK_STDIN_FILE="${STDIN_CAPTURE}" \
BEHAVIORAL_EVALS=1 \
CLAUDE_BIN="${PROJECT_ROOT}/tests/fixtures/behavioral-runner/mock-claude.sh" \
ARTIFACTS_DIR="${TMPDIR:-/tmp}/acs-artifacts-$$" \
SKILL_PATH="${PROJECT_ROOT}/skills/incident-analysis/SKILL.md" \
bash "${RUNNER}" \
  --scenario well-formed-scenario \
  --directive-file "${DIRECTIVE_FILE_T}" \
  --pack "${PROJECT_ROOT}/tests/fixtures/behavioral-runner/scenarios.json" >/dev/null 2>&1

directive_captured="$(cat "${STDIN_CAPTURE}" 2>/dev/null)"
assert_contains "directive body is injected into the constructed prompt" "ZZ_UNIQUE_DIRECTIVE_MARKER_9137" "${directive_captured}"
assert_contains "directive is wrapped in an activation_directive block" "activation_directive" "${directive_captured}"
rm -f "${DIRECTIVE_FILE_T}" "${STDIN_CAPTURE}"

# ---------------------------------------------------------------------------
# Verdict: stubbed claude returns a response that does NOT match the assertion
# ---------------------------------------------------------------------------
echo "-- verdict: stubbed claude fail case --"

FAIL_RESPONSE_FILE="${TMPDIR:-/tmp}/acs-mock-fail-$$.txt"
cat > "${FAIL_RESPONSE_FILE}" <<'EOF'
I don't know much about this incident. Could you provide more details?
EOF

output="$(MOCK_RESPONSE_FILE="${FAIL_RESPONSE_FILE}" \
BEHAVIORAL_EVALS=1 \
CLAUDE_BIN="${PROJECT_ROOT}/tests/fixtures/behavioral-runner/mock-claude.sh" \
ARTIFACTS_DIR="${TMPDIR:-/tmp}/acs-artifacts-$$" \
SKILL_PATH="${PROJECT_ROOT}/skills/incident-analysis/SKILL.md" \
bash "${RUNNER}" \
  --scenario well-formed-scenario \
  --pack "${PROJECT_ROOT}/tests/fixtures/behavioral-runner/scenarios.json" 2>&1)"
exit_code=$?

assert_equals "exits 1 when at least one assertion fails" "1" "${exit_code}"
assert_contains "output reports FAIL for the unmatched assertion" "FAIL" "${output}"
assert_contains "output names the failing assertion description" "Mentions exit codes" "${output}"

rm -f "${FAIL_RESPONSE_FILE}"

# ---------------------------------------------------------------------------
# Artifact: runner writes a JSON file with expected fields
# ---------------------------------------------------------------------------
echo "-- artifact: JSON file with expected fields --"

ART_DIR="${TMPDIR:-/tmp}/acs-artifacts-$$"
rm -rf "${ART_DIR}"
mkdir -p "${ART_DIR}"

ART_RESPONSE_FILE="${TMPDIR:-/tmp}/acs-art-resp-$$.txt"
cat > "${ART_RESPONSE_FILE}" <<'EOF'
Exit code 137 suggests OOMKilled termination.
EOF

MOCK_RESPONSE_FILE="${ART_RESPONSE_FILE}" \
    BEHAVIORAL_EVALS=1 \
    CLAUDE_BIN="${PROJECT_ROOT}/tests/fixtures/behavioral-runner/mock-claude.sh" \
    ARTIFACTS_DIR="${ART_DIR}" \
    SKILL_PATH="${PROJECT_ROOT}/skills/incident-analysis/SKILL.md" \
    bash "${RUNNER}" \
        --scenario well-formed-scenario \
        --pack "${PROJECT_ROOT}/tests/fixtures/behavioral-runner/scenarios.json" >/dev/null 2>&1

# Exactly one JSON artifact should exist in ART_DIR
artifact_file="$(ls "${ART_DIR}"/*.json 2>/dev/null | head -n1)"

assert_not_empty "artifact file was created" "${artifact_file}"
assert_json_valid "artifact is valid JSON" "${artifact_file}"

if [ -n "${artifact_file}" ] && [ -f "${artifact_file}" ]; then
    scenario_id="$(jq -r '.scenario_id // empty' "${artifact_file}")"
    model="$(jq -r '.model // empty' "${artifact_file}")"
    raw_output="$(jq -r '.raw_output // empty' "${artifact_file}")"
    overall="$(jq -r '.overall_passed // empty' "${artifact_file}")"
    assertion_count="$(jq '.assertions | length' "${artifact_file}")"

    assert_equals "artifact scenario_id matches" "well-formed-scenario" "${scenario_id}"
    assert_contains "artifact model field is populated" "mock" "${model}"
    assert_not_contains "artifact model is not 'unknown' (parser reaches real .model or .modelUsage key)" "unknown" "${model}"
    assert_contains "artifact raw_output contains captured text" "137" "${raw_output}"
    assert_equals "artifact overall_passed is true" "true" "${overall}"
    assert_equals "artifact records one assertion" "1" "${assertion_count}"
fi

rm -f "${ART_RESPONSE_FILE}"
rm -rf "${ART_DIR}"

# ---------------------------------------------------------------------------
# Sandbox: runner passes --disallowedTools to deny Edit/Write/Bash in inner
# claude -p invocation. Prevents the inner agent from mutating committed
# files during fixture runs (see feedback_inner_claude_p_tool_access.md).
# ---------------------------------------------------------------------------
echo "-- sandbox: --disallowedTools is passed to inner claude -p --"

SANDBOX_RESPONSE_FILE="${TMPDIR:-/tmp}/acs-sandbox-resp-$$.txt"
SANDBOX_ARGS_FILE="${TMPDIR:-/tmp}/acs-sandbox-args-$$.txt"
SANDBOX_ART_DIR="${TMPDIR:-/tmp}/acs-sandbox-art-$$"
# Compose with the earlier trap (line 85) — bash trap-EXIT is single-slot,
# so the earlier CANNED_RESPONSE_FILE must be re-listed here or it leaks.
trap 'rm -f "${CANNED_RESPONSE_FILE}" "${SANDBOX_RESPONSE_FILE}" "${SANDBOX_ARGS_FILE}"; rm -rf "${SANDBOX_ART_DIR}"' EXIT
cat > "${SANDBOX_RESPONSE_FILE}" <<'EOF'
Exit code 137 indicates OOMKilled termination.
EOF

MOCK_RESPONSE_FILE="${SANDBOX_RESPONSE_FILE}" \
    MOCK_ARGS_FILE="${SANDBOX_ARGS_FILE}" \
    BEHAVIORAL_EVALS=1 \
    CLAUDE_BIN="${PROJECT_ROOT}/tests/fixtures/behavioral-runner/mock-claude.sh" \
    ARTIFACTS_DIR="${SANDBOX_ART_DIR}" \
    SKILL_PATH="${PROJECT_ROOT}/skills/incident-analysis/SKILL.md" \
    bash "${RUNNER}" \
        --scenario well-formed-scenario \
        --pack "${PROJECT_ROOT}/tests/fixtures/behavioral-runner/scenarios.json" >/dev/null 2>&1

# Each argv arrives on its own line in MOCK_ARGS_FILE. Checking the line
# *immediately after* --disallowedTools avoids matching the prompt body,
# which contains "Edit"/"Write"/"Bash" as ordinary text from the skill.
flag_line="$(grep -nxF -- '--disallowedTools' "${SANDBOX_ARGS_FILE}" 2>/dev/null | head -n1 | cut -d: -f1)"
sandbox_value=""
if [ -n "${flag_line}" ]; then
    sandbox_value="$(sed -n "$((flag_line + 1))p" "${SANDBOX_ARGS_FILE}")"
fi

assert_not_empty "runner passes --disallowedTools flag as standalone argv" "${flag_line}"
assert_contains "sandbox value denies Edit tool" "Edit" "${sandbox_value}"
assert_contains "sandbox value denies Write tool" "Write" "${sandbox_value}"
assert_contains "sandbox value denies Bash tool" "Bash" "${sandbox_value}"

# ---------------------------------------------------------------------------
# Model pin: --model <name> is threaded to the inner claude -p invocation so
# the probation fixture can pin Haiku vs a baseline model for a comparative
# catch-rate run (see docs/observability.md probation contract).
# ---------------------------------------------------------------------------
echo "-- model pin: --model is passed to inner claude -p --"

MODEL_RESPONSE_FILE="${TMPDIR:-/tmp}/acs-model-resp-$$.txt"
MODEL_ARGS_FILE="${TMPDIR:-/tmp}/acs-model-args-$$.txt"
MODEL_ART_DIR="${TMPDIR:-/tmp}/acs-model-art-$$"
# Compose with the earlier trap (single-slot bash trap-EXIT): re-list all
# prior temp paths so none leak.
trap 'rm -f "${CANNED_RESPONSE_FILE}" "${SANDBOX_RESPONSE_FILE}" "${SANDBOX_ARGS_FILE}" "${MODEL_RESPONSE_FILE}" "${MODEL_ARGS_FILE}"; rm -rf "${SANDBOX_ART_DIR}" "${MODEL_ART_DIR}"' EXIT
cat > "${MODEL_RESPONSE_FILE}" <<'EOF'
Exit code 137 indicates OOMKilled termination.
EOF

MOCK_RESPONSE_FILE="${MODEL_RESPONSE_FILE}" \
    MOCK_ARGS_FILE="${MODEL_ARGS_FILE}" \
    BEHAVIORAL_EVALS=1 \
    CLAUDE_BIN="${PROJECT_ROOT}/tests/fixtures/behavioral-runner/mock-claude.sh" \
    ARTIFACTS_DIR="${MODEL_ART_DIR}" \
    SKILL_PATH="${PROJECT_ROOT}/skills/incident-analysis/SKILL.md" \
    bash "${RUNNER}" \
        --scenario well-formed-scenario \
        --model haiku \
        --pack "${PROJECT_ROOT}/tests/fixtures/behavioral-runner/scenarios.json" >/dev/null 2>&1

model_flag_line="$(grep -nxF -- '--model' "${MODEL_ARGS_FILE}" 2>/dev/null | head -n1 | cut -d: -f1)"
model_value=""
if [ -n "${model_flag_line}" ]; then
    model_value="$(sed -n "$((model_flag_line + 1))p" "${MODEL_ARGS_FILE}")"
fi

assert_not_empty "runner passes --model as standalone argv when set" "${model_flag_line}"
assert_equals "the pinned model value is forwarded verbatim" "haiku" "${model_value}"

# ---------------------------------------------------------------------------
# Model pin (default): without --model, no --model flag is forwarded, so the
# session's configured model is used unchanged.
# ---------------------------------------------------------------------------
echo "-- model pin: --model absent forwards no model flag --"

NOMODEL_ARGS_FILE="${TMPDIR:-/tmp}/acs-nomodel-args-$$.txt"
trap 'rm -f "${CANNED_RESPONSE_FILE}" "${SANDBOX_RESPONSE_FILE}" "${SANDBOX_ARGS_FILE}" "${MODEL_RESPONSE_FILE}" "${MODEL_ARGS_FILE}" "${NOMODEL_ARGS_FILE}"; rm -rf "${SANDBOX_ART_DIR}" "${MODEL_ART_DIR}"' EXIT

MOCK_RESPONSE_FILE="${MODEL_RESPONSE_FILE}" \
    MOCK_ARGS_FILE="${NOMODEL_ARGS_FILE}" \
    BEHAVIORAL_EVALS=1 \
    CLAUDE_BIN="${PROJECT_ROOT}/tests/fixtures/behavioral-runner/mock-claude.sh" \
    ARTIFACTS_DIR="${MODEL_ART_DIR}" \
    SKILL_PATH="${PROJECT_ROOT}/skills/incident-analysis/SKILL.md" \
    bash "${RUNNER}" \
        --scenario well-formed-scenario \
        --pack "${PROJECT_ROOT}/tests/fixtures/behavioral-runner/scenarios.json" >/dev/null 2>&1

nomodel_flag_line="$(grep -nxF -- '--model' "${NOMODEL_ARGS_FILE}" 2>/dev/null | head -n1 | cut -d: -f1)"
assert_equals "no --model flag forwarded when unset" "" "${nomodel_flag_line}"

# ---------------------------------------------------------------------------
# Bare mode: --bare is forwarded to the inner claude -p so the probation can
# strip ambient hooks/LSP/plugin noise (e.g. this plugin's own skill-activation
# banner) from the measured review. Boolean flag — present or absent.
# ---------------------------------------------------------------------------
echo "-- bare mode: --bare is forwarded when set, absent otherwise --"

BARE_ARGS_FILE="${TMPDIR:-/tmp}/acs-bare-args-$$.txt"
NOBARE_ARGS_FILE="${TMPDIR:-/tmp}/acs-nobare-args-$$.txt"
trap 'rm -f "${CANNED_RESPONSE_FILE}" "${SANDBOX_RESPONSE_FILE}" "${SANDBOX_ARGS_FILE}" "${MODEL_RESPONSE_FILE}" "${MODEL_ARGS_FILE}" "${NOMODEL_ARGS_FILE}" "${BARE_ARGS_FILE}" "${NOBARE_ARGS_FILE}"; rm -rf "${SANDBOX_ART_DIR}" "${MODEL_ART_DIR}"' EXIT

MOCK_RESPONSE_FILE="${MODEL_RESPONSE_FILE}" \
    MOCK_ARGS_FILE="${BARE_ARGS_FILE}" \
    BEHAVIORAL_EVALS=1 \
    CLAUDE_BIN="${PROJECT_ROOT}/tests/fixtures/behavioral-runner/mock-claude.sh" \
    ARTIFACTS_DIR="${MODEL_ART_DIR}" \
    SKILL_PATH="${PROJECT_ROOT}/skills/incident-analysis/SKILL.md" \
    bash "${RUNNER}" \
        --scenario well-formed-scenario \
        --bare \
        --pack "${PROJECT_ROOT}/tests/fixtures/behavioral-runner/scenarios.json" >/dev/null 2>&1

bare_flag_line="$(grep -nxF -- '--bare' "${BARE_ARGS_FILE}" 2>/dev/null | head -n1 | cut -d: -f1)"
assert_not_empty "runner forwards --bare when set" "${bare_flag_line}"

MOCK_RESPONSE_FILE="${MODEL_RESPONSE_FILE}" \
    MOCK_ARGS_FILE="${NOBARE_ARGS_FILE}" \
    BEHAVIORAL_EVALS=1 \
    CLAUDE_BIN="${PROJECT_ROOT}/tests/fixtures/behavioral-runner/mock-claude.sh" \
    ARTIFACTS_DIR="${MODEL_ART_DIR}" \
    SKILL_PATH="${PROJECT_ROOT}/skills/incident-analysis/SKILL.md" \
    bash "${RUNNER}" \
        --scenario well-formed-scenario \
        --pack "${PROJECT_ROOT}/tests/fixtures/behavioral-runner/scenarios.json" >/dev/null 2>&1

nobare_flag_line="$(grep -nxF -- '--bare' "${NOBARE_ARGS_FILE}" 2>/dev/null | head -n1 | cut -d: -f1)"
assert_equals "no --bare flag forwarded when unset" "" "${nobare_flag_line}"

# ---------------------------------------------------------------------------
# Assertion kind: absent — mirror of 'text' that PASSES when a regex is NOT
# found in RAW_OUTPUT and FAILS when it is. Built as a scenario-level,
# end-to-end run through the real runner (not a bare grep test) so the
# actual `case "${a_kind}" in absent)` branch is exercised. The pack is a
# throwaway temp file (not a committed fixture) to keep this change scoped
# to this test file only.
# ---------------------------------------------------------------------------
echo "-- assertion kind: absent --"

ABSENT_PACK_FILE="${TMPDIR:-/tmp}/acs-absent-pack-$$.json"
ABSENT_PASS_RESPONSE_FILE="${TMPDIR:-/tmp}/acs-absent-pass-resp-$$.txt"
ABSENT_FAIL_RESPONSE_FILE="${TMPDIR:-/tmp}/acs-absent-fail-resp-$$.txt"
ABSENT_ART_DIR="${TMPDIR:-/tmp}/acs-absent-art-$$"
trap 'rm -f "${CANNED_RESPONSE_FILE}" "${SANDBOX_RESPONSE_FILE}" "${SANDBOX_ARGS_FILE}" "${MODEL_RESPONSE_FILE}" "${MODEL_ARGS_FILE}" "${NOMODEL_ARGS_FILE}" "${BARE_ARGS_FILE}" "${NOBARE_ARGS_FILE}" "${ABSENT_PACK_FILE}" "${ABSENT_PASS_RESPONSE_FILE}" "${ABSENT_FAIL_RESPONSE_FILE}"; rm -rf "${SANDBOX_ART_DIR}" "${MODEL_ART_DIR}" "${ABSENT_ART_DIR}"' EXIT

cat > "${ABSENT_PACK_FILE}" <<'EOF'
[
  {
    "id": "absent-assertion-scenario",
    "prompt": "review this migration",
    "expected_behavior": "Must not mention destructive DDL when the migration is safe.",
    "assertions": [
      {"kind": "absent", "text": "DROP TABLE|TRUNCATE", "description": "Does not mention destructive DDL"}
    ]
  }
]
EOF

cat > "${ABSENT_PASS_RESPONSE_FILE}" <<'EOF'
Reviewed migration: adds a nullable column, safe online.
EOF

cat > "${ABSENT_FAIL_RESPONSE_FILE}" <<'EOF'
This migration will DROP TABLE orders — destructive.
EOF

echo "-- absent: PASSES when regex is missing from output --"

output="$(MOCK_RESPONSE_FILE="${ABSENT_PASS_RESPONSE_FILE}" \
BEHAVIORAL_EVALS=1 \
CLAUDE_BIN="${PROJECT_ROOT}/tests/fixtures/behavioral-runner/mock-claude.sh" \
ARTIFACTS_DIR="${ABSENT_ART_DIR}" \
SKILL_PATH="${PROJECT_ROOT}/skills/incident-analysis/SKILL.md" \
bash "${RUNNER}" \
  --scenario absent-assertion-scenario \
  --pack "${ABSENT_PACK_FILE}" 2>&1)"
exit_code=$?

assert_equals "absent assertion PASSES (exit 0) when regex missing from output" "0" "${exit_code}"
assert_contains "output reports PASS for the absent assertion" "PASS" "${output}"
assert_contains "output tags the assertion as kind absent" "absent" "${output}"

echo "-- absent: FAILS when regex is present in output --"

output="$(MOCK_RESPONSE_FILE="${ABSENT_FAIL_RESPONSE_FILE}" \
BEHAVIORAL_EVALS=1 \
CLAUDE_BIN="${PROJECT_ROOT}/tests/fixtures/behavioral-runner/mock-claude.sh" \
ARTIFACTS_DIR="${ABSENT_ART_DIR}" \
SKILL_PATH="${PROJECT_ROOT}/skills/incident-analysis/SKILL.md" \
bash "${RUNNER}" \
  --scenario absent-assertion-scenario \
  --pack "${ABSENT_PACK_FILE}" 2>&1)"
exit_code=$?

assert_equals "absent assertion FAILS (exit 1) when regex present in output" "1" "${exit_code}"
assert_contains "output reports FAIL for the absent assertion" "FAIL" "${output}"
assert_contains "output names the failing assertion description" "Does not mention destructive DDL" "${output}"

rm -rf "${ABSENT_ART_DIR}"

print_summary
