#!/usr/bin/env bash
# mock-claude.sh — Stub 'claude' binary for hermetic eval runner tests.
# Reads the mock response from MOCK_RESPONSE_FILE and emits a JSON envelope
# shaped like 'claude -p --output-format json'.
set -u

if [ -z "${MOCK_RESPONSE_FILE:-}" ] || [ ! -f "${MOCK_RESPONSE_FILE}" ]; then
    echo "mock-claude: MOCK_RESPONSE_FILE unset or missing" >&2
    exit 1
fi

# Optional argv capture: tests may set MOCK_ARGS_FILE to assert on the
# flags the runner passed (e.g. --disallowedTools sandbox). Fail loudly
# if the contract is advertised but the file can't be written, so a future
# test that depends on the captured argv can't pass-by-accident.
if [ -n "${MOCK_ARGS_FILE:-}" ]; then
    if ! printf '%s\n' "$@" > "${MOCK_ARGS_FILE}" 2>/dev/null; then
        echo "mock-claude: failed to write MOCK_ARGS_FILE='${MOCK_ARGS_FILE}'" >&2
        exit 1
    fi
fi

# Optional stdin capture: tests may set MOCK_STDIN_FILE to assert on the
# constructed prompt the runner pipes in on stdin (e.g. --directive-file
# injection). Fail loudly if advertised but unwritable, so a dependent test
# can't pass by accident. When unset, stdin is left untouched.
if [ -n "${MOCK_STDIN_FILE:-}" ]; then
    if ! cat > "${MOCK_STDIN_FILE}" 2>/dev/null; then
        echo "mock-claude: failed to write MOCK_STDIN_FILE='${MOCK_STDIN_FILE}'" >&2
        exit 1
    fi
fi

response_text="$(cat "${MOCK_RESPONSE_FILE}")"
jq -n \
    --arg result "${response_text}" \
    --arg model "mock-claude-v1" \
    '{type: "result", result: $result, model: $model, num_turns: 1}'
