#!/bin/bash
# GREEN FIXTURE (#137) — the same hook with the source correctly guarded.
# The lint must NOT flag this file, and executed it must still reach its deny
# decision even though the lib fails mid-source.

trap 'exit 0' ERR

_ROOT="$(cd "$(dirname "$0")" && pwd)"

_LIB_OK=false
if [ -f "${_ROOT}/lib-returns-nonzero.sh" ]; then
    . "${_ROOT}/lib-returns-nonzero.sh" 2>/dev/null && \
        command -v fixture_helper >/dev/null 2>&1 && _LIB_OK=true || true
fi

# The flag is what makes the fallback reachable; `|| true` on the source alone
# would leave fixture_helper undefined and the call below would trip the trap.
if [ "${_LIB_OK}" = true ]; then
    fixture_helper >/dev/null
fi

echo "DENY_REACHED"
exit 0
