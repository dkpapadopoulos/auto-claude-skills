#!/usr/bin/env bash
# test-activation-registry-extract.sh — the activation hook reads the registry with ONE
# jq call that validates it and emits every section scoring needs (skills, methodology
# hints, required_when pairs, all phases' compositions). It replaced five calls, about
# 11ms of fixed overhead (openspec/changes/composition-contract-fixes/PERF-activation-hook.md).
#
# What batching could break, and what each cell pins:
#   C1  the cache really is read once, and the old `jq empty` validation is gone
#   C2  a malformed entry still costs only its own section, and never the whole cache
#   C3  an unparseable cache still falls back exactly as a missing one does
#   C4  composition lines come from the CURRENT phase only (all phases are extracted)
#   C5  a multi-line composition value keeps its continuation lines, in its own phase
#   C6  each JSON document is isolated, as jq's CLI isolated them per call: skills, hints
#       and compositions all still come from a document after a malformed one
#   C7  an RS in registry text, or in a phase key, cannot shift the sections
#   C8  a phase key containing a newline, US or NUL cannot forge another phase's lines
#   C9  methodology hints still render
#   C10 the SKILL_EXPLAIN trace still scores the skills
# C6-C8 pin the equivalence breaks independent review found in earlier versions.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-activation-registry-extract.sh ==="

HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
REAL_JQ="$(command -v jq 2>/dev/null)"
if [ -z "${REAL_JQ}" ]; then
    _record_fail "jq available" "jq is required"
    print_summary
    exit 1
fi

setup_test_env
BASE_HOME="${TEST_TMPDIR}/base"
mkdir -p "${BASE_HOME}/.claude"
echo '{}' | HOME="${BASE_HOME}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
    /bin/bash "${PROJECT_ROOT}/hooks/session-start-hook.sh" >/dev/null 2>&1
CACHE0="${BASE_HOME}/.claude/.skill-registry-cache.json"

# Every skill and plugin available, plus a marker skill that exists ONLY in the cache,
# so its presence in the output proves the cache (not the fallback registry) was used.
FULL="${TEST_TMPDIR}/full.json"
"${REAL_JQ}" '
  .skills |= (map(.available = true | .enabled = true) + [{
    name: "zz-marker-skill", role: "domain", priority: 0, available: true, enabled: true,
    invoke: "Skill(test:zz-marker-skill)", phase: "", triggers: ["zzmarker"]}])
  | .plugins |= map(.available = true)
' "${CACHE0}" > "${FULL}" 2>/dev/null

if ! "${REAL_JQ}" -e '.skills | length > 1' "${FULL}" >/dev/null 2>&1; then
    _record_fail "setup: registry built" "session-start produced no usable registry"
    teardown_test_env
    print_summary
    exit 1
fi

# run_hook <registry-file|-> <prompt> [extra env...] : prints the hook's stdout.
# "-" runs with no cache file at all.
run_hook() {
    local reg="$1" prompt="$2"; shift 2
    local h
    h="$(mktemp -d "${TEST_TMPDIR}/run.XXXXXX")"
    mkdir -p "${h}/.claude"
    [ "${reg}" != "-" ] && cp "${reg}" "${h}/.claude/.skill-registry-cache.json"
    "${REAL_JQ}" -nc --arg p "${prompt}" --arg t "${h}/.claude/a.jsonl" \
        '{prompt:$p,transcript_path:$t}' \
      | env HOME="${h}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
            SKILL_PROJECT_ROOT="${TEST_TMPDIR}" "$@" /bin/bash "${HOOK}" 2>/dev/null
}

# ---------------------------------------------------------------------------
# C1: one jq read of the registry file, and no separate validation call.
# ---------------------------------------------------------------------------
SHIM="${TEST_TMPDIR}/shim"
mkdir -p "${SHIM}"
JQLOG="${TEST_TMPDIR}/jq.log"
cat > "${SHIM}/jq" <<EOF
#!/bin/bash
printf '%s\x1e' "\$*" >> "${JQLOG}"
exec "${REAL_JQ}" "\$@"
EOF
chmod +x "${SHIM}/jq"
: > "${JQLOG}"
OUT1="$(run_hook "${FULL}" "debug the flaky login test zzmarker" PATH="${SHIM}:${PATH}")"
# Records are RS-terminated, so two jq processes of one pipeline cannot merge.
N_ALL="$(tr -cd '\036' < "${JQLOG}" | wc -c | tr -d ' ')"
N_CACHE="$(tr '\036\n' '\n ' < "${JQLOG}" | grep -c '\.skill-registry-cache\.json')"
N_EMPTY="$(tr '\036\n' '\n ' < "${JQLOG}" | grep -c '^empty ')"
# The old per-section calls read the registry from STDIN, so they never name the file;
# count calls by what their program extracts instead.
N_SECTIONS="$(tr '\036\n' '\n ' < "${JQLOG}" | grep -c 'methodology_hints\|phase_compositions\|required_when')"
if [ "${N_ALL}" -gt 1 ]; then
    _record_pass "C1 setup: the jq shim recorded the hook's calls (${N_ALL})"
