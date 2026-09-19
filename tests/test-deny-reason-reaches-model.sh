#!/usr/bin/env bash
# test-deny-reason-reaches-model.sh — issue #254 (defect 1), and the shared
# cause behind #249's "denies with no message".
#
# THE DEFECT. Claude Code's PreToolUse contract puts the two audiences in two
# different fields:
#
#   hookSpecificOutput.permissionDecisionReason  -> shown to CLAUDE on a deny
#   systemMessage                                -> shown to the USER, never to Claude
#
# Every gate hook in this repo wrote its remediation text into `systemMessage`
# alone. The text was already good — it names the missing step, the exact Skill
# to invoke, the attestation escape and the human bypass — and the model never
# received a word of it. All it saw was the harness's generic "denied" line.
#
# Measured consequence (#254): an agent hit `deny:chain-verify` three times,
# concluded that agent pushes are simply not allowed in that repo, and handed
# the push to a human. An earlier session had drawn the same wrong conclusion
# and written it to memory. The gate was telling it exactly what to do the
# whole time, into a channel the model cannot read.
#
# This is one defect with four instances, not four defects, so the primary
# assertion here is a LINT over every deny site rather than a per-hook cell:
# a new gate that forgets the field must fail immediately, not after another
# session is spent diagnosing a silent deny.
#
# Bash 3.2 compatible (macOS default).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-deny-reason-reaches-model.sh ==="
echo ""

# ---------------------------------------------------------------------------
# 1. LINT — every deny-emitting line carries permissionDecisionReason
# ---------------------------------------------------------------------------
# Population: any line in hooks/ that sets "permissionDecision" to deny. There
# is deliberately NO allowlist: a gate that denies without telling the model why
# is the defect, and an exemption would be indistinguishable from the bug.
echo "--- lint: no deny may omit permissionDecisionReason ---"

# KNOWN-INCOMPLETE ENUMERATION, deliberately labelled as one — the treatment
# this repo prescribes for a matcher it cannot prove total (cf. the smuggling
# list in git-command.sh). The population is LINE-oriented: a future emitter
# that supplies the value from a variable (`--arg dec deny … "permissionDecision":$dec`)
# or splits the jq filter so `deny` lands on the next line falls silently
# outside it, and with the current five sites intact the floor below would not
# notice. That is the repo's own line-oriented-parsers-report-clean shape, in a
# lint rather than a scanner. No live instance; recorded so the next person
# widens the matcher instead of trusting it.
# Inverse hazard, loud rather than silent: a doc comment inside hooks/ carrying
# the literal `"permissionDecision": "deny"` would RED this lint as a violation.
DENY_LINES="$(grep -rn '"permissionDecision"' --include='*.sh' "${PROJECT_ROOT}/hooks/" 2>/dev/null \
              | grep -i 'deny' || true)"

# A floor, so the lint cannot pass by matching nothing. If a refactor moves the
# emitters behind a helper the count drops and this fails LOUDLY rather than
# going vacuously green — the failure mode that let the #137 lint's population
# fall from 13 to 1 while its assertion kept passing.
N_DENY="$(printf '%s\n' "${DENY_LINES}" | grep -c '.' || true)"
case "${N_DENY}" in ''|*[!0-9]*) N_DENY=0 ;; esac
if [ "${N_DENY}" -ge 5 ]; then
    _record_pass "lint population is non-vacuous (${N_DENY} deny-emitting lines, floor 5)"
else
    _record_fail "lint population is non-vacuous" \
        "found ${N_DENY} deny-emitting lines, expected >= 5 — the emitters moved and this lint now checks nothing"
fi

VIOLATIONS=""
while IFS= read -r line; do
    [ -n "${line}" ] || continue
    case "${line}" in
        *permissionDecisionReason*) : ;;
        *) VIOLATIONS="${VIOLATIONS}${VIOLATIONS:+
}${line%%:*}:$(printf '%s' "${line}" | cut -d: -f2)" ;;
    esac
done <<EOF
${DENY_LINES}
EOF

