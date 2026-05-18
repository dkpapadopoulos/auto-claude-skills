#!/usr/bin/env bash
# test-detect-serena-languages.sh — assertions for scripts/detect-serena-languages.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DETECTOR="${REPO_ROOT}/scripts/detect-serena-languages.sh"
FIXTURE_ROOT="${REPO_ROOT}/tests/fixtures/language-detection"

# shellcheck source=tests/test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

setup_test_env

assert_file_exists "detector script exists" "${DETECTOR}"
[ -x "${DETECTOR}" ] || { echo "FAIL: detector script not executable"; exit 1; }

# Helper: run detector against a fixture, return sorted output.
_run() {
    bash "${DETECTOR}" "${FIXTURE_ROOT}/$1" 2>/dev/null | sort
}

# typescript-only: package.json + tsconfig.json -> exactly "typescript"
TS_OUT="$(_run typescript-only)"
assert_equals "typescript-only fixture emits 'typescript'" "typescript" "${TS_OUT}"

# polyglot-go-python: go.mod + pyproject.toml -> {"go", "python"}
POLY_OUT="$(_run polyglot-go-python)"
assert_equals "polyglot fixture emits 'go' and 'python'" "$(printf 'go\npython')" "${POLY_OUT}"

# bash-only: only *.sh -> "bash"
BASH_OUT="$(_run bash-only)"
assert_equals "bash-only fixture emits 'bash'" "bash" "${BASH_OUT}"

# empty: no markers -> empty output
EMPTY_OUT="$(_run empty)"
assert_equals "empty fixture emits nothing" "" "${EMPTY_OUT}"

teardown_test_env

if [ "${TESTS_FAILED}" -gt 0 ]; then
    printf "\nFAILED: %d / %d\n" "${TESTS_FAILED}" "${TESTS_RUN}"
    exit 1
fi
printf "\nPASSED: %d / %d\n" "${TESTS_PASSED}" "${TESTS_RUN}"
exit 0
