#!/usr/bin/env bash
# test-pasted-content-lib.sh — the pasted-content parser (#409), hooks/lib/pasted-content.sh.
#
# The parser finds the harness's paste wrapper, which in every one of 79 real wrapped
# prompts (2026-10-01..11-16) is: an opener carrying id="<4 lowercase hex>", the pasted
# text, and a closer repeating the SAME id. It replaces each such pair with one newline
# and leaves everything else byte-identical. It is used only by the activation hook's
# shadow record (#409 stage 1), never to change what is scored for routing state.
#
# Inputs: two REAL wrapped prompts and one real negative from this repository's own work
# (tests/fixtures/routing-input/pasted-content/README.md says where each came from). Every
# other input here is DERIVED from those bytes by one stated edit, and says so; no wrapper
# shape is invented, because none was observed beyond the real one (0 unterminated,
# mismatched or nested blocks in 79).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-pasted-content-lib.sh ==="

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not available — pasted-content parser cells NOT run"; exit 0
fi
setup_test_env

LIB="${PROJECT_ROOT}/hooks/lib/pasted-content.sh"
FIX="${PROJECT_ROOT}/tests/fixtures/routing-input/pasted-content"
ONLY="${FIX}/paste-only-escaped-inner-tag.txt"   # real: a paste-only prompt
AROUND="${FIX}/typed-before-and-after.txt"         # real: typed text, a paste, typed text
NEG="${FIX}/negative-issue-409-body.txt"           # real: prose quoting the bare tag names

PASTED_CONTENT_JQ_DEF=""
[ -f "${LIB}" ] && . "${LIB}"

# strip <file> : the parser's result object for the file's exact bytes (trailing newlines kept).
strip() { jq -nc --rawfile t "$1" "${PASTED_CONTENT_JQ_DEF} \$t | paste_strip" 2>/dev/null; }
field() { printf '%s' "$1" | jq -r "$2" 2>/dev/null; }
# derive <out> <jq-expr on $t> : write a derived input from a real one ($t = its exact bytes).
derive() { local src="$1" out="$2" expr="$3"; jq -nj --rawfile t "${src}" "${expr}" > "${out}"; }

# --- L0: the lib exists, defines the parser, and it compiles -----------------------------
if [ -n "${PASTED_CONTENT_JQ_DEF}" ] && jq -n "${PASTED_CONTENT_JQ_DEF} \"\" | paste_strip" >/dev/null 2>&1; then
    _record_pass "L0: lib defines PASTED_CONTENT_JQ_DEF and paste_strip compiles"
else
    _record_fail "L0: lib defines PASTED_CONTENT_JQ_DEF and paste_strip compiles" "missing or does not compile: ${LIB}"
fi

# --- L1: real paste-only prompt -----------------------------------------------------------
r="$(strip "${ONLY}")"
assert_equals "L1: paste-only: status ok" "ok" "$(field "$r" .status)"
assert_equals "L1: paste-only: one opener, one pair" "1 1" "$(field "$r" '"\(.openers) \(.pairs)"')"
assert_equals "L1: paste-only: nothing but the boundary newlines survives" "0" \
    "$(field "$r" '.text | gsub("[\\n]"; "") | length')"
assert_equals "L1: paste-only: the escaped inner tag went with its block" "0" \
    "$(field "$r" '.text | indices("pasted_content") | length')"

# --- L2: real typed-before-and-after prompt -------------------------------------------------
r="$(strip "${AROUND}")"
assert_equals "L2: typed around a paste: one pair" "1" "$(field "$r" .pairs)"
assert_equals "L2: the typed text before the block survives" "true" \
    "$(field "$r" '.text | contains("check the below review on PR406:")')"
assert_equals "L2: the typed text after the block survives" "true" \
    "$(field "$r" '.text | contains("keep going with the remaining tasks")')"
