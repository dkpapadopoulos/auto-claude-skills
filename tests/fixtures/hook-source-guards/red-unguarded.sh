#!/bin/bash
# RED FIXTURE (#137) — a fail-open hook with an UNGUARDED source.
#
# Never runs as part of the suite (it lives under tests/fixtures/, not
# tests/test-*.sh). Two jobs:
#   1. tests/test-hook-source-guards.sh must FLAG this file's source line.
#   2. Executed, it must demonstrate the actual bypass: the paired lib
#      `lib-returns-nonzero.sh` returns 1 mid-source, which trips the ERR trap,
#      so the hook exits 0 BEFORE reaching its deny decision — the dangerous
#      direction for a safety gate.
#
# Keep the source line below in its bare form. Adding `|| true` here would make
# the lint's own red fixture green and silently disarm the test.

trap 'exit 0' ERR

_ROOT="$(cd "$(dirname "$0")" && pwd)"

# UNGUARDED on purpose — this is the defect under test.
. "${_ROOT}/lib-returns-nonzero.sh"

# In a real gate this is where the deny decision lives. Reaching it at all is
# the assertion: pre-fix, the ERR trap fires above and this never prints.
echo "DENY_REACHED"
exit 0
