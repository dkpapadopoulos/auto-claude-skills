#!/usr/bin/env bash
# test-frontmatter-hyphen-keys.sh — the SKILL.md frontmatter reader in session-start-hook.sh
# must treat a hyphenated key as a key.
#
# THE DEFECT (reproduced 2026-10-04 on HEAD, first seen with a real gstack install). The
# reader recognised a key only as /^[a-zA-Z_][a-zA-Z0-9_]*:/ — no hyphen. A line such as
# `allowed-tools:` was therefore not a key at all, the key before it stayed current, and the
# list items under `allowed-tools:` were appended to THAT key's list. For gstack's `careful`
# skill the registry said: triggers = ["be careful", "warn before destructive",
# "safety mode", "Bash", "Read"] — tool names as routing triggers. It needs a list-valued key
# directly before the hyphenated one; a scalar in between resets the current key, which is why
# 702 locally installed skills (whose hyphenated keys are all scalars) never showed it.
#
#   F1  the real `careful` frontmatter yields exactly its three triggers
#   F2  control: the real `review` frontmatter (hyphenated list BEFORE triggers) yields
#       exactly its four triggers — this shape was already right, so a failure here means
#       the harness broke, not the parser
#   F3  control: both skills were actually discovered and are available
#   F4  an owned skill that carries a hyphenated scalar key (`disable-model-invocation` in
#       skills/synthesize) keeps the triggers config/default-triggers.json gives it
#   F5  the reader itself, lifted from the hook: a hyphenated key is a BOUNDARY — the list
#       under it is not attached to the key before it and is not emitted at all; a list after
#       a hyphenated SCALAR key is not attached to the key before it either
#   F6  a control character in a frontmatter value cannot wipe every skill's frontmatter.
#       The files are parsed as one batch and handed to `jq --argjson`; one invalid JSON
#       string resets the WHOLE map. Found in review of the first cut of this fix, which
#       emitted hyphenated scalars: `x-note: "one<TAB>two"` did exactly that. The same hazard
#       predates the fix for a non-hyphenated unknown scalar (`version: "1<TAB>2"`), and for a
#       tab inside a trigger. All three are pinned end to end, through the real hook, by
#       checking that ANOTHER skill's triggers survive.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-frontmatter-hyphen-keys.sh ==="

HOOK="${PROJECT_ROOT}/hooks/session-start-hook.sh"
FIX="${PROJECT_ROOT}/tests/fixtures/frontmatter"
if ! command -v jq >/dev/null 2>&1; then
    _record_fail "jq available" "jq is required"; print_summary; exit 1
fi
for _f in gstack-careful.SKILL.md gstack-review.SKILL.md; do
    if [ ! -s "${FIX}/${_f}" ]; then
        _record_fail "fixture ${_f} present" "missing or empty: every cell below would be vacuous"
        print_summary; exit 1
    fi
done

