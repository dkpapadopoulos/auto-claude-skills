#!/usr/bin/env bash
# test-egress-consent-lib.sh — the single source of the egress consent digest, validators
# and state-file shapes. The dispatcher and both hooks MUST agree on these byte-for-byte:
# a digest that differs between writer and reader turns every approval into a refusal
# (safe, but useless), and a path that differs turns it into a silent no-op.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-egress-consent-lib.sh ==="

LIB="${PROJECT_ROOT}/hooks/lib/egress-consent.sh"
assert_file_exists "egress-consent.sh exists" "${LIB}"
# shellcheck source=/dev/null
. "${LIB}" 2>/dev/null || true

assert_not_equals() {
    # Both sides empty means the function under test produced nothing — not a pass.
    if [ -n "$2" ] && [ "$2" != "$3" ]; then _record_pass "$1"; else _record_fail "$1" "expected values to differ (got '$2' / '$3')"; fi
}
_sha() { printf '%s' "$1" | { shasum -a 256 2>/dev/null || sha256sum; } | cut -d' ' -f1; }

assert_equals "approve label is the fixed contract string" "Approve and send" "${EGRESS_APPROVE_LABEL:-}"
assert_equals "receipt TTL is 900s" "900" "${EGRESS_RECEIPT_TTL:-}"

d_plain="$(printf 'a' | egress_digest_stdin 2>/dev/null)"
assert_equals "digest is sha256 of the bytes" "$(_sha a)" "${d_plain}"
assert_equals "trailing newlines do not change the digest" "${d_plain}" \
    "$(printf 'a\n\n' | egress_digest_stdin 2>/dev/null)"
assert_not_equals "trailing space DOES change the digest" "${d_plain}" \
    "$(printf 'a ' | egress_digest_stdin 2>/dev/null)"
assert_not_equals "leading newline DOES change the digest" "${d_plain}" \
    "$(printf '\na' | egress_digest_stdin 2>/dev/null)"
assert_not_equals "internal whitespace DOES change the digest" \
    "$(printf 'a b' | egress_digest_stdin 2>/dev/null)" "$(printf 'a  b' | egress_digest_stdin 2>/dev/null)"

_ok() { if "$@"; then echo yes; else echo no; fi; }
H="$(printf 'f%.0s' $(seq 1 64))"
assert_equals "valid digest: 64 lowercase hex" "yes" "$(_ok egress_valid_digest "${H}")"
assert_equals "digest: uppercase rejected" "no" "$(_ok egress_valid_digest "$(printf 'F%.0s' $(seq 1 64))")"
assert_equals "digest: 63 chars rejected" "no" "$(_ok egress_valid_digest "${H%f}")"
assert_equals "digest: empty rejected" "no" "$(_ok egress_valid_digest "")"
assert_equals "digest: path chars rejected" "no" "$(_ok egress_valid_digest "../${H}")"
assert_equals "id: toolu_ shape accepted" "yes" "$(_ok egress_valid_id "toolu_016vQv5QPcym3tDmW7A4Ggm3")"
assert_equals "id: traversal rejected" "no" "$(_ok egress_valid_id "../x")"
assert_equals "id: dot rejected (it is the field separator)" "no" "$(_ok egress_valid_id "a.b")"
assert_equals "id: empty rejected" "no" "$(_ok egress_valid_id "")"
assert_equals "token: session- shape accepted" "yes" "$(_ok egress_valid_token "session-20842a10-eb37-4f51")"
assert_equals "token: missing prefix rejected" "no" "$(_ok egress_valid_token "20842a10")"
assert_equals "token: slash rejected" "no" "$(_ok egress_valid_token "session-a/b")"

HOME_SAVE="${HOME}"
T="$(mktemp -d "${TMPDIR:-/tmp}/egress-lib.XXXXXX")"; mkdir -p "${T}/.claude"
HOME="${T}"
assert_equals "ask path shape" "${T}/.claude/.skill-egress-ask-session-x.toolu_1" \
    "$(egress_ask_path session-x toolu_1)"
assert_equals "receipt path shape" "${T}/.claude/.skill-egress-receipt-session-x.${H}.toolu_1" \
    "$(egress_receipt_path session-x "${H}" toolu_1)"
assert_equals "package path shape" "${T}/.claude/.skill-egress-pkg-session-x.${H}" \
    "$(egress_pkg_path session-x "${H}")"

dest="${T}/.claude/out"
printf 'hello' | egress_write_atomic "${dest}"
assert_equals "atomic write stores the bytes" "hello" "$(cat "${dest}" 2>/dev/null)"
assert_equals "atomic write is owner-only" "600" "$(stat -f '%Lp' "${dest}" 2>/dev/null || stat -c '%a' "${dest}")"
assert_equals "atomic write leaves no temp file" "0" \
    "$(find "${T}/.claude" -name 'out.tmp.*' | wc -l | tr -d ' ')"
printf '' | egress_write_atomic "${T}/.claude/empty"; rc=$?
assert_equals "atomic write refuses empty input" "1" "${rc}"
assert_equals "refused empty write leaves no file" "false" "$([ -e "${T}/.claude/empty" ] && echo true || echo false)"
HOME="${HOME_SAVE}"
rm -rf "${T}"

print_summary
