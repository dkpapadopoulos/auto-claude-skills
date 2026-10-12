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
