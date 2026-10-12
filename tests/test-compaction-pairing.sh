#!/bin/bash
# test-compaction-pairing.sh — scripts/compaction-pairing.sh reads
# ~/.claude/.compact-events.log and says whether every compaction was followed
# by a recovery (SessionStart(compact) via compact-recovery-hook.sh, or the
# prompt carrier) before the next compaction.
#
# Fixture lines are copied from the REAL log's shapes (2026-10-12), not
# hand-written: `<ts> trigger=auto|manual size_bytes=N path=<jsonl>`,
# `<ts> event=post_compact size_bytes=N path=<jsonl>`,
# `<ts> event=post_compact_prompt trigger=auto`.
#
# Exit codes are the contract (same shape as scripts/assert-suite-complete.sh):
#   0 every compaction paired, 1 at least one unpaired, 3 cannot check
#   (missing or empty log). 3 is separate from 0 on purpose: an empty log must
#   never read as "paired".

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
READER="${PROJECT_ROOT}/scripts/compaction-pairing.sh"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-compaction-pairing.sh ==="
setup_test_env

_fx="${TEST_TMPDIR}/fx"; mkdir -p "${_fx}"
_S1="/Users/x/.claude/projects/-p/aaaa.jsonl"
_S2="/Users/x/.claude/projects/-p/bbbb.jsonl"

# A: fully paired (two auto compactions, each followed by a SessionStart recovery).
cat > "${_fx}/paired.log" <<EOF
2026-09-04T21:03:35Z trigger=auto size_bytes=100 path=${_S1}
2026-09-04T21:05:16Z event=post_compact size_bytes=50 path=${_S1}
2026-09-05T16:09:08Z trigger=auto size_bytes=100 path=${_S2}
2026-09-05T16:11:03Z event=post_compact size_bytes=50 path=${_S2}
EOF

# B: a genuinely unpaired compaction: the 20:08 auto compaction gets NO recovery of
# either kind before the same session compacts again at 21:26 (which is then
# recovered). In the real October log the carrier fired at 21:26:42, just before the
# second compaction, and so PAIRED the 20:08 one; that shape is fixture D below.
cat > "${_fx}/unpaired.log" <<EOF
2026-10-01T20:08:31Z trigger=auto size_bytes=100 path=${_S1}
2026-10-01T21:26:42Z trigger=auto size_bytes=100 path=${_S1}
2026-10-01T21:29:08Z event=post_compact size_bytes=50 path=${_S1}
2026-10-10T15:58:17Z trigger=manual size_bytes=100 path=${_S2}
2026-10-10T16:00:28Z event=post_compact size_bytes=50 path=${_S2}
EOF

# D: the real October shape, copied line for line: the carrier recovers the 20:08
# compaction at the next prompt, 78 minutes later, so it is paired, and the
# per-month carrier count is how many compactions SessionStart missed.
cat > "${_fx}/carrier-real.log" <<EOF
2026-10-01T20:08:31Z trigger=auto size_bytes=100 path=${_S1}
2026-10-01T21:26:42Z event=post_compact_prompt trigger=auto
2026-10-01T21:26:42Z trigger=auto size_bytes=100 path=${_S1}
2026-10-01T21:29:08Z event=post_compact size_bytes=50 path=${_S1}
EOF

# C: carrier-only recovery counts as paired.
cat > "${_fx}/carrier.log" <<EOF
2026-10-01T20:08:31Z trigger=auto size_bytes=100 path=${_S1}
2026-10-01T20:30:00Z event=post_compact_prompt trigger=auto
EOF

: > "${_fx}/empty.log"

# E: a non-empty log in which NO line is one of the three shapes. Parsed nothing, so it
# must be cannot-check (3), never "all paired" over zero compactions (review, PR 6).
cat > "${_fx}/garbage.log" <<EOF
garbage line one
2026-10-01T20:08:31Z something=else path=${_S1}
EOF

# F: one good compaction plus a line of a shape the reader does not know. pre-compact-hook
# writes trigger=unknown when the payload carries no trigger; dropping it silently would
# under-count compactions. Must be listed and exit 1.
cat > "${_fx}/unrecognised.log" <<EOF
2026-10-01T20:08:31Z trigger=auto size_bytes=100 path=${_S1}
2026-10-01T20:10:00Z event=post_compact size_bytes=50 path=${_S1}
2026-10-02T09:00:00Z trigger=unknown size_bytes=100 path=${_S2}
EOF

