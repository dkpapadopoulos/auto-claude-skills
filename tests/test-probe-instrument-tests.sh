#!/bin/bash
# Runs the probe packages' own instrument tests.
#
# These test the CLASSIFIERS, not the product: they assert that the probe and the
# conformance runner read a real stream correctly. Both are deterministic and free —
# the conformance tests stub the provider and assert that stub is in place, so no
# test here can launch a paid run. The paid runner itself remains unwired; see
# tests/probes/README.md.
#
# Wired because an instrument test nobody runs is how conformance.py's classifier
# came to be corrected twice by reading traces instead of by a failing test.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 not available — probe instrument tests NOT checked"
  exit 0
fi

FAIL=0
# Floor per suite. The count was extracted and printed but never compared, so renaming
# a TestCase class so unittest stops collecting it left status 0 and a smaller number
# nobody checked. Python >=3.12 errors on zero collected; 3.11 and earlier report OK.
_floor_for() {
  case "$1" in
    intent-routing/test_intent_probe)      printf '15' ;;
    native-contracts/test_conformance)     printf '30' ;;
    *)                                     printf '1'  ;;
  esac
}
for suite in intent-routing/test_intent_probe native-contracts/test_conformance; do
  dir="${ROOT}/tests/probes/${suite%/*}"
  module="${suite##*/}"
  if [ ! -f "${dir}/${module}.py" ]; then
    echo "FAIL: instrument tests missing (${dir}/${module}.py)"
    FAIL=$((FAIL + 1))
    continue
  fi
  out="$(cd "$dir" && python3 -m unittest "$module" 2>&1 < /dev/null)"
  status=$?
  count="$(printf '%s\n' "$out" | sed -n 's/^Ran \([0-9]*\) test.*/\1/p')"
  if [ "$status" -ne 0 ]; then
    echo "FAIL: ${suite}"
    printf '%s\n' "$out" | tail -20
    FAIL=$((FAIL + 1))
  elif [ "${count:-0}" -lt "$(_floor_for "$suite")" ]; then
    echo "FAIL: ${suite} ran ${count:-0} tests, below the floor of $(_floor_for "$suite")"
    echo "      (a whole TestCase class silently uncollected looks like a smaller pass)"
    FAIL=$((FAIL + 1))
  else
    echo "  ok: ${suite} (${count:-?} tests)"
  fi
done

if [ "$FAIL" -ne 0 ]; then
  echo "test-probe-instrument-tests: ${FAIL} suite(s) failed"
  exit 1
fi
echo "test-probe-instrument-tests: all instrument suites passed"
