#!/usr/bin/env bash
# test-regex-fixtures.sh — Per-skill regex trigger fixtures.
#
# Reads every tests/fixtures/routing/<skill>.txt, looks up the skill's
# compiled triggers in config/default-triggers.json, and asserts:
#   MATCH: <prompt>     → at least one trigger regex matches
#   NO_MATCH: <prompt>  → no trigger regex matches
#
# Zero LLM cost. Catches regex drift in config/default-triggers.json
# before merge. Complementary to the LLM-judged trigger-accuracy eval in
# .github/workflows/skill-eval.yml, which covers description drift.
#
# Bash 3.2 compatible (macOS default).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FIXTURES_DIR="${SCRIPT_DIR}/fixtures/routing"
TRIGGERS_JSON="${PROJECT_ROOT}/config/default-triggers.json"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-regex-fixtures.sh ==="

if [ ! -d "${FIXTURES_DIR}" ]; then
    echo "No fixture directory at ${FIXTURES_DIR} — nothing to test."
    print_summary
    exit 0
fi

if [ ! -f "${TRIGGERS_JSON}" ]; then
    echo "error: ${TRIGGERS_JSON} not found" >&2
    exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required for this test" >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# get_triggers_for_skill <skill-name>
# Writes trigger regexes (one per line, newline-terminated) to stdout.
# Empty output = skill not in registry.
# ---------------------------------------------------------------------------
get_triggers_for_skill() {
    local skill="$1"
    # Search skills[] first, then methodology_hints[] (e.g. frontend-playwright)
    local result
    result="$(jq -r --arg n "${skill}" \
        '(.skills[], .methodology_hints[]) | select(.name==$n) | .triggers[]?' \
        "${TRIGGERS_JSON}" 2>/dev/null)"
    printf '%s\n' "${result}"
}

# ---------------------------------------------------------------------------
# find_matching_trigger <lowered-prompt> <triggers-text>
# Prints the first matching trigger regex and returns 0. Returns 1 if none.
# Uses bash =~ (extended regex) — same engine the activation hook uses.
# ---------------------------------------------------------------------------
find_matching_trigger() {
    local lowered="$1"
    local triggers="$2"
    local regex
    # Append trailing newline defensively so `read` sees the last line even
    # when the input was captured via command substitution that stripped it.
    while IFS= read -r regex || [ -n "${regex}" ]; do
        [ -z "${regex}" ] && continue
        if [[ "${lowered}" =~ $regex ]]; then
            printf '%s\n' "${regex}"
            return 0
        fi
    done <<EOF
${triggers}
EOF
    return 1
}

# ---------------------------------------------------------------------------
# Process each fixture file
# ---------------------------------------------------------------------------
fixture_count=0
for fixture in "${FIXTURES_DIR}"/*.txt; do
    [ -f "${fixture}" ] || continue
    fixture_count=$((fixture_count + 1))

    skill="$(basename "${fixture}" .txt)"
    triggers="$(get_triggers_for_skill "${skill}")"
    if [ -z "${triggers}" ]; then
        _record_fail "skill '${skill}' (fixture=${fixture}) has no entry in config/default-triggers.json"
        continue
    fi

    line_no=0
    while IFS= read -r line || [ -n "${line}" ]; do
        line_no=$((line_no + 1))
        trimmed="$(printf '%s' "${line}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [ -z "${trimmed}" ] && continue
        case "${trimmed}" in
            \#*) continue ;;
        esac

        case "${trimmed}" in
            MATCH:*)
                prompt="$(printf '%s' "${trimmed#MATCH:}" | sed -e 's/^[[:space:]]*//')"
                lowered="$(printf '%s' "${prompt}" | tr '[:upper:]' '[:lower:]')"
                if find_matching_trigger "${lowered}" "${triggers}" >/dev/null; then
                    _record_pass "${skill}:${line_no} MATCH: ${prompt}"
                else
                    _record_fail "${skill}:${line_no} expected MATCH but no trigger matched: ${prompt}"
                fi
                ;;
            NO_MATCH:*)
                prompt="$(printf '%s' "${trimmed#NO_MATCH:}" | sed -e 's/^[[:space:]]*//')"
                lowered="$(printf '%s' "${prompt}" | tr '[:upper:]' '[:lower:]')"
                matched_regex="$(find_matching_trigger "${lowered}" "${triggers}" 2>/dev/null || true)"
                if [ -z "${matched_regex}" ]; then
                    _record_pass "${skill}:${line_no} NO_MATCH: ${prompt}"
                else
                    _record_fail "${skill}:${line_no} expected NO_MATCH but matched /${matched_regex}/: ${prompt}"
                fi
                ;;
            *)
                _record_fail "${skill}:${line_no} invalid directive (expected MATCH: or NO_MATCH:): ${trimmed}"
                ;;
        esac
    done < "${fixture}"
done

if [ "${fixture_count}" -eq 0 ]; then
    echo "No fixture files under ${FIXTURES_DIR}/*.txt — nothing to test."
fi

print_summary