if [ -z "${VIOLATIONS}" ]; then
    _record_pass "every deny-emitting line carries permissionDecisionReason"
else
    _record_fail "every deny-emitting line carries permissionDecisionReason" \
        "sites emitting a deny the model cannot read:
${VIOLATIONS}"
fi

# ---------------------------------------------------------------------------
# Shared assertion for a real hook run.
# ---------------------------------------------------------------------------
# The reason must be present AND must carry the remediation, not a stub. We
# assert it equals systemMessage: the two audiences differ, the guidance must
# not. Asserting only "non-empty" would pass on a hook that emits "denied".
_assert_deny_reaches_model() {  # $1=label  $2=hook stdout
    local label="$1" out="${2:-}"
    local dec reason sysmsg
    # `jq empty` accepts a STREAM, so two concatenated objects pass it and the
    # second one's empty fields then satisfy every assertion below (Codex).
    # The hook contract is exactly ONE object, so count them.
    local nobj
    nobj="$(printf '%s' "${out}" | jq -s 'length' 2>/dev/null)" || nobj=""
    if [ "${nobj}" != "1" ]; then
        _record_fail "${label}: output is exactly one JSON object" \
            "parsed ${nobj:-<unparseable>} objects; got: ${out:-<empty>}"
        return
    fi
    dec="$(printf '%s' "${out}" | jq -r '.hookSpecificOutput.permissionDecision // ""')"
    if [ "${dec}" != "deny" ]; then
        _record_fail "${label}: the cell actually produced a deny" \
            "permissionDecision='${dec}' — this cell proves nothing unless it denies"
        return
    fi
    reason="$(printf '%s' "${out}" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')"
    sysmsg="$(printf '%s' "${out}" | jq -r '.systemMessage // ""')"
    if [ -n "${reason}" ]; then
        _record_pass "${label}: deny carries permissionDecisionReason"
    else
        _record_fail "${label}: deny carries permissionDecisionReason" \
            "the model receives nothing; the user-only systemMessage was: ${sysmsg:0:120}"
    fi
    assert_equals "${label}: the model is told the same thing as the user" "${sysmsg}" "${reason}"
}

# ---------------------------------------------------------------------------
# 2. skill-gate.sh — a real sequencing deny (#249's hook)
# ---------------------------------------------------------------------------
echo ""
echo "--- skill-gate.sh: real sequencing deny ---"
SG_HOME="$(mktemp -d /tmp/drm-sg-XXXXXX)"
_OLDHOME="${HOME}"
export HOME="${SG_HOME}"
mkdir -p "${HOME}/.claude"
SG_TOKEN="session-drm"
printf '%s' "${SG_TOKEN}" > "${HOME}/.claude/.skill-session-token"
printf '{"chain":["brainstorming","writing-plans","subagent-driven-development","requesting-code-review","verification-before-completion"],"completed":[],"current_index":0}\n' \
    > "${HOME}/.claude/.skill-composition-state-${SG_TOKEN}"
printf '["brainstorming"]\n' > "${HOME}/.claude/.skill-invocation-evidence-${SG_TOKEN}"

# _sg <hook script> — the plugin/project root is ALWAYS the real checkout.
# The mutant differs by ONE FILE, nothing else. Pointing the roots at a copied
# tree instead changes the gate's resolved MODE (a foreign root defaults to
# `warn`, which emits systemMessage only and no permissionDecision at all), so
# the mutant would "lose the field" for a reason that has nothing to do with
# the mutation — an apples-to-oranges control that passes vacuously. Caught in
# review; the first cut of this cell had exactly that bug.
_sg() {
    printf '{"tool_name":"Skill","tool_input":{"skill":"superpowers:subagent-driven-development"},"transcript_path":""}' \
        | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" SKILL_PROJECT_ROOT="${PROJECT_ROOT}" \
          /bin/bash "${1}" 2>/dev/null
}
SG_OUT="$(_sg "${PROJECT_ROOT}/hooks/skill-gate.sh")"
_assert_deny_reaches_model "skill-gate" "${SG_OUT}"
assert_contains "skill-gate: the model is told which step is missing" \
    "writing-plans" "$(printf '%s' "${SG_OUT}" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')"

