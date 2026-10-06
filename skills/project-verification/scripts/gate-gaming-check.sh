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
# This list is NOT the whole rule: see the net-loss families below it.
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

# Assertion families the fixed list above cannot see. `\b` treats `_` as a word character,
# so `\bassert\b` never matched `assert_equals`: a bash, bats or pytest-helper assertion
# could be deleted and the diff read clean. `assertFalse(`, `assertNull(`, `assertRaises(`
# and every other camelCase name outside the four listed were missed the same way.
#
# These are counted PER FILE and flagged only on a NET LOSS (more assertion lines deleted
# than added in that file). So this detects NET REMOVAL of assertions the list above never
# recognised. It is not "the old rule, for more idioms": the fixed list above keeps its
# any-deletion rule exactly as it was, on the same input, and is not loosened here; a diff
# the old rule flags is still flagged (the result is old OR new). The two semantics differ
# for historical reasons, not because the risk differs, and whether the old list should
# move to net loss too is a separate decision for the owner.
#
# Net loss, and not any-deletion, because `suspect` is a push deny: measured over the 537 commits on this repository's mainline that touch tests,
# any-deletion over these families flags 83 of them (ordinary edits to an assertion's
# expected value), net loss per file flags 12. Per file and not over the whole diff, so
# assertions deleted from one file are not paid for by unrelated ones added to another.
#
# `_record_pass` / `_record_fail` are this plugin's own test recorders (a quarter of its
# assertion sites); they are counted with the rest and match nothing elsewhere.
#
# NOT seen, stated so it is not assumed: an assertion replaced by a vacuous or weaker one
# in the same file (the counts balance: `assert_equals "deny" "$d"` swapped for
# `assert_equals "1" "1"` reads clean); any other house idiom that is not named
# assert-something; a comment marker other than `#` or `//`.
# A comment-only line is not counted on either side, so commenting an assertion out IS a
# loss. A method call counts (self.assert_valid(, mock.assert_called_once_with().
#
# A KNOWN FALSE POSITIVE, by design: per file means a test file SPLIT in two, or moved
# with enough edits that git does not see a rename, charges the old file with the loss and
# the new file's assertions cannot pay for it. That reads suspect, and a person has to
# look. The alternative (counting over the whole diff) lets unrelated new tests pay for a
# deleted one.
#
# WHICH FILE a line belongs to is decided by the diff's STRUCTURE, never by what a line
# looks like. A hunk header says how many old and new lines follow, and exactly that many
# are read as the hunk's body. Without this, a source line whose own text began with
# "++ b/other-file" was read as a file header: assertions deleted after it were charged to
# the other file, where unrelated new ones paid for them, and the diff read clean
# (measured). A line outside any hunk is a header or noise and is never counted.
# This assumes a complete two-way unified diff, which is what the caller produces. A
# combined diff (three at-signs) is not read by this pass, and input cut off inside a
# hunk is not detected; in both cases this pass loses coverage and the fixed list above
# is unaffected.
_net_loss="$(printf '%s\n' "$_diff" | awk '
  function is_assert(line,   body) {
      body = substr(line, 2)
      if (body ~ /^[[:space:]]*(#|\/\/)/) return 0
      # A DEFINITION is not an assertion: deleting an unused helper (assert_x() {, or
      # function assert_x) is not a loss of coverage, and counted it would deny a push
      # for tidying a helpers file (found in review).
      # Only name() followed by a brace or the end of the line: `assertNoErrors();` is a
      # call with no arguments, and must still count.
      if (body ~ /^[[:space:]]*(function[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)[[:space:]]*(\{.*)?$/) return 0
      if (body ~ /^[[:space:]]*function[[:space:]]+[A-Za-z_]/) return 0
      if (body ~ /^[[:space:]]*def[[:space:]]+[A-Za-z_]/) return 0
      if (body ~ /(^|[^A-Za-z0-9_])assert_[A-Za-z0-9_]+/) return 1
      if (body ~ /(^|[^A-Za-z0-9_])_record_(pass|fail)([^A-Za-z0-9_]|$)/) return 1
      if (body ~ /(^|[^A-Za-z0-9_])assert[A-Z][A-Za-z0-9]*[[:space:]]*\(/ \
          && body !~ /(^|[^A-Za-z0-9_])(assertEquals|assertThat|assertTrue|assertEqual)[^A-Za-z0-9_]/) return 1
      return 0
  }
  { sub(/\r$/, "") }
  old_left > 0 || new_left > 0 {
      c = substr($0, 1, 1)
      if (c == "-")       { old_left--; if (is_assert($0)) { rem[f]++; if (rem[f] <= 3) shown[f] = shown[f] "\n" $0 } }
      else if (c == "+")  { new_left--; if (is_assert($0)) add[f]++ }
      else if (c != "\\") { old_left--; new_left-- }
      next
  }
  /^@@ -[0-9]+(,[0-9]+)? \+[0-9]+(,[0-9]+)? @@/ {
      n = split($2, o, ","); old_left = (n > 1 ? o[2] + 0 : 1)
      n = split($3, w, ","); new_left = (n > 1 ? w[2] + 0 : 1)
      next
  }
  # The WHOLE path, not its first word: two files whose names share a first word would
  # otherwise share one counter, and one could pay for the other. git appends a tab and
  # metadata only for names with spaces, and quotes unusual names; both forms are kept
  # as git wrote them, so distinct files stay distinct.
  /^--- /    { op = substr($0, 5); sub(/\t.*$/, "", op); sub(/^[a-zA-Z]\//, "", op); next }
  /^\+\+\+ / {
      np = substr($0, 5); sub(/\t.*$/, "", np); sub(/^[a-zA-Z]\//, "", np); f = (np == "/dev/null" ? op : np)
      if (!(f in seen)) { seen[f] = 1; order[++nf] = f }
      next
  }
  END {
      for (i = 1; i <= nf; i++) {
          g = order[i]
          if (rem[g] > add[g] + 0)
              printf "%s: %d assertion line(s) deleted, %d added%s\n", g, rem[g], add[g] + 0, shown[g]
      }
  }
' 2>/dev/null || true)"

[ -n "$_removed" ] && _hits="${_removed}"
[ -n "$_added_skip" ] && _hits="${_hits}${_hits:+
}${_added_skip}"
[ -n "$_removed_gate" ] && _hits="${_hits}${_hits:+
}${_removed_gate}"
[ -n "$_net_loss" ] && _hits="${_hits}${_hits:+
}${_net_loss}"

if [ -n "$_hits" ]; then
  echo "suspect"
  printf '%s\n' "$_hits" | sed 's/^/> /'
  exit 0
fi
echo "clean"
exit 0
