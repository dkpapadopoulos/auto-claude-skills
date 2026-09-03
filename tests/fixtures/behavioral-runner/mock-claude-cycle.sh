#!/usr/bin/env bash
# mock-claude-cycle.sh — thin wrapper over mock-claude.sh that CYCLES the
# response file across successive invocations, so a scenario can produce an
# INTERMEDIATE pass rate (e.g. 2/3).
#
# Why this exists: the plain mock is fully deterministic, so every measured rate
# in the suite is 0/n or n/n — exactly the rates at which the old truncated-count
# rule (`p >= int(n*0.9)`) and the corrected rate rule (`p*100 >= n*90`) AGREE.
# That blind spot is why a baseline writer still carrying the old rule passed a
# green suite. Any test meant to distinguish the two rules must drive an
# intermediate rate, and only this mock can produce one.
#
# MOCK_RESPONSE_CYCLE     colon-separated list of response files, cycled in order
# MOCK_CYCLE_COUNT_FILE   counter file (created if absent)
# All other behaviour, including the JSON envelope and judge routing, is
# delegated unchanged to mock-claude.sh.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
: "${MOCK_RESPONSE_CYCLE:?mock-claude-cycle: MOCK_RESPONSE_CYCLE unset}"
: "${MOCK_CYCLE_COUNT_FILE:?mock-claude-cycle: MOCK_CYCLE_COUNT_FILE unset}"

_n=0
if [ -f "${MOCK_CYCLE_COUNT_FILE}" ]; then
    _n="$(cat "${MOCK_CYCLE_COUNT_FILE}" 2>/dev/null)"
    case "${_n}" in ''|*[!0-9]*) _n=0 ;; esac
fi
# Bash 3.2: indexed arrays only, and read -a splits on IFS.
IFS=':' read -r -a _files <<< "${MOCK_RESPONSE_CYCLE}"
_count="${#_files[@]}"
[ "${_count}" -gt 0 ] || { echo "mock-claude-cycle: empty cycle" >&2; exit 1; }
_sel="${_files[$(( _n % _count ))]}"
printf '%s' "$(( _n + 1 ))" > "${MOCK_CYCLE_COUNT_FILE}" 2>/dev/null || true

MOCK_RESPONSE_FILE="${_sel}" exec bash "${DIR}/mock-claude.sh" "$@"