# Mutation: a copy with the field stripped must stop satisfying the cell.
SG_MUT="$(mktemp -d /tmp/drm-sgmut-XXXXXX)"
sed 's/,"permissionDecisionReason":\$msg//; s/,"permissionDecisionReason":"%s"//' \
    "${PROJECT_ROOT}/hooks/skill-gate.sh" > "${SG_MUT}/skill-gate.sh"
if cmp -s "${PROJECT_ROOT}/hooks/skill-gate.sh" "${SG_MUT}/skill-gate.sh"; then
    _record_fail "mutation actually changed skill-gate.sh" \
        "the strip was a no-op — the field is absent, so the cell above is vacuous"
else
    _record_pass "mutation actually changed skill-gate.sh"
    MUT_OUT="$(_sg "${SG_MUT}/skill-gate.sh")"
    # Asserting only "reason is empty" is also satisfied by empty stdout or
    # malformed JSON, i.e. by a mutant that simply broke (Codex). The mutant
    # must still be a working hook that denies with its user-facing message
    # intact — ONLY the model-facing field may be gone.
    assert_equals "mutation: the mutant still emits exactly one JSON object" \
        "1" "$(printf '%s' "${MUT_OUT}" | jq -s 'length' 2>/dev/null)"
    assert_equals "mutation: the mutant still DENIES" \
        "deny" "$(printf '%s' "${MUT_OUT}" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null)"
    assert_contains "mutation: the mutant still tells the USER why" \
        "writing-plans" "$(printf '%s' "${MUT_OUT}" | jq -r '.systemMessage // ""' 2>/dev/null)"
    MUT_REASON="$(printf '%s' "${MUT_OUT}" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)"
    assert_equals "mutation: ...and ONLY the model is left with nothing" "" "${MUT_REASON}"
fi
rm -rf "${SG_MUT}"
export HOME="${_OLDHOME}"
rm -rf "${SG_HOME}"

# ---------------------------------------------------------------------------
# 3. publish-guard.sh — a real privacy deny
# ---------------------------------------------------------------------------
echo ""
echo "--- publish-guard.sh: real privacy deny ---"
PG_WORK="$(mktemp -d /tmp/drm-pg-XXXXXX)"
PG_MEM="${PG_WORK}/memory"; PG_REPO="${PG_WORK}/repo"
mkdir -p "${PG_MEM}" "${PG_REPO}"
PG_PRIVATE="the verdict artifact carries the head sha at verify time so an ancestor failure never blocks a commit that has since been repaired"
printf 'name: v\n---\n\n%s\n' "${PG_PRIVATE}" > "${PG_MEM}/feedback_verdict_sha.md"
( cd "${PG_REPO}" && git init -q . && printf 'unrelated\n' > r.md && git add r.md \
  && git -c user.email=t@t -c user.name=t commit -q -m init )
printf 'Proposal.\n\n%s\n' "${PG_PRIVATE}" > "${PG_WORK}/leaky.md"
PG_OUT="$(jq -n --arg c "gh issue create --title t --body-file ${PG_WORK}/leaky.md" '{"tool_input":{"command":$c}}' \
    | ( cd "${PG_REPO}" && MEMORY_LEAK_CHECK_MEMORY_DIR="${PG_MEM}" \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${PROJECT_ROOT}/hooks/publish-guard.sh" 2>/dev/null ))"
_assert_deny_reaches_model "publish-guard" "${PG_OUT}"
assert_not_contains "publish-guard: the reason still does not echo the private text" \
    "${PG_PRIVATE}" "$(printf '%s' "${PG_OUT}" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')"
rm -rf "${PG_WORK}"

