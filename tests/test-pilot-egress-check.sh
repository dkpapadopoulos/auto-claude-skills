#!/bin/bash
# test-pilot-egress-check.sh — the pre-egress gate must refuse contaminated artifacts.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHECK="${ROOT}/scripts/pilot-egress-check.sh"
PASS=0; FAIL=0
_ok()   { printf '  PASS %s\n' "$1"; PASS=$(( PASS + 1 )); }
_bad()  { printf '  FAIL %s\n' "$1"; FAIL=$(( FAIL + 1 )); }
_assert_exit() { # <expected> <label> <artifact> <fixture>
    "${CHECK}" "$3" "$4" >/dev/null 2>&1
    _got=$?
    if [ "${_got}" = "$1" ]; then _ok "$2"; else _bad "$2 (expected exit $1, got ${_got})"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

cat > "${TMP}/fixture.json" <<'JSON'
{"ok":true,"command":"report","data":{"report":{"report_id":"r1","proposal_summary":{"orders":[{"symbol":"VWRL","expected_fee_chf":null}]}}}}
JSON

# Clean: same data, keys reordered and whitespace added. MUST pass.
{ printf '<html><body><script type="application/json" id="dion-report">\n'
  printf '{ "data" : { "report" : { "proposal_summary" : { "orders" : [ { "expected_fee_chf" : null, "symbol" : "VWRL" } ] }, "report_id" : "r1" } }, "command" : "report", "ok" : true }\n'
  printf '</script></body></html>\n'; } > "${TMP}/clean.html"

# Contaminated: one extra holding that is not in the fixture. MUST be refused.
{ printf '<html><body><script type="application/json" id="dion-report">\n'
  printf '{"ok":true,"command":"report","data":{"report":{"report_id":"r1","proposal_summary":{"orders":[{"symbol":"VWRL","expected_fee_chf":null},{"symbol":"REAL","expected_fee_chf":12.5}]}}}}\n'
  printf '</script></body></html>\n'; } > "${TMP}/dirty.html"

# No data block at all. MUST be refused, never silently allowed.
printf '<html><body><p>no data here</p></body></html>\n' > "${TMP}/noblock.html"

# Two data blocks — ambiguous. MUST be refused.
{ cat "${TMP}/clean.html"; cat "${TMP}/clean.html"; } > "${TMP}/double.html"

# Malformed JSON in the block. MUST be refused.
printf '<html><script type="application/json" id="dion-report">{not json}</script></html>\n' > "${TMP}/bad.html"

echo "test-pilot-egress-check"
_assert_exit 0 "clean artifact (reordered keys) is allowed"      "${TMP}/clean.html"   "${TMP}/fixture.json"
_assert_exit 1 "contaminated artifact is refused"                "${TMP}/dirty.html"   "${TMP}/fixture.json"
_assert_exit 1 "artifact with no data block is refused"          "${TMP}/noblock.html" "${TMP}/fixture.json"
_assert_exit 1 "artifact with two data blocks is refused"        "${TMP}/double.html"  "${TMP}/fixture.json"
_assert_exit 1 "artifact with malformed JSON is refused"         "${TMP}/bad.html"     "${TMP}/fixture.json"
_assert_exit 1 "missing fixture is refused"                      "${TMP}/clean.html"   "${TMP}/nope.json"

printf '%s passed, %s failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