assert_equals "L2: the pasted body is gone" "false" "$(field "$r" '.text | contains("Blocking issues")')"
# Everything outside the block is byte-identical: input minus the block plus one newline.
exp="$(jq -nr --rawfile t "${AROUND}" '$t | (index("<pasted_content id=")) as $a
    | (index("</pasted_content id=")) as $b | ($t[$b:] | index(">")) as $c
    | $t[:$a] + "\n" + $t[($b + $c + 1):]')"
assert_equals "L2: outside the block nothing changed" "${exp}" "$(field "$r" .text)"

# --- L3: boundary — typed words touching the block stay separate tokens (DERIVED) ---------
D3="${TEST_TMPDIR}/touching.txt"   # derived from AROUND: the blank lines around the block removed
derive "${AROUND}" "${D3}" '$t | gsub("\n+(?=<pasted_content id=)"; "") | gsub("(?<=\">)\n+(?=keep going)"; "")'
assert_equals "L3: control: the derived input really has words touching the block" "true" \
    "$(jq -nr --rawfile t "${D3}" '$t | test("PR406:<pasted_content") and test("\">keep going")')"
r="$(strip "${D3}")"
assert_equals "L3: 'PR406:' and 'keep' are split by the replacement newline" "true" \
    "$(field "$r" '.text | contains("PR406:\nkeep going")')"

# --- L4: unterminated block swallows nothing (DERIVED: closer removed) ----------------------
D4="${TEST_TMPDIR}/unterminated.txt"
derive "${AROUND}" "${D4}" '$t | sub("</pasted_content id=\"[0-9a-f]{4}\">"; "")'
r="$(strip "${D4}")"
assert_equals "L4: unterminated: no pair" "0" "$(field "$r" .pairs)"
assert_equals "L4: unterminated: text byte-identical to input" "$(jq -nr --rawfile t "${D4}" '$t')" "$(field "$r" .text)"

# --- L5: closer with a different id matches nothing (DERIVED) -------------------------------
D5="${TEST_TMPDIR}/mismatched.txt"
derive "${AROUND}" "${D5}" '$t | sub("</pasted_content id=\"[0-9a-f]{4}\">"; "</pasted_content id=\"ffff\">")'
r="$(strip "${D5}")"
assert_equals "L5: mismatched id: no pair, text unchanged" "0 true" \
    "$(printf '%s' "$r" | jq -r --rawfile in "${D5}" '"\(.pairs) \(.text == $in)"')"

# --- L6: two blocks with typed text between them (DERIVED: both real blocks joined) ---------
D6="${TEST_TMPDIR}/two-blocks.txt"
jq -nj --rawfile a "${AROUND}" --rawfile o "${ONLY}" \
    '($a | split("\n\n\n\n<pasted_content") | .[0]) + $o + "\nbetween the blocks\n" + ($a | .[(index("\n\n\n\n<pasted_content")):])' > "${D6}"
r="$(strip "${D6}")"
assert_equals "L6: two blocks: two pairs" "2" "$(field "$r" .pairs)"
assert_equals "L6: text between two blocks survives" "true" "$(field "$r" '.text | contains("between the blocks")')"
assert_equals "L6: neither body survives" "false" \
    "$(field "$r" '.text | (contains("Blocking issues") or contains("Work on issue"))')"

# --- L7: id shapes the harness has never produced match nothing (DERIVED) -------------------
for v in upper:'ascii_upcase' long:'. + "a"'; do
    name="${v%%:*}"; f="${v#*:}"
    D7="${TEST_TMPDIR}/id-${name}.txt"
    derive "${ONLY}" "${D7}" "\$t | gsub(\"id=\\\"(?<i>[0-9a-f]{4})\\\"\"; \"id=\\\"\\(.i | ${f})\\\"\")"
    r="$(strip "${D7}")"
    assert_equals "L7: id ${name}: control: the derived input still has a same-id pair" "true" \
        "$(jq -nr --rawfile t "${D7}" '$t | [match("id=\"([^\"]*)\""; "g") | .captures[0].string] | (length == 2 and .[0] == .[1] and .[0] != "4bf8")')"
    assert_equals "L7: id ${name}: status ok, no pair, text unchanged" "ok 0 true" \
        "$(printf '%s' "$r" | jq -r --rawfile in "${D7}" '"\(.status) \(.pairs) \(.text == $in)"')"
