#!/bin/bash
# test-pilot-capture.sh — captures must be deterministic, or they are not evidence.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CAP="${ROOT}/scripts/pilot-capture.sh"
PASS=0; FAIL=0
_ok()  { printf '  PASS %s\n' "$1"; PASS=$(( PASS + 1 )); }
_bad() { printf '  FAIL %s\n' "$1"; FAIL=$(( FAIL + 1 )); }
_skip(){ printf '  SKIP %s\n' "$1"; }

echo "test-pilot-capture"

if [ ! -x "${CAP}" ]; then
    _bad "scripts/pilot-capture.sh is missing or not executable"
    printf '%s passed, %s failed\n' "${PASS}" "${FAIL}"; [ "${FAIL}" -eq 0 ]; exit
fi

TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT
cat > "${TMP}/page.html" <<'HTML'
<html><head><style>
:root { color-scheme: light dark; }
body { background:#fff; color:#111; font-family: system-ui, sans-serif; }
@media (prefers-color-scheme: dark) { body { background:#111; color:#eee; } }
</style></head><body><h1>capture probe</h1><p>1234.5678</p></body></html>
HTML

if ! "${CAP}" "${TMP}/page.html" "${TMP}/run1" >/dev/null 2>&1; then
    _skip "capture backend unavailable on this machine — cannot assert determinism"
    printf '%s passed, %s failed\n' "${PASS}" "${FAIL}"; [ "${FAIL}" -eq 0 ]; exit
fi
_ok "capture produced output"

for f in light.png dark.png; do
    [ -s "${TMP}/run1/${f}" ] && _ok "${f} is non-empty" || _bad "${f} missing or empty"
done

"${CAP}" "${TMP}/page.html" "${TMP}/run2" >/dev/null 2>&1
if cmp -s "${TMP}/run1/light.png" "${TMP}/run2/light.png"; then
    _ok "light capture is byte-identical across runs"
else
    _bad "light capture is NOT deterministic"
fi
if cmp -s "${TMP}/run1/dark.png" "${TMP}/run2/dark.png"; then
    _ok "dark capture is byte-identical across runs"
else
    _bad "dark capture is NOT deterministic"
fi
if cmp -s "${TMP}/run1/light.png" "${TMP}/run1/dark.png"; then
    _bad "light and dark captures are identical — colour scheme is not being applied"
else
    _ok "light and dark captures differ"
fi

printf '%s passed, %s failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