else
    _record_fail "C1 setup: the jq shim recorded the hook's calls" "recorded ${N_ALL}"
fi
assert_contains "C1 setup: the hook routed the prompt" "Skill(test:zz-marker-skill)" "${OUT1}"
assert_equals "C1: the registry cache file is opened by exactly one jq call" "1" "${N_CACHE}"
assert_equals "C1: one jq call extracts hints, compositions and required_when" "1" "${N_SECTIONS}"
assert_equals "C1: no separate 'jq empty' validation call" "0" "${N_EMPTY}"

# ---------------------------------------------------------------------------
# C2: fault isolation. A broken plugin list breaks the hint and composition
# sections; the skills section, extracted from the same call, must survive, and
# the cache must not be abandoned for the fallback registry.
# ---------------------------------------------------------------------------
BROKEN="${TEST_TMPDIR}/broken-plugins.json"
"${REAL_JQ}" '.plugins = "broken"' "${FULL}" > "${BROKEN}"
OUT2="$(run_hook "${BROKEN}" "debug the flaky login test zzmarker")"
assert_contains "C2: skills still route when the plugin list is malformed" \
    "Skill(test:zz-marker-skill)" "${OUT2}"
assert_contains "C2: the process skill is still selected" \
    "Skill(superpowers:systematic-debugging)" "${OUT2}"
# A malformed skill AFTER the marker ends the skills section there; the skills already
# emitted (the marker among them) must survive, as they did with a separate call.
BADSKILL="${TEST_TMPDIR}/bad-skill.json"
"${REAL_JQ}" '.skills += [{name: "zz-bad", role: "domain", available: true, enabled: true,
  triggers: ["zzbad"], required_when: 42}]' "${FULL}" > "${BADSKILL}"
OUT2B="$(run_hook "${BADSKILL}" "debug the flaky login test zzmarker")"
assert_contains "C2: skills emitted before a malformed skill still route" \
    "Skill(test:zz-marker-skill)" "${OUT2B}"

# ---------------------------------------------------------------------------
# C3: an unparseable cache falls back to the fallback registry, exactly like a
# missing one. The shipped fallback marks no skill available, so its output is
# empty and indistinguishable from a crash; this cell therefore runs the hook with
# a plugin root whose fallback registry is FULL (marker skill included). Everything
# else in that root is a symlink to this checkout, so the hook's libs still load.
# ---------------------------------------------------------------------------
FAKE_ROOT="${TEST_TMPDIR}/plugin-root"
mkdir -p "${FAKE_ROOT}/config"
for _entry in "${PROJECT_ROOT}"/* "${PROJECT_ROOT}"/.claude-plugin; do
    [ "${_entry##*/}" = "config" ] && continue
    ln -s "${_entry}" "${FAKE_ROOT}/${_entry##*/}"