done

# --- L8: a backslash-escaped tag in typed text is not an opener (DERIVED: the escaped form
#     from inside the real paste, as typed text) --------------------------------------------
D8="${TEST_TMPDIR}/escaped-typed.txt"
jq -nj --rawfile o "${ONLY}" '$o | capture("(?<x>strip <\\\\pasted_content> blocks)").x' > "${D8}"
assert_equals "L8: control: the derived input is the escaped tag in prose" "strip <\\pasted_content> blocks" "$(cat "${D8}")"
assert_equals "L8: escaped tag in prose: status none" "none" "$(field "$(strip "${D8}")" .status)"

# --- L9: real negative — prose quoting bare tag names ----------------------------------------
r="$(strip "${NEG}")"
assert_equals "L9: control: the negative really quotes the tag" "true" \
    "$(jq -nr --rawfile t "${NEG}" '$t | contains("<pasted_content")')"
assert_equals "L9: issue body: status none, text unchanged" "none true" \
    "$(printf '%s' "$r" | jq -r --rawfile in "${NEG}" '"\(.status) \(.text == $in)"')"

# --- L10: the opener cap (DERIVED: the real opener repeated) ----------------------------------
# More than 16 openers: no regex runs (each unmatched opener costs a scan of the rest of the
# prompt; measured 1,000 openers 0.5 s, 4,000 openers 3.3 s). Exactly 16 still parses.
for n in 16 17; do
    Dn="${TEST_TMPDIR}/openers-${n}.txt"
    jq -nj --rawfile o "${ONLY}" --argjson n "${n}" \
        '($o | match("<pasted_content id=\"[0-9a-f]{4}\">").string) as $op | ($op * ($n - 1)) + $o' > "${Dn}"
    r="$(strip "${Dn}")"
    if [ "${n}" -eq 16 ]; then
        assert_equals "L10: 16 openers: parsed, the one real pair found" "ok 16 1" "$(field "$r" '"\(.status) \(.openers) \(.pairs)"')"
    else
        assert_equals "L10: 17 openers: capped, nothing stripped" "capped 17 0 true" \
            "$(printf '%s' "$r" | jq -r --rawfile in "${Dn}" '"\(.status) \(.openers) \(.pairs) \(.text == $in)"')"
    fi
done

# --- L11: cost bound: 16 unmatched openers before a 1 MB tail (DERIVED) -------------------------
D11="${TEST_TMPDIR}/slow.txt"
jq -nj --rawfile o "${ONLY}" '($o | match("<pasted_content id=\"[0-9a-f]{4}\">").string) as $op
    | ($op * 16) + ("typed text " * 95000)' > "${D11}"
_t0="$(date +%s)"; r="$(strip "${D11}")"; _t1="$(date +%s)"
assert_equals "L11: 16 unmatched openers + 1 MB: parsed, no pair" "ok 0" "$(field "$r" '"\(.status) \(.pairs)"')"
if [ $((_t1 - _t0)) -le 3 ]; then
    _record_pass "L11: and it took $((_t1 - _t0)) s (<= 3)"
else
    _record_fail "L11: 16 unmatched openers + 1 MB within 3 s" "took $((_t1 - _t0)) s"
fi

# --- L12: a regex failure is caught: nothing stripped -------------------------------------------
# The catch is exercised by an ARRAY holding the opener: `indices` counts it (an object would
# count nothing and never reach the regex), then `match` raises on a non-string. A real engine
# failure (a retry limit) takes the same branch.
assert_equals "L12: a raising match yields status error, nothing stripped" "error 0" \
    "$(jq -nrc "${PASTED_CONTENT_JQ_DEF} [\"<pasted_content id=\\\"\"] | paste_strip | \"\(.status) \(.pairs)\"" 2>/dev/null)"

teardown_test_env
print_summary
