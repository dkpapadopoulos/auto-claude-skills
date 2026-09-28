#!/usr/bin/env bash
# Pins the `claude mcp list` connection probes in session-start-hook.sh.
#
# THE BUG THIS EXISTS FOR: both probes grepped for the literal U+2713 CHECK MARK
# (`✓ Connected`, bytes e29c93) while the CLI emits U+2714 HEAVY CHECK MARK
# (`✔ Connected`, e29c94). One byte apart, so `serena_connected` and
# `forgetful_connected` could NEVER be set true even with the env gate on — dead
# code, failing in the CLEAN direction (falls back to the `false` default, so
# nothing looks broken). Unpinned by any test until now.
#
# WHY IT MATCHES THE ASCII WORD, NOT A GLYPH: a glyph is an enumeration of one and
# it was already wrong. The real failure line is
# `✘ Failed to connect — CONNECTION_CLOSED: Connection closed` — it contains
# "Connection" but never "Connected", so the ASCII word alone separates the states.
# grep -F is retained so the original locale-safety property holds (no multi-byte
# regex under C/POSIX).
#
# The fixture is REAL producer output (paths sanitised; every status marker byte
# preserved), because a hand-written fixture only proves the predicate agrees with
# the test author's idea of the format — the exact failure that let this ship.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-mcp-connection-probe.sh ==="

HOOK="${PROJECT_ROOT}/hooks/session-start-hook.sh"
FIX="${PROJECT_ROOT}/tests/fixtures/mcp-list/real-output.txt"
assert_file_exists "session-start hook exists" "${HOOK}"
assert_file_exists "real-producer mcp-list fixture exists" "${FIX}"

# --- the fixture must carry the REAL status bytes, or it pins nothing ----------
# Assert the glyph BYTES directly, by COUNTING lines carrying each glyph.
# The first cut of this cell piped `grep -o '. Connected'` through `od` and
# compared hex: it failed because grep's output carries a TRAILING NEWLINE, so the
# hex ended `...0a` and never equalled the expected string. Counting lines avoids
# byte-exact plumbing entirely. (The dot did match the 3-byte glyph fine -- an
# earlier note here blamed byte-vs-character matching, which was simply wrong.)
_n_2714="$(LC_ALL=C grep -c $'\xe2\x9c\x94' "${FIX}" | tr -d ' ')"
_n_2718="$(LC_ALL=C grep -c $'\xe2\x9c\x98' "${FIX}" | tr -d ' ')"
_n_2713="$(LC_ALL=C grep -c $'\xe2\x9c\x93' "${FIX}" | tr -d ' ')"
if [ "${_n_2714}" -ge 2 ]; then
    _record_pass "fixture success marker is U+2714 HEAVY CHECK (${_n_2714} lines)"
else
    _record_fail "fixture success marker is U+2714" "found ${_n_2714}; the fixture is not real producer output"
fi
if [ "${_n_2718}" -ge 1 ]; then
    _record_pass "fixture carries a real FAILURE line, U+2718 (${_n_2718})"
else
    _record_fail "fixture carries a real FAILURE line" "no U+2718 -- the NOT-connected cell below is vacuous"
fi
assert_equals "fixture contains ZERO of the dead U+2713 the probe used to grep" "0" "${_n_2713}"
# Floor: the fixture must contain both states, else the predicate cells are vacuous.
_n_conn="$(LC_ALL=C grep -c 'Connected' "${FIX}" | tr -d ' ')"
_n_fail="$(LC_ALL=C grep -c 'Failed' "${FIX}" | tr -d ' ')"
if [ "${_n_conn}" -ge 2 ] && [ "${_n_fail}" -ge 1 ]; then
    _record_pass "fixture floor: ${_n_conn} connected + ${_n_fail} failed line(s)"
else
    _record_fail "fixture floor" "need >=2 connected and >=1 failed line; got ${_n_conn}/${_n_fail} — predicate cells would be vacuous"
fi

