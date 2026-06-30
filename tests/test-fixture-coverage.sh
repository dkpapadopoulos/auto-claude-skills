#!/usr/bin/env bash
# test-fixture-coverage.sh — every owned, trigger-routed skill must ship a routing
# fixture with at least one MATCH and one NO_MATCH (decoy) line. Closes the
# test-regex-fixtures.sh missing-fixture silent-pass. Bash 3.2 compatible.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FIXTURES_DIR="${SCRIPT_DIR}/fixtures/routing"
TRIGGERS_JSON="${PROJECT_ROOT}/config/default-triggers.json"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-fixture-coverage.sh ==="
command -v jq >/dev/null 2>&1 || { echo "error: jq required" >&2; exit 2; }

# Owned (auto-claude-skills:) skills that have >=1 trigger regex.
owned_with_triggers="$(jq -r '
  .skills[]
  | select((.invoke // "") | contains("auto-claude-skills:"))
  | select((.triggers // []) | length > 0)
  | .name' "${TRIGGERS_JSON}")"

while IFS= read -r skill || [ -n "${skill}" ]; do
    [ -z "${skill}" ] && continue
    fixture="${FIXTURES_DIR}/${skill}.txt"
    if [ ! -f "${fixture}" ]; then
        _record_fail "owned skill '${skill}' has no routing fixture (tests/fixtures/routing/${skill}.txt)"
        continue
    fi
    m="$(grep -c '^[[:space:]]*MATCH:' "${fixture}" 2>/dev/null || true)"
    nm="$(grep -c '^[[:space:]]*NO_MATCH:' "${fixture}" 2>/dev/null || true)"
    m="${m:-0}"; nm="${nm:-0}"
    if [ "${m}" -ge 1 ]; then _record_pass "${skill}.txt has >=1 MATCH"
    else _record_fail "${skill}.txt has no MATCH: line"; fi
    if [ "${nm}" -ge 1 ]; then _record_pass "${skill}.txt has >=1 NO_MATCH decoy"
    else _record_fail "${skill}.txt has no NO_MATCH: decoy line"; fi

    # borrowed-decoy: >=1 NO_MATCH must be a VERBATIM FULL-LINE MATCH in some other
    # fixture. -x requires the whole line to equal "MATCH: <decoy>" exactly, which
    # also inherently excludes "NO_MATCH:" lines — no second-stage filter needed.
    borrowed=0
    while IFS= read -r decoy; do
        [ -z "${decoy}" ] && continue
        if grep -rqxF "MATCH: ${decoy}" "${FIXTURES_DIR}" \
           --include='*.txt' --exclude="${skill}.txt" 2>/dev/null; then
            borrowed=1; break
        fi
    done <<EOD
$(grep '^[[:space:]]*NO_MATCH:' "${fixture}" | sed -e 's/^[[:space:]]*NO_MATCH:[[:space:]]*//')
EOD
    if [ "${borrowed}" -eq 1 ]; then _record_pass "${skill}.txt borrows a real decoy"
    else _record_fail "${skill}.txt NO_MATCH decoy is not borrowed from another fixture"; fi
done <<EOF
${owned_with_triggers}
EOF

print_summary