done
cp -R "${PROJECT_ROOT}"/config/* "${FAKE_ROOT}/config/"
cp "${FULL}" "${FAKE_ROOT}/config/fallback-registry.json"
BAD="${TEST_TMPDIR}/bad.json"
printf '{"skills": [ not json' > "${BAD}"
OUT3A="$(run_hook "${BAD}" "debug the flaky login test zzmarker" CLAUDE_PLUGIN_ROOT="${FAKE_ROOT}")"
OUT3B="$(run_hook - "debug the flaky login test zzmarker" CLAUDE_PLUGIN_ROOT="${FAKE_ROOT}")"
assert_contains "C3 setup: a missing cache routes through the fallback registry" \
    "Skill(test:zz-marker-skill)" "${OUT3B}"
assert_contains "C3: an unparseable cache routes through the fallback registry" \
    "Skill(test:zz-marker-skill)" "${OUT3A}"
assert_equals "C3: an unparseable cache is treated exactly like a missing cache" "${OUT3B}" "${OUT3A}"
# Control: when the fallback is unparseable too, the no-registry branch answers.
cp "${BAD}" "${FAKE_ROOT}/config/fallback-registry.json"
OUT3C="$(run_hook "${BAD}" "debug the flaky login test zzmarker" CLAUDE_PLUGIN_ROOT="${FAKE_ROOT}")"
assert_contains "C3 control: with both unparseable, the no-registry checkpoint is emitted" \
    "phase checkpoint only" "${OUT3C}"

# ---------------------------------------------------------------------------
# C4 + C5: phase filtering, and multi-line composition values. Each phase gets a
# hint whose text spans lines; the continuation line is itself shaped like a hint,
# which the composition reader has always turned into its own hint.
# ---------------------------------------------------------------------------
# The FIRST phase in the registry also gets a malformed parallel entry: the old call
# only ever evaluated one phase, so a broken phase must not take later phases with it.
ML="${TEST_TMPDIR}/multiline.json"
"${REAL_JQ}" '
  .phase_compositions |= with_entries(
    .value.hints = ((.value.hints // []) + [{text: ("zzfirst-" + .key + "\nHINT:zzcont-" + .key)}]))
  | (.phase_compositions | keys_unsorted[0]) as $first
  | .phase_compositions[$first].parallel = ["not-an-object"]
' "${FULL}" > "${ML}"
FIRST_PHASE="$("${REAL_JQ}" -r '.phase_compositions | keys_unsorted[0]' "${ML}")"
if [ "${FIRST_PHASE}" != "REVIEW" ]; then
    _record_pass "C4 setup: the broken phase (${FIRST_PHASE}) precedes REVIEW"
else
    _record_fail "C4 setup: the broken phase precedes REVIEW" "REVIEW is the first phase"
fi
OUT4="$(run_hook "${ML}" "review the PR diff for bugs")"
assert_contains "C4 setup: the prompt landed in the REVIEW phase" "Phase: [REVIEW]" "${OUT4}"
assert_contains "C4: the REVIEW composition hint is rendered despite a broken earlier phase" \
    "zzfirst-REVIEW" "${OUT4}"
# The required_when pairs come from the same call (section 3).
assert_contains "C4: required_when text is rendered for a condition-gated skill" \
    "INVOKE WHEN:" "${OUT4}"
assert_not_contains "C4: another phase's composition hint is not rendered" "zzfirst-DEBUG" "${OUT4}"
assert_not_contains "C4: no other phase leaks in (SHIP)" "zzfirst-SHIP" "${OUT4}"
assert_contains "C5: a continuation line stays with its phase" "zzcont-REVIEW" "${OUT4}"
assert_not_contains "C5: another phase's continuation line does not leak" "zzcont-DEBUG" "${OUT4}"

# ---------------------------------------------------------------------------
# C6: documents are isolated. The old calls each ran jq over the file, and jq's CLI
# reports a runtime error and continues with the NEXT document, so a non-object
# document before the real registry cost nothing. Every section must still come from
# the second document: skills, methodology hints and the current phase's compositions.
# ---------------------------------------------------------------------------
DOC2="${TEST_TMPDIR}/doc2.json"
"${REAL_JQ}" -c '
  .methodology_hints = ((.methodology_hints // []) + [{hint: "zz-doc2-hint", triggers: ["zzmarker"]}])
  | .phase_compositions.DEBUG.hints = ((.phase_compositions.DEBUG.hints // []) + [{text: "zz-doc2-comp"}])
' "${FULL}" > "${DOC2}"
for _lead in '[]' '"bad"' 'null' '42'; do
    CAT="${TEST_TMPDIR}/concat.json"
    { printf '%s\n' "${_lead}"; cat "${DOC2}"; } > "${CAT}"
    OUT6="$(run_hook "${CAT}" "debug the flaky login test zzmarker")"
    assert_contains "C6: after a leading ${_lead} document, skills still route" \
        "Skill(test:zz-marker-skill)" "${OUT6}"
    assert_contains "C6: after a leading ${_lead} document, methodology hints still render" \
        "zz-doc2-hint" "${OUT6}"
    assert_contains "C6: after a leading ${_lead} document, compositions still render" \
        "zz-doc2-comp" "${OUT6}"
done

# ---------------------------------------------------------------------------
# C7: an RS must not shift the sections, whether it sits in rendered text or in a
# phase key. The two are separate registries so neither can trigger the fallback on
# the other's behalf.
# ---------------------------------------------------------------------------
RSTEXT="${TEST_TMPDIR}/rs-text.json"
"${REAL_JQ}" '
  ([30] | implode) as $rs
  | .phase_compositions.REVIEW.hints = ((.phase_compositions.REVIEW.hints // [])
        + [{text: ("zzbefore" + $rs + "zzafter")}])
' "${FULL}" > "${RSTEXT}"
OUT7="$(run_hook "${RSTEXT}" "review the PR diff for bugs")"
RS_NEEDLE="zzbefore$(printf '%s' '\')u001ezzafter"
assert_contains "C7: text containing RS is rendered whole" "${RS_NEEDLE}" "${OUT7}"
assert_contains "C7: REVIEW composition lines survive RS in the text" "PARALLEL:" "${OUT7}"

RSKEY="${TEST_TMPDIR}/rs-key.json"
"${REAL_JQ}" '
  ([30] | implode) as $rs
  | .phase_compositions = ({("RE" + $rs): {hints: [{text: "zzrskey"}]}} + .phase_compositions)
  | .phase_compositions.REVIEW.hints = ((.phase_compositions.REVIEW.hints // []) + [{text: "zz-after-rs-key"}])
' "${FULL}" > "${RSKEY}"
OUT7B="$(run_hook "${RSKEY}" "review the PR diff for bugs")"
assert_contains "C7: an RS-bearing phase key placed first does not cost REVIEW" \
    "zz-after-rs-key" "${OUT7B}"
assert_not_contains "C7: the RS-bearing phase is not rendered" "zzrskey" "${OUT7B}"

# ---------------------------------------------------------------------------
# C8: a phase key containing a newline, a US or a NUL cannot forge another phase's
# lines. The old exact-key lookup could never select such a key; bash drops NUL, so
# REVIEW<NUL> would otherwise read as REVIEW. Each key is placed FIRST.
# ---------------------------------------------------------------------------
BADKEYS="${TEST_TMPDIR}/badkeys.json"
"${REAL_JQ}" '
  ([31] | implode) as $us | ([0] | implode) as $nul
  | .phase_compositions = ({
        "OTHER\nREVIEW": {hints: [{text: "zzleak-nl"}]},
        ("REVIEW" + $us + "HINT:zzleak-us"): {hints: [{text: "zzleak-us2"}]},
        ("REVIEW" + $nul): {hints: [{text: "zzleak-nul"}]}
      } + .phase_compositions)
' "${FULL}" > "${BADKEYS}"
OUT8="$(run_hook "${BADKEYS}" "review the PR diff for bugs")"
assert_contains "C8 setup: the prompt landed in the REVIEW phase" "Phase: [REVIEW]" "${OUT8}"
assert_not_contains "C8: a newline-bearing phase key does not leak into REVIEW" "zzleak-nl" "${OUT8}"
assert_not_contains "C8: a US-bearing phase key does not leak into REVIEW" "zzleak-us" "${OUT8}"
assert_not_contains "C8: a NUL-bearing phase key does not leak into REVIEW" "zzleak-nul" "${OUT8}"
assert_contains "C8: the real REVIEW compositions still render" "PARALLEL:" "${OUT8}"

# ---------------------------------------------------------------------------
# C9: methodology hints come from the same call (section 2) and still render.
# ---------------------------------------------------------------------------
HINTREG="${TEST_TMPDIR}/hint.json"
"${REAL_JQ}" '.methodology_hints = ((.methodology_hints // []) + [{hint: "zz-method-hint", triggers: ["zzmarker"]}])' \
    "${FULL}" > "${HINTREG}"
OUT9="$(run_hook "${HINTREG}" "debug the flaky login test zzmarker")"
assert_contains "C9: a matching methodology hint is rendered" "zz-method-hint" "${OUT9}"

# ---------------------------------------------------------------------------
# C10: the SKILL_EXPLAIN trace still scores skills read from the single call.
# ---------------------------------------------------------------------------
H10="$(mktemp -d "${TEST_TMPDIR}/run.XXXXXX")"
mkdir -p "${H10}/.claude"
cp "${FULL}" "${H10}/.claude/.skill-registry-cache.json"
TRACE10="$("${REAL_JQ}" -nc --arg p "debug the flaky login test zzmarker" --arg t "${H10}/.claude/a.jsonl" \
    '{prompt:$p,transcript_path:$t}' \
  | env HOME="${H10}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" SKILL_PROJECT_ROOT="${TEST_TMPDIR}" \
        SKILL_EXPLAIN=1 /bin/bash "${HOOK}" 2>&1 >/dev/null)"
assert_contains "C10: the trace scores the marker skill" "zz-marker-skill: trigger=(zzmarker)" "${TRACE10}"

teardown_test_env
print_summary
