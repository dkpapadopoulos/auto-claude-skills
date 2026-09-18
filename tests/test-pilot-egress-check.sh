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

# Same-line clean artifact (real generator output). MUST be allowed.
printf '<html><body><script type="application/json" id="dion-report">{"ok":true,"command":"report","data":{"report":{"report_id":"r1","proposal_summary":{"orders":[{"symbol":"VWRL","expected_fee_chf":null}]}}}}</script></body></html>\n' > "${TMP}/sameline-clean.html"

# Same-line contaminated bypass test. MUST be refused (catches the original bypass).
{ printf '<html><body><script type="application/json" id="dion-report">{"ok":true,"command":"report","data":{"report":{"report_id":"r1","proposal_summary":{"orders":[{"symbol":"VWRL","expected_fee_chf":null},{"symbol":"REAL","expected_fee_chf":12.5}]}}}}</script>\n'
  printf '{"ok":true,"command":"report","data":{"report":{"report_id":"r1","proposal_summary":{"orders":[{"symbol":"VWRL","expected_fee_chf":null}]}}}}\n'
  printf '</script></body></html>\n'; } > "${TMP}/sameline-dirty.html"

# --- A5: attribute matching must not be quote-blind -------------------------
# A second block under SINGLE quotes. A double-quote-literal matcher does not
# count it at all, so the duplicate refusal never fires and the artifact ships
# with two payloads — the second of which a browser reads perfectly well.
{ printf '<html><body><script type="application/json" id="dion-report">{"ok":true,"command":"report","data":{"report":{"report_id":"r1","proposal_summary":{"orders":[{"symbol":"VWRL","expected_fee_chf":null}]}}}}</script>\n'
  printf "<script type='application/json' id='dion-report'>{\"leak\":true}</script>\n"
  printf '</body></html>\n'; } > "${TMP}/singlequote-second.html"

# A single-quoted block on its OWN is still the designated block and must be
# validated, not ignored. Here its data is clean, so it must be ALLOWED —
# a matcher that simply refuses everything single-quoted would pass the cell
# above for the wrong reason.
{ printf "<html><body><script type='application/json' id='dion-report'>"
  printf '{"ok":true,"command":"report","data":{"report":{"report_id":"r1","proposal_summary":{"orders":[{"symbol":"VWRL","expected_fee_chf":null}]}}}}'
  printf "</script></body></html>\n"; } > "${TMP}/singlequote-clean.html"

# A second application/json block under a DIFFERENT id. The designated block is
# clean; the payload rides alongside it. This is the shape a leak takes once an
# arm knows the designated block is checked.
{ printf '<html><body><script type="application/json" id="dion-report">{"ok":true,"command":"report","data":{"report":{"report_id":"r1","proposal_summary":{"orders":[{"symbol":"VWRL","expected_fee_chf":null}]}}}}</script>\n'
  printf '<script type="application/json" id="holdings">{"positions":[{"symbol":"REAL","qty":420}]}</script>\n'
  printf '</body></html>\n'; } > "${TMP}/second-json-other-id.html"

# A legitimate single-block artifact carrying other non-JSON script tags. Must
# still be ALLOWED — the new refusal is about application/json payloads, not
# about scripts in general, and an artifact that renders needs one.
{ printf '<html><head><style>body{color:#111}</style></head><body>\n'
  printf '<script type="application/json" id="dion-report">{"ok":true,"command":"report","data":{"report":{"report_id":"r1","proposal_summary":{"orders":[{"symbol":"VWRL","expected_fee_chf":null}]}}}}</script>\n'
  printf '<script>document.title="execution list";</script>\n'
  printf '<script type="application/ld+json">{"@context":"https://schema.org"}</script>\n'
  printf '</body></html>\n'; } > "${TMP}/legit-with-scripts.html"

# A block that omits the mandated type= attribute. Refused, by contract.
printf '<html><body><script id="dion-report">{"ok":true,"command":"report","data":{"report":{"report_id":"r1","proposal_summary":{"orders":[{"symbol":"VWRL","expected_fee_chf":null}]}}}}</script></body></html>\n' > "${TMP}/notype.html"

# Attribute ORDER must stay free — id first, type second. Allowed.
printf '<html><body><script id="dion-report" type="application/json">{"ok":true,"command":"report","data":{"report":{"report_id":"r1","proposal_summary":{"orders":[{"symbol":"VWRL","expected_fee_chf":null}]}}}}</script></body></html>\n' > "${TMP}/attr-order.html"

# Malformed JSON on multiple lines (reaches jq parse). MUST be refused with specific message.
{ printf '<html><body><script type="application/json" id="dion-report">\n'
  printf '{this is not valid json}\n'
  printf '</script></body></html>\n'; } > "${TMP}/bad-multiline.html"

_assert_exit_with_msg() { # <expected> <label> <artifact> <fixture> <msg_pattern>
    output=$("${CHECK}" "$3" "$4" 2>&1)
    _got=$?
    if [ "${_got}" = "$1" ] && printf '%s' "${output}" | grep -q "$5"; then
        _ok "$2";
    else
        _bad "$2 (expected exit $1 with msg matching '$5', got ${_got}, output: ${output})";
    fi
}

echo "test-pilot-egress-check"
_assert_exit 0 "clean artifact (reordered keys) is allowed"      "${TMP}/clean.html"   "${TMP}/fixture.json"
_assert_exit 1 "contaminated artifact is refused"                "${TMP}/dirty.html"   "${TMP}/fixture.json"
_assert_exit 1 "artifact with no data block is refused"          "${TMP}/noblock.html" "${TMP}/fixture.json"
_assert_exit 1 "artifact with two data blocks is refused"        "${TMP}/double.html"  "${TMP}/fixture.json"
_assert_exit 1 "artifact with malformed JSON is refused"         "${TMP}/bad.html"     "${TMP}/fixture.json"
_assert_exit 1 "missing fixture is refused"                      "${TMP}/clean.html"   "${TMP}/nope.json"
_assert_exit 0 "same-line clean artifact is allowed"             "${TMP}/sameline-clean.html" "${TMP}/fixture.json"
_assert_exit 1 "same-line contaminated bypass is refused"        "${TMP}/sameline-dirty.html" "${TMP}/fixture.json"
_assert_exit_with_msg 1 "malformed JSON (multiline) reaches jq parse" "${TMP}/bad-multiline.html" "${TMP}/fixture.json" "not valid JSON"
_assert_exit 1 "second block under single quotes is refused"       "${TMP}/singlequote-second.html"   "${TMP}/fixture.json"
_assert_exit 0 "lone single-quoted clean block is allowed"         "${TMP}/singlequote-clean.html"    "${TMP}/fixture.json"
_assert_exit 1 "second application/json block (other id) refused"  "${TMP}/second-json-other-id.html" "${TMP}/fixture.json"
_assert_exit 0 "legitimate artifact with other script tags passes" "${TMP}/legit-with-scripts.html"   "${TMP}/fixture.json"
_assert_exit 1 "block missing the mandated type= attribute is refused" "${TMP}/notype.html"    "${TMP}/fixture.json"
_assert_exit 0 "attribute order (id before type) stays free"          "${TMP}/attr-order.html" "${TMP}/fixture.json"

printf '%s passed, %s failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
