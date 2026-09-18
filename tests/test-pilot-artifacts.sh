#!/bin/bash
# test-pilot-artifacts.sh — the frozen pilot instrument must satisfy the
# pre-registration structurally, not merely exist.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
P="$(cd "${SCRIPT_DIR}/.." && pwd)/openspec/changes/design-seed-capability/pilot"
PASS=0; FAIL=0
_ok()  { printf '  PASS %s\n' "$1"; PASS=$(( PASS + 1 )); }
_bad() { printf '  FAIL %s\n' "$1"; FAIL=$(( FAIL + 1 )); }

echo "test-pilot-artifacts"

for f in rubric.md brief.md budget.md advance-disclosures.md; do
    if [ -r "${P}/${f}" ]; then _ok "${f} exists"; else _bad "${f} missing"; fi
done

# --- the brief must not reveal the treatment -------------------------------
# An arm that can tell it is the seeded arm from the brief is not a control.
_leaks=0
for w in token styleguide "design system" "design seed" palette hypothesis "arm " seeded; do
    if grep -qi -- "${w}" "${P}/brief.md" 2>/dev/null; then
        _bad "brief leaks the treatment: '${w}'"; _leaks=1
    fi
done
[ "${_leaks}" -eq 0 ] && _ok "brief reveals no treatment vocabulary"

# --- the brief must state the embedding contract the egress check relies on -
if grep -q 'id="dion-report"' "${P}/brief.md" 2>/dev/null; then
    _ok "brief states the data-embedding contract"
else
    _bad "brief omits the id=\"dion-report\" embedding contract"
fi

# --- the rubric's dimension table ------------------------------------------
# Rows look like: | R1 | dimension text | source text |
_rows="$(grep -c '^| R[0-9]' "${P}/rubric.md" 2>/dev/null)" || _rows=0
if [ "${_rows}" -ge 5 ]; then _ok "rubric has ${_rows} scored dimensions"; else _bad "rubric has only ${_rows} dimensions (need >= 5)"; fi

# Every row must cite a source (third column non-empty).
_nosrc="$(awk -F'|' '/^\| R[0-9]/ { gsub(/^[ \t]+|[ \t]+$/,"",$4); if ($4 == "") c++ } END { print c+0 }' "${P}/rubric.md" 2>/dev/null)"
if [ "${_nosrc}" = "0" ]; then _ok "every dimension cites a source"; else _bad "${_nosrc} dimension(s) cite no source"; fi

# No scored dimension may reward resemblance to the thing under test.
_bans=0
_dims="$(awk -F'|' '/^\| R[0-9]/ { print $3 }' "${P}/rubric.md" 2>/dev/null)"
for w in token "design system" seed styleguide palette; do
    case "$(printf '%s' "${_dims}" | tr 'A-Z' 'a-z')" in
        *"${w}"*) _bad "rubric scores '${w}' — resemblance to the seed is not quality"; _bans=1 ;;
    esac
done
[ "${_bans}" -eq 0 ] && _ok "no dimension scores resemblance to the seed"

# --- budget must be operational, not aspirational --------------------------
_bmiss=0
for k in cap "stopping rule" timeout retry; do
    grep -qi -- "${k}" "${P}/budget.md" 2>/dev/null || { _bad "budget omits '${k}'"; _bmiss=1; }
done
[ "${_bmiss}" -eq 0 ] && _ok "budget defines cap, stopping rule, timeout and retry"

printf '%s passed, %s failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