setup_test_env
H="${TEST_TMPDIR}/home"
mkdir -p "${H}/.claude/skills/gstack-careful" "${H}/.claude/skills/gstack-review" "${TEST_TMPDIR}/cwd"
cp "${FIX}/gstack-careful.SKILL.md" "${H}/.claude/skills/gstack-careful/SKILL.md"
cp "${FIX}/gstack-review.SKILL.md" "${H}/.claude/skills/gstack-review/SKILL.md"
( cd "${TEST_TMPDIR}/cwd" && echo '{}' | HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" _SKILL_TEST_MODE=1 \
    /bin/bash "${HOOK}" >/dev/null 2>&1 < /dev/null )
REG="${H}/.claude/.skill-registry-cache.json"
if [ ! -s "${REG}" ]; then
    _record_fail "the session-start hook built a registry" "no registry at ${REG}"
    teardown_test_env; print_summary; exit 1
fi
trig() { jq -c --arg n "$1" '[.skills[] | select(.name == $n)][0].triggers' "${REG}" 2>/dev/null; }

assert_equals "F1: gstack careful has exactly its three triggers (no tool names)" \
    '["be careful","warn before destructive","safety mode"]' "$(trig gstack-careful)"
assert_equals "F2 control: gstack review has exactly its four triggers" \
    '["review this pr","code review","check my diff","pre-landing review"]' "$(trig gstack-review)"
assert_equals "F3 control: both fixtures were discovered and are available" "2" \
    "$(jq '[.skills[] | select((.name == "gstack-careful" or .name == "gstack-review") and .available == true)] | length' "${REG}")"

# F4: an owned skill with a hyphenated scalar key keeps its configured triggers.
if grep -q '^disable-model-invocation:' "${PROJECT_ROOT}/skills/synthesize/SKILL.md"; then
    _record_pass "F4 setup: skills/synthesize carries a hyphenated frontmatter key"
else
    _record_fail "F4 setup: skills/synthesize carries a hyphenated frontmatter key" "the cell below would test nothing"
fi
assert_equals "F4: synthesize keeps the triggers the default config gives it" \
    "$(jq -c '[.skills[] | select(.name == "synthesize")][0].triggers' "${PROJECT_ROOT}/config/default-triggers.json")" \
    "$(trig synthesize)"

# F5: the reader, lifted from the hook with sed (a hand copy would test the copy).
PARSER="$(sed -n '/^_parse_frontmatter() {$/,/^}$/p' "${HOOK}")"
if [ -z "${PARSER}" ]; then
    _record_fail "F5 setup: _parse_frontmatter can be lifted from the hook" "sed found nothing"
else
    eval "${PARSER}"
    U1="${TEST_TMPDIR}/u1.md"
    printf '%s\n' '---' 'name: x' 'triggers:' '  - alpha' 'allowed-tools:' '  - Bash' '  - Read' 'requires:' '  - other' '---' > "${U1}"
    OUT_U1="$(_parse_frontmatter "${U1}")"
    assert_equals "F5: a hyphenated list key keeps its own items" '["alpha"]' "$(printf '%s' "${OUT_U1}" | jq -c '.triggers')"
    assert_equals "F5: and they are not emitted (no consumer reads a hyphenated key)" 'null' "$(printf '%s' "${OUT_U1}" | jq -c '."allowed-tools"')"
    assert_equals "F5: a list after it still reaches its own key" '["other"]' "$(printf '%s' "${OUT_U1}" | jq -c '.requires')"
    U2="${TEST_TMPDIR}/u2.md"
    printf '%s\n' '---' 'name: y' 'triggers:' '  - alpha' 'disable-model-invocation: true' '  - stray' '---' > "${U2}"
    OUT_U2="$(_parse_frontmatter "${U2}")"
    assert_equals "F5: a list item after a hyphenated SCALAR key is not added to the key before it" '["alpha"]' "$(printf '%s' "${OUT_U2}" | jq -c '.triggers')"
    assert_equals "F5: the output is still one valid JSON object" "object" "$(printf '%s' "${OUT_U2}" | jq -r 'type' 2>/dev/null)"
    assert_equals "F5: and a hyphenated scalar is not emitted either" 'null' "$(printf '%s' "${OUT_U2}" | jq -c '."disable-model-invocation"')"
fi

# F6: control characters. Each case adds ONE skill with a tab somewhere in its frontmatter
# next to the gstack fixture, rebuilds the registry through the real hook, and checks that
# the OTHER skill still has its triggers — which is what a batch-wide reset would destroy.
TAB="$(printf '\t')"
f6() { # f6 <label> <frontmatter-line-with-a-tab> [expected-own-triggers]
    local h="${TEST_TMPDIR}/h6-$1" own
    mkdir -p "${h}/.claude/skills/gstack-careful" "${h}/.claude/skills/tabby"
    cp "${FIX}/gstack-careful.SKILL.md" "${h}/.claude/skills/gstack-careful/SKILL.md"
    printf '%s\n' '---' 'name: tabby' 'triggers:' '  - tabby trigger' "$2" '---' '# tabby' > "${h}/.claude/skills/tabby/SKILL.md"
    ( cd "${TEST_TMPDIR}/cwd" && echo '{}' | HOME="${h}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" _SKILL_TEST_MODE=1 \
        /bin/bash "${HOOK}" >/dev/null 2>&1 < /dev/null )
    assert_equals "F6 ($1): the other skill keeps its triggers" \
        '["be careful","warn before destructive","safety mode"]' \
        "$(jq -c '[.skills[] | select(.name == "gstack-careful")][0].triggers' "${h}/.claude/.skill-registry-cache.json" 2>/dev/null)"
    own="$(jq -c '[.skills[] | select(.name == "tabby")][0].triggers' "${h}/.claude/.skill-registry-cache.json" 2>/dev/null)"
    assert_equals "F6 ($1): the skill carrying the tab keeps its own" "${3:-[\"tabby trigger\"]}" "${own}"
}
if grep -q "${TAB}" "${FIX}/gstack-careful.SKILL.md"; then
    _record_fail "F6 setup: the control fixture itself has no tab" "the cells below could not attribute a failure"
else
    _record_pass "F6 setup: the control fixture itself has no tab"
fi
f6 hyphen-scalar "x-note: \"one${TAB}two\""
f6 plain-scalar "version: \"1${TAB}2\""
f6 list-item "  - second${TAB}trigger" '["tabby trigger","second trigger"]'

teardown_test_env
print_summary