# G: two sessions open when a carrier recovery arrives. SessionStart recoveries land
# within ~2 minutes of their compaction (every one in the real log); the carrier fires at
# the NEXT PROMPT, often much later. So the carrier belongs to the OLDER open compaction,
# whose SessionStart is overdue, and the newer one's SessionStart is still coming. A
# "most recent open" rule closes B here, orphans B's own recovery and leaves A pending.
cat > "${_fx}/two-open.log" <<EOF
2026-10-01T20:08:31Z trigger=auto size_bytes=100 path=${_S1}
2026-10-01T20:20:00Z trigger=auto size_bytes=100 path=${_S2}
2026-10-01T20:30:00Z event=post_compact_prompt trigger=auto
2026-10-01T20:31:00Z event=post_compact size_bytes=50 path=${_S2}
EOF

# H: an open compaction at the end of the log is PENDING (the session may be live): exit 0,
# and the pending compaction is LISTED, so a perpetual "1 pending" can be traced.
cat > "${_fx}/pending.log" <<EOF
2026-10-01T20:08:31Z trigger=auto size_bytes=100 path=${_S1}
2026-10-01T20:10:00Z event=post_compact size_bytes=50 path=${_S1}
2026-10-01T22:00:00Z trigger=auto size_bytes=100 path=${_S2}
EOF

# I: a SessionStart recovery for a session with no logged compaction (a stray): the
# pre-compact hook failed to log, or the two hooks saw different transcript paths. It is a
# producer defect worth seeing, so it is listed and kept OUT of sessionstart= (otherwise
# sessionstart + carrier would exceed the compactions and the counts cannot be reconciled).
# It does not change the exit code on its own.
cat > "${_fx}/stray.log" <<EOF
2026-10-01T20:08:31Z trigger=auto size_bytes=100 path=${_S1}
2026-10-01T20:10:00Z event=post_compact size_bytes=50 path=${_S1}
2026-10-01T21:00:00Z event=post_compact size_bytes=50 path=${_S2}
EOF

_run() { bash "${READER}" "$1" > "${TEST_TMPDIR}/out.txt" 2>&1; echo $?; }

_rc="$(_run "${_fx}/paired.log")"
assert_equals "paired log exits 0" "0" "${_rc}"
# Positive wording required: an empty output would also contain no "unpaired".
if grep -q "all paired" "${TEST_TMPDIR}/out.txt" && ! grep -q "^unpaired:" "${TEST_TMPDIR}/out.txt"; then
    _record_pass "paired log says all paired and lists no unpaired compaction"
else
    _record_fail "paired log says all paired and lists no unpaired compaction" "$(cat "${TEST_TMPDIR}/out.txt")"
fi
if grep -q "2026-09: auto=2 manual=0 sessionstart=2 carrier=0" "${TEST_TMPDIR}/out.txt"; then
    _record_pass "per-month counts are reported in a fixed shape"
else
    _record_fail "per-month counts" "expected '2026-09: auto=2 manual=0 sessionstart=2 carrier=0' in: $(cat "${TEST_TMPDIR}/out.txt")"
fi

_rc="$(_run "${_fx}/unpaired.log")"
assert_equals "unpaired log exits 1" "1" "${_rc}"
if grep -q "2026-10-01T20:08:31Z" "${TEST_TMPDIR}/out.txt"; then
    _record_pass "the unpaired compaction's timestamp is printed"
else
    _record_fail "unpaired timestamp" "20:08:31 not named in: $(cat "${TEST_TMPDIR}/out.txt")"
fi
if grep -q "2026-10: auto=2 manual=1 sessionstart=2 carrier=0" "${TEST_TMPDIR}/out.txt"; then
    _record_pass "October counts match the fixture (2 auto, 1 manual, 2 SessionStart, 0 carrier)"
else
    _record_fail "October counts" "$(cat "${TEST_TMPDIR}/out.txt")"
fi

_rc="$(_run "${_fx}/carrier.log")"
assert_equals "a carrier recovery pairs a compaction (exit 0)" "0" "${_rc}"
# Exit 0 alone is vacuous here: with the carrier rule deleted the compaction is merely
# pending, which is also exit 0. The pairing shows only in the pending count.
if grep -q "summary: 1 compactions, all paired, 0 pending" "${TEST_TMPDIR}/out.txt"; then
    _record_pass "carrier-only log has 0 pending (the carrier actually closed it)"
else
    _record_fail "carrier-only pending count" "$(cat "${TEST_TMPDIR}/out.txt")"
