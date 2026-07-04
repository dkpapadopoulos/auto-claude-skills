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

# Judge-call routing: when the runner invokes the judge it passes
# `--model $JUDGE_MODEL`. If MOCK_JUDGE_RESPONSE_FILE is set and argv
# contains the judge model name (tests set JUDGE_MODEL=judge-mock), emit
# the judge response instead of the subject one. Optional two-response
# sequence via MOCK_JUDGE_RESPONSE_FILE2 + MOCK_JUDGE_COUNT_FILE lets a
# retry test serve different payloads per judge call. MOCK_JUDGE_STDIN_FILE
# captures the judge prompt.
#
# Detection: match only the token IMMEDIATELY FOLLOWING --model.
# Limitation: if the subject is pinned to the same model id as the judge,
# argv-only discrimination cannot distinguish them (inherent to CLI parsing).
is_judge_call=0
if [ -n "${MOCK_JUDGE_RESPONSE_FILE:-}" ]; then
    prev=""
    for arg in "$@"; do
        if [ "${prev}" = "--model" ] && [ "${arg}" = "${JUDGE_MODEL:-judge-mock}" ]; then
            is_judge_call=1
            break
        fi
        prev="${arg}"
    done
fi
if [ "${is_judge_call}" = "1" ]; then
    resp_file="${MOCK_JUDGE_RESPONSE_FILE}"
    if [ -n "${MOCK_JUDGE_COUNT_FILE:-}" ] && [ -n "${MOCK_JUDGE_RESPONSE_FILE2:-}" ]; then
        n="$(cat "${MOCK_JUDGE_COUNT_FILE}" 2>/dev/null || printf '0')"
        [ "${n}" -ge 1 ] && resp_file="${MOCK_JUDGE_RESPONSE_FILE2}"
        printf '%s' "$((n + 1))" > "${MOCK_JUDGE_COUNT_FILE}"
    fi
    if [ -n "${MOCK_JUDGE_STDIN_FILE:-}" ]; then
        cat > "${MOCK_JUDGE_STDIN_FILE}" 2>/dev/null || true
    fi
    jq -n --arg result "$(cat "${resp_file}")" --arg model "judge-mock" \
        '{type: "result", result: $result, model: $model, num_turns: 1}'
    exit 0
fi

response_text="$(cat "${MOCK_RESPONSE_FILE}")"
jq -n \
    --arg result "${response_text}" \
    --arg model "mock-claude-v1" \
    '{type: "result", result: $result, model: $model, num_turns: 1}'