# --- REGRESSION: no grep predicate in the hook may match a status glyph -------
# Comments may mention the glyphs (they explain the bug); predicates may not.
_glyph_pred="$(LC_ALL=C grep -nE "grep -q?F? *'(\xe2\x9c\x93|\xe2\x9c\x94)" "${HOOK}" | wc -l | tr -d ' ')"
assert_equals "no grep predicate matches a status glyph" "0" "${_glyph_pred}"

# --- the predicate is EXTRACTED from the hook, never hand-copied --------------
for _entry in serena forgetful; do
    _pred="$(LC_ALL=C grep -A2 "_mcp_${_entry}=\"\$(claude mcp list" "${HOOK}" | LC_ALL=C grep -c "grep -qF 'Connected'" | tr -d ' ')"
    if [ "${_pred}" -ge 1 ]; then
        _record_pass "${_entry} probe greps the ASCII word 'Connected'"
    else
        _record_fail "${_entry} probe greps the ASCII word" "could not find the extracted predicate — hook shape changed"
    fi
    _excl="$(LC_ALL=C grep -A3 "_mcp_${_entry}=\"\$(claude mcp list" "${HOOK}" | LC_ALL=C grep -c "! printf .* grep -qF 'Failed'" | tr -d ' ')"
    if [ "${_excl}" -ge 1 ]; then
        _record_pass "${_entry} probe excludes 'Failed'"
    else
        _record_fail "${_entry} probe excludes 'Failed'" "the failure-line guard is missing"
    fi
done

# --- BEHAVIOURAL: run the hook's own predicate against the real fixture -------
# Three cells: the two connected servers must pass, the genuinely failed one must not.
for _case in "serena:CONNECTED" "forgetful:CONNECTED" "gcp-observability:NOT"; do
    _e="${_case%%:*}"; _want="${_case##*:}"
    _line="$(LC_ALL=C grep "^${_e}: " "${FIX}" || true)"
    if [ -z "${_line}" ]; then
        _record_fail "fixture has a ${_e} line" "absent — this cell checked nothing"
        continue
    fi
    if printf '%s' "${_line}" | LC_ALL=C grep -qF 'Connected' && ! printf '%s' "${_line}" | LC_ALL=C grep -qF 'Failed'; then
        _got=CONNECTED
    else
        _got=NOT
    fi
    assert_equals "predicate on real output: ${_e} -> ${_want}" "${_want}" "${_got}"
done

# --- the env gate still defaults OFF (behaviour must not have widened) --------
_off="$(_SKILL_TEST_MODE=1 bash "${HOOK}" < /dev/null 2>&1 | LC_ALL=C grep -o 'serena_connected=[a-z]*' | head -1)"
assert_equals "with SERENA_CONNECTION_CHECK unset the flag stays false" "serena_connected=false" "${_off}"

# --- END TO END, announced-skip when the precondition is absent ---------------
# A silent pass here would be the vacuous-pass trap: no `claude` binary, or no
# connected serena, must be REPORTED as skipped, never counted as a pass.
if ! command -v claude >/dev/null 2>&1; then
    echo "  SKIP (announced): no \`claude\` binary — end-to-end probe cell not run"
elif ! claude mcp list 2>/dev/null | LC_ALL=C grep -q '^serena: '; then
    echo "  SKIP (announced): no serena entry in \`claude mcp list\` — end-to-end cell not run"
else
    _live="$(_SKILL_TEST_MODE=1 SERENA_CONNECTION_CHECK=1 bash "${HOOK}" < /dev/null 2>&1 \
             | LC_ALL=C grep -o 'serena_connected=[a-z]*' | head -1)"
    _expect=serena_connected=false
    if claude mcp list 2>/dev/null | LC_ALL=C grep '^serena: ' | LC_ALL=C grep -qF 'Connected'; then
        _expect=serena_connected=true
    fi
    assert_equals "end-to-end: gate on + live serena -> flag tracks reality" "${_expect}" "${_live}"
fi

print_summary