# ---------------------------------------------------------------------------
# 4. openspec-guard.sh — the no-jq emitter, driven directly
# ---------------------------------------------------------------------------
# The push gate's jq path is covered end-to-end by the healthy control in
# tests/test-push-gate-degradation-advisory.sh, which pins the real guard's
# deny output byte-for-byte. What no other test reaches is the FALLBACK
# emitter: with jq absent, `_emit_deny` hand-rolls the JSON with printf and
# _json_escape, and a field added only to the jq branch would be invisible
# there. The function text is EXTRACTED from the real hook rather than
# hand-copied — a hand-copy only ever agrees with itself.
echo ""
echo "--- openspec-guard.sh: the no-jq fallback emitter ---"
GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
EM_DIR="$(mktemp -d /tmp/drm-em-XXXXXX)"
sed -n '/^_json_escape()/,/^}/p'  "${GUARD}" >  "${EM_DIR}/fns.sh"
sed -n '/^_emit_deny()/,/^}/p'    "${GUARD}" >> "${EM_DIR}/fns.sh"

# Both functions must be DEFINED in the extract, not merely mentioned: the
# emitter's body names `_json_escape`, so a `grep -q '_json_escape'` passes even
# when the definition failed to extract — and with jq present that omission is
# never noticed (Codex).
if grep -q '^_emit_deny()' "${EM_DIR}/fns.sh" && grep -q '^_json_escape()' "${EM_DIR}/fns.sh"; then
    _record_pass "extracted the real _emit_deny and _json_escape from the hook"
    # A message with the two characters that break hand-rolled JSON, in the
    # order that matters: a backslash escaped after a quote gets doubled.
    NASTY='PUSH GATE: run Skill("x") then retry \ or set ACSM_SKIP_PUSH_GATE=1'
    # A TOOLS-ONLY PATH. The first cut appended /usr/bin:/bin "for safety" and
    # macOS ships /usr/bin/jq, so this cell exercised the jq branch and the
    # fallback had ZERO coverage while reporting green (Codex). _json_escape
    # needs exactly sed and tr; printf is a shell builtin.
    NOJQ_BIN="${EM_DIR}/bin"; mkdir -p "${NOJQ_BIN}"
    for _t in sed tr; do
        _p="$(command -v "${_t}" 2>/dev/null)" && [ -n "${_p}" ] && ln -sf "${_p}" "${NOJQ_BIN}/${_t}"
    done
    # Prove the branch under test is the one that runs. Without this the cell
    # silently reverts to measuring jq the moment the PATH changes again.
    if PATH="${NOJQ_BIN}" /bin/bash -c 'command -v jq' >/dev/null 2>&1; then
        _record_fail "the no-jq cell actually has no jq" \
            "jq is resolvable on the tools-only PATH — this cell is exercising the jq branch, not the fallback"
    else
        _record_pass "the no-jq cell actually has no jq"
    fi
    NOJQ_OUT="$(PATH="${NOJQ_BIN}" /bin/bash -c \
        ". '${EM_DIR}/fns.sh'; _SUBJ_NOTE=''; _emit_deny \"\$1\"" _ "${NASTY}" 2>/dev/null)"
    # Parsed with the REAL jq, from outside the stripped PATH.
    if [ "$(printf '%s' "${NOJQ_OUT}" | jq -s 'length' 2>/dev/null)" = "1" ]; then
        _record_pass "no-jq emitter still produces exactly one parseable JSON object"
        NOJQ_REASON="$(printf '%s' "${NOJQ_OUT}" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')"
        NOJQ_SYS="$(printf '%s' "${NOJQ_OUT}" | jq -r '.systemMessage // ""')"
        assert_equals "no-jq emitter: the model gets the same text as the user" "${NOJQ_SYS}" "${NOJQ_REASON}"
        assert_equals "no-jq emitter: the message survives escaping intact" "${NASTY}" "${NOJQ_REASON}"
    else
        _record_fail "no-jq emitter still produces exactly one parseable JSON object" "got: ${NOJQ_OUT:-<empty>}"
    fi
else
    _record_fail "extracted the real _emit_deny and _json_escape from the hook" \
        "extraction found nothing — the function was renamed or reshaped, and this cell is vacuous"
fi
rm -rf "${EM_DIR}"

print_summary
