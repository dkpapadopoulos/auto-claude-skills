#!/bin/bash
# gate-gaming-check.sh — deterministic detector for test-gate gaming.
# Reads a unified diff on stdin. Prints "clean" or "suspect" (+ offending lines).
# Advisory only; never errors (fail-open => clean) so it cannot break the verifier.
set -u

_diff="$(cat 2>/dev/null || true)"
_hits=""

# Removed assertion lines (deletions of common assert idioms across py/js/ts/java/go).
# Pre-filter unified-diff header lines (--- a/path, +++ b/path) so a keyword in a
# file path cannot false-positive, then match any real deletion line (^-).
_removed="$(printf '%s\n' "$_diff" \
  | grep -vE '^(\-\-\-|\+\+\+)([[:space:]]|$)' \
  | grep -E '^-.*\b(assert|assertEquals|assertThat|assertTrue|assertEqual|expect|t\.Error|t\.Fatal)\b' \
  2>/dev/null || true)"

# Added skip / disable / ignore markers (same header pre-filter as the removed path,
# so a marker substring inside a +++ file path cannot false-positive).
_added_skip="$(printf '%s\n' "$_diff" \
  | grep -vE '^(\-\-\-|\+\+\+)([[:space:]]|$)' \
  | grep -E '^\+.*(@pytest\.mark\.skip|@unittest\.skip|pytest\.skip|xfail|@Disabled|@Ignore|\.skip\(|\bxit\(|\bxdescribe\(|t\.Skip\(|t\.SkipNow)' \
  2>/dev/null || true)"

[ -n "$_removed" ] && _hits="${_removed}"
[ -n "$_added_skip" ] && _hits="${_hits}${_hits:+
}${_added_skip}"

if [ -n "$_hits" ]; then
  echo "suspect"
  printf '%s\n' "$_hits" | sed 's/^/> /'
  exit 0
fi
echo "clean"
exit 0
