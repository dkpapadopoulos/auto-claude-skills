#!/usr/bin/env bash
# test-paste-shadow-report.sh — the reader for the #409 pasted-content shadow records.
#
# The records are read by nothing else, and a corpus with no reader reaches its pre-registered
# floor unseen (#239). The reader counts what the pre-registration's G0 and its read need: how
# many records, how many saw a real paste pair (the hook payload carries the wrapper), how many
# R would hide a process mandate in, how many look like a changed wrapper format, and how many
# could not be parsed. Records here are written by the REAL hook (round trip), plus one
# malformed file and one unreadable directory.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-paste-shadow-report.sh ==="

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not available — paste-shadow reader cells NOT run"; exit 0
fi
setup_test_env

HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
READER="${PROJECT_ROOT}/scripts/paste-shadow-report.sh"
FIX="${PROJECT_ROOT}/tests/fixtures/routing-input/pasted-content"
ONLY="${FIX}/paste-only-escaped-inner-tag.txt"
AROUND="${FIX}/typed-before-and-after.txt"
H="$(mktemp -d "${TEST_TMPDIR}/h.XXXXXX")"; mkdir -p "${H}/.claude"
jq '.skills |= map(.available = true | .enabled = true)' "${PROJECT_ROOT}/config/default-triggers.json" > "${H}/.claude/.skill-registry-cache.json"
RD="${H}/.claude/.paste-shadow.d"

hook() {   # hook <file> <session> : one real hook turn writing to ${H}
    jq -nc --rawfile p "$1" --arg t "${H}/$2.jsonl" '{prompt:$p, transcript_path:$t}' \
        | env -u ACS_PASTE_SHADOW HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${HOOK}" >/dev/null 2>&1
}
report() { bash "${READER}" "$@" 2>&1; }
val() { printf '%s\n' "$1" | sed -n "s/^$2: //p" | head -1; }

# --- P1: no directory is "no records", said as such ---------------------------------------
out="$(report "${RD}")"; rc=$?
assert_equals "P1: no directory: exit 0" "0" "${rc}"
assert_equals "P1: no directory: records 0" "0" "$(val "${out}" records)"
assert_contains "P1: and it says there is no directory" "no record directory" "${out}"

# --- P2: round trip through the real hook ----------------------------------------------------
UPPER="${TEST_TMPDIR}/upper.txt"   # DERIVED: the real wrapper with its id upper-cased
jq -nj --rawfile t "${ONLY}" '$t | gsub("id=\"(?<i>[0-9a-f]{4})\""; "id=\"\(.i | ascii_upcase)\"")' > "${UPPER}"
touch "${H}/a.jsonl" "${H}/b.jsonl" "${H}/c.jsonl"
hook "${ONLY}" a; hook "${AROUND}" b; hook "${UPPER}" c
assert_equals "P2: control: the hook wrote three records" "3" "$(ls -A "${RD}" 2>/dev/null | wc -l | tr -d ' ')"
out="$(report "${RD}")"; rc=$?
assert_equals "P2: exit 0" "0" "${rc}"
assert_equals "P2: records" "3" "$(val "${out}" records)"
assert_equals "P2: with a paste pair (the payload carries the wrapper)" "2" "$(val "${out}" with_pairs)"
assert_equals "P2: R would hide the process mandate" "1" "$(val "${out}" process_hidden)"
assert_equals "P2: R keeps the process mandate (typed words select it)" "1" "$(val "${out}" process_kept)"
assert_equals "P2: wrapper opener but no pair (format drift)" "1" "$(val "${out}" drift)"
assert_equals "P2: malformed" "0" "$(val "${out}" malformed)"
assert_equals "P2: sessions" "3" "$(val "${out}" sessions)"

# --- P2b: a record whose second selection was skipped by the budget is counted as such --------
LONG="${TEST_TMPDIR}/long.txt"   # DERIVED: AROUND's typed first line repeated past 16 KB, then its block
jq -nj --rawfile a "${AROUND}" '($a | split("\n")[0] + " ") as $line | ($line * ((17000 / ($line | length)) + 1))
    + ($a | .[(index("\n\n\n\n<pasted_content")):])' > "${LONG}"
touch "${H}/d.jsonl"; hook "${LONG}" d
out="$(report "${RD}")"
assert_equals "P2b: records" "4" "$(val "${out}" records)"
assert_equals "P2b: skipped" "1" "$(val "${out}" skipped)"

# --- P3: a malformed file is counted, and the others still are ---------------------------------
printf '{"schema_version":1, broken\n' > "${RD}/zz.bad.json"
out="$(report "${RD}")"
assert_equals "P3: malformed counted" "1" "$(val "${out}" malformed)"
assert_equals "P3: the good records still counted" "4" "$(val "${out}" records)"

# --- P4: an unreadable directory is cannot-check (3), never "no records" -------------------------
if [ "$(id -u)" != "0" ]; then
    chmod 000 "${RD}"
    out="$(report "${RD}")"; rc=$?
    chmod 700 "${RD}"
    assert_equals "P4: unreadable directory: exit 3" "3" "${rc}"
    assert_not_contains "P4: and no count is printed" "records: 0" "${out}"
else
    echo "  SKIP: P4 (running as root; chmod 000 does not deny root)"
fi

teardown_test_env
print_summary
