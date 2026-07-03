#!/bin/bash
# test-db-gate-score.sh — regression guard for the db-gate-race integrity core.
# Wires the scorer's frozen-rule unit tests and the corpus validator into the
# standard suite (tests/run-tests.sh discovers tests/test-*.sh), so a future edit
# to score.sh's comparators (e.g. flipping the inclusive FP ceiling) or a corpus
# regression fails CI instead of passing silently. Bash 3.2 compatible; no set -e.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || { echo "cannot cd to repo root"; exit 1; }

fail=0

echo "== db-gate-race: scorer frozen-rule + aggregation unit tests =="
if bash scripts/db-gate-race/test-score.sh; then
    echo "PASS: score.sh"
else
    echo "FAIL: score.sh"; fail=1
fi

echo "== db-gate-race: held-out corpus structure validator =="
if bash scripts/db-gate-race/validate-corpus.sh; then
    echo "PASS: corpus validator"
else
    echo "FAIL: corpus validator"; fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "test-db-gate-score: ALL PASS"
else
    echo "test-db-gate-score: FAILURES above"
fi
exit "$fail"