fi

_rc="$(_run "${_fx}/pending.log")"
assert_equals "an open compaction at the end of the log is pending, exit 0" "0" "${_rc}"
if grep -q "summary: 2 compactions, all paired, 1 pending" "${TEST_TMPDIR}/out.txt" \
   && grep -q "^pending: 2026-10-01T22:00:00Z (auto, ${_S2})" "${TEST_TMPDIR}/out.txt"; then
    _record_pass "the pending compaction is counted and listed with timestamp, trigger and path"
else
    _record_fail "pending listing" "$(cat "${TEST_TMPDIR}/out.txt")"
fi

_rc="$(_run "${_fx}/stray.log")"
assert_equals "a stray SessionStart recovery does not change the exit code (0)" "0" "${_rc}"
if grep -q "2026-10: auto=1 manual=0 sessionstart=1 carrier=0" "${TEST_TMPDIR}/out.txt" \
   && grep -q "^stray-sessionstart: 2026-10-01T21:00:00Z (${_S2})" "${TEST_TMPDIR}/out.txt"; then
    _record_pass "a stray SessionStart is listed and kept out of sessionstart="
else
    _record_fail "stray SessionStart handling" "$(cat "${TEST_TMPDIR}/out.txt")"
fi

_rc="$(_run "${_fx}/carrier-real.log")"
assert_equals "the real October shape is paired by the carrier (exit 0)" "0" "${_rc}"
if grep -q "2026-10: auto=2 manual=0 sessionstart=1 carrier=1" "${TEST_TMPDIR}/out.txt"; then
    _record_pass "real shape: one SessionStart miss shows as carrier=1, the retirement signal"
else
    _record_fail "real shape counts" "$(cat "${TEST_TMPDIR}/out.txt")"
fi

_rc="$(_run "${_fx}/empty.log")"
assert_equals "empty log exits 3 (cannot check)" "3" "${_rc}"
if grep -qi "cannot check" "${TEST_TMPDIR}/out.txt" && ! grep -qi "paired" "${TEST_TMPDIR}/out.txt"; then
    _record_pass "empty log says cannot-check and never says paired"
else
    _record_fail "empty log wording" "$(cat "${TEST_TMPDIR}/out.txt")"
fi

_rc="$(_run "${_fx}/does-not-exist.log")"
assert_equals "missing log exits 3 (cannot check)" "3" "${_rc}"

_rc="$(_run "${_fx}/garbage.log")"
assert_equals "a log with no recognised line exits 3, not 'all paired' over zero compactions" "3" "${_rc}"
if grep -qi "cannot check" "${TEST_TMPDIR}/out.txt" && ! grep -qi "paired" "${TEST_TMPDIR}/out.txt"; then
    _record_pass "garbage log says cannot-check and never says paired"
else
    _record_fail "garbage log wording" "$(cat "${TEST_TMPDIR}/out.txt")"
fi

_rc="$(_run "${_fx}/unrecognised.log")"
assert_equals "an unrecognised line among good ones exits 1" "1" "${_rc}"
if grep -q "^unrecognised: 2026-10-02T09:00:00Z" "${TEST_TMPDIR}/out.txt"; then
    _record_pass "the unrecognised line is listed with its timestamp"
else
    _record_fail "unrecognised listing" "$(cat "${TEST_TMPDIR}/out.txt")"
fi

_rc="$(_run "${_fx}/two-open.log")"
assert_equals "carrier with two sessions open: both end paired (exit 0)" "0" "${_rc}"
if grep -q "summary: 2 compactions, all paired, 0 pending" "${TEST_TMPDIR}/out.txt"; then
    _record_pass "carrier closes the OLDER open compaction, so the newer one's SessionStart still pairs"
else
    _record_fail "two-open pairing" "$(cat "${TEST_TMPDIR}/out.txt")"
fi

# Default path: with no argument the reader uses ~/.claude/.compact-events.log;
# under the test HOME that file is absent, so the default path must also be 3.
bash "${READER}" > "${TEST_TMPDIR}/out.txt" 2>&1; _rc=$?
assert_equals "default path under an empty HOME exits 3" "3" "${_rc}"

# Portability: the reader must be bash 3.2 clean and run under /bin/bash.
if /bin/bash -n "${READER}" 2>/dev/null; then
    _record_pass "reader parses under /bin/bash (3.2)"
else
    _record_fail "reader /bin/bash -n" "syntax error under /bin/bash"
fi

teardown_test_env
print_summary
