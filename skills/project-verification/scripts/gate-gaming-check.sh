#!/bin/bash
# gate-gaming-check.sh — deterministic detector for test-gate gaming.
# Reads a unified diff on stdin. Prints "clean" or "suspect" (+ offending lines).
# Advisory only and fail-open: exits cleanly (exit 0) on every path so it never aborts
# the verifier. NOTE: empty output is NOT "clean" — the caller (project-verification)
# treats an empty result as "unverified" (script missing / pipe failed), and a normal
# run always prints an explicit "clean" or "suspect".
# Portability: the \b word boundaries below rely on a grep that supports them. GNU grep
# and macOS's GNU-compatible BSD grep (/usr/bin/grep, "BSD grep, GNU compatible") both do;
# a strictly POSIX-only grep would silently under-match (acceptable for an advisory tripwire).
# Known coverage gaps (extend the patterns, don't assume completeness): skip dialects not
# yet matched include RSpec xit/pending, Rust #[ignore], and PHPUnit markTestSkipped(); and
# the caller's default `-- '*test*' '*spec*' '.verify.yml'` pathspec misses non-canonical test
# files (__mocks__/, fixtures/) while selecting documents that merely have "test" or "spec" in
# their path. This script matches TEXT and cannot tell a marker from a quotation of one (#332),
# so WHICH files it is shown is the caller's job: scripts/verify-and-record.sh honours a
# `gate_gaming_paths:` list in the merge-base's .verify.yml. .verify.yml weakening is ENTRY-removal-only: a
# `- name:` deleted and not re-added flags; run:-line rewrites (incl. to a no-op) and
# renames that re-add a name do not. All acceptable for an advisory tripwire — see the
# SKILL.md Limits note.
set -u

_diff="$(cat 2>/dev/null || true)"
_hits=""

# Removed assertion lines (deletions of common assert idioms across py/js/ts/java/go).
# Pre-filter unified-diff header lines (--- a/path, +++ b/path) so a keyword in a
# file path cannot false-positive, then match any real deletion line (^-).
_removed="$(printf '%s\n' "$_diff" \
  | grep -vE '^(\-\-\-|\+\+\+)([[:space:]]|$)' \
  | grep -E '^-.*\b(assert|assertEquals|assertThat|assertTrue|assertEqual|expect[[:space:]]*\(|t\.Error|t\.Fatal)\b' \
  2>/dev/null || true)"

# Added skip / disable / ignore markers (same header pre-filter as the removed path,
# so a marker substring inside a +++ file path cannot false-positive).
_added_skip="$(printf '%s\n' "$_diff" \
  | grep -vE '^(\-\-\-|\+\+\+)([[:space:]]|$)' \
  | grep -E '^\+.*(@pytest\.mark\.skip|@unittest\.skip|pytest\.skip|xfail|@Disabled|@Ignore|\.skip\(|\bxit\(|\bxdescribe\(|t\.Skip\(|t\.SkipNow)' \
  2>/dev/null || true)"

# Removed .verify.yml gate ENTRIES: a `- name:` line deleted and not re-added
# with the same name — the gate DECLARATION shrinking is verification
# weakening (evaluator-surface-advisory). Entry-level (not line-level) on
# purpose: `suspect` is consumed by verdict_is_clean, which routing-governance
# hard-requires, so a line-level pattern would turn a benign run:-rewrite into
# a push DENY (review-caught false-block). File tracking uses BOTH diff
# headers: `+++ /dev/null` (whole-file deletion — the maximal weakening) falls
# back to the `---` side path, and any single-letter prefix (a/ b/ i/ w/ c/,
# incl. none) is stripped so diff.mnemonicPrefix/noprefix gitconfigs cannot
# silently disable detection. run:-line edits, additions, and entry renames
# that re-add a name are NOT flagged, per the coverage-gaps note above.
_removed_gate="$(printf '%s\n' "$_diff" | awk '
  /^--- /    { op = $2; sub(/^[a-zA-Z]\//, "", op); next }
  /^\+\+\+ / { np = $2; sub(/^[a-zA-Z]\//, "", np); f = (np == "/dev/null" ? op : np); next }
  f == ".verify.yml" && /^-[[:space:]]*-[[:space:]]*name:/  { rem[++nr] = $0 }
  f == ".verify.yml" && /^\+[[:space:]]*-[[:space:]]*name:/ {
      n = $0; sub(/^\+[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", n); added[n] = 1
  }
  END {
      for (i = 1; i <= nr; i++) {
          n = rem[i]; sub(/^-[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", n)
          if (!(n in added)) print rem[i]
      }
  }
' 2>/dev/null || true)"

[ -n "$_removed" ] && _hits="${_removed}"
[ -n "$_added_skip" ] && _hits="${_hits}${_hits:+
}${_added_skip}"
[ -n "$_removed_gate" ] && _hits="${_hits}${_hits:+
}${_removed_gate}"

if [ -n "$_hits" ]; then
  echo "suspect"
  printf '%s\n' "$_hits" | sed 's/^/> /'
  exit 0
fi
echo "clean"
exit 0
