#!/usr/bin/env bash
# test-review-credit-readers.sh — every OTHER reader of REVIEW status applies
# the push guard's rule (openspec review-credit-from-evidence), so a push and a
# later SHIP step never disagree:
#
#   P  hooks/lib/phase-evidence.sh::phase_step_satisfied (and through it the
#      REAL hooks/skill-gate.sh): for the requesting-code-review step ONLY, any
#      credited name in the invocation array, and a returned allowlisted
#      reviewer whose sha covers HEAD. No alias leak into other steps.
#   G  scripts/gate-status.sh: a REVIEWER evidence line, replay rows 2 and 5,
#      and a narrowing (never FALL OPEN) warning when credited-skills.sh is
#      missing.
#   K  hooks/openspec-guard.sh Check 4 (the SHIP-phase REVIEW GUARD advisory):
#      for a commit the reviewer leg reads the process cwd's toplevel, HEAD
#      and that root's ledger key (ruling F7); for a push it reuses the push
#      gate's own reviewer leg.
#
# Every widening is tested in BOTH arms, against real producers and real
# repos: a covering allowlisted reviewer credits; a description-arm, legacy
# untagged, stale (material change since), `-` sha, other-branch or lib-less
# reviewer does not.
#
# Bash 3.2 compatible. Sources test-helpers.sh.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
GATE_HOOK="${PROJECT_ROOT}/hooks/skill-gate.sh"
GATE_STATUS="${PROJECT_ROOT}/scripts/gate-status.sh"
LEDGER_LIB="${PROJECT_ROOT}/hooks/lib/branch-ledger.sh"
EVID_LIB="${PROJECT_ROOT}/hooks/lib/phase-evidence.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-review-credit-readers.sh ==="

if ! command -v jq >/dev/null 2>&1; then
    _record_pass "jq unavailable — every reader under test is jq-gated; skipping"
    print_summary
    exit 0
fi

unset ACSM_SKIP_PUSH_GATE
# gate-status resolves its token own-session-first; the agent running this
# suite has its own id, which must not leak in. The singleton is used instead.
unset CLAUDE_CODE_SESSION_ID
export SKILL_GATE_CAPTURE_DISABLE=1

for _f in "${EVID_LIB}" "${GATE_STATUS}" "${GUARD}" "${GATE_HOOK}"; do
    if /bin/bash -n "${_f}"; then _record_pass "parses under /bin/bash: ${_f##*/}"
    else _record_fail "parses under /bin/bash: ${_f##*/}" "syntax error"; fi
done

_GIT() { git -c user.email=t@t -c user.name=t "$@"; }

# _mk_repo — a NON-routing repo with an origin and branch feature/x:
#   C1 adds src.sh (material), C2 adds docs/a.md (docs only), C3 edits src.sh
#   (material), C4 adds docs/b.md (docs only) = HEAD. So a reviewer at C4 is at
#   HEAD, one at C3 covers (only docs since), and C1/C2 are stale.
_mk_repo() {
    REPO="${TEST_TMPDIR}/repo"
    ORIGIN="${TEST_TMPDIR}/origin.git"
    git init -q --bare "${ORIGIN}"
    git init -q -b main "${REPO}"
    printf 'base\n' > "${REPO}/README.md"
    git -C "${REPO}" add README.md
    _GIT -C "${REPO}" commit -q -m base
    git -C "${REPO}" remote add origin "${ORIGIN}"
    git -C "${ORIGIN}" fetch -q "${REPO}" main:main
    git -C "${REPO}" fetch -q origin
    git -C "${REPO}" checkout -q -b feature/x
    printf 'echo one\n' > "${REPO}/src.sh"
    git -C "${REPO}" add src.sh
    _GIT -C "${REPO}" commit -q -m c1
    C1="$(git -C "${REPO}" rev-parse HEAD)"
    mkdir -p "${REPO}/docs"
    printf 'doc\n' > "${REPO}/docs/a.md"
    git -C "${REPO}" add docs/a.md
    _GIT -C "${REPO}" commit -q -m c2
    C2="$(git -C "${REPO}" rev-parse HEAD)"
    printf 'echo two\n' > "${REPO}/src.sh"
    git -C "${REPO}" add src.sh
    _GIT -C "${REPO}" commit -q -m c3
    C3="$(git -C "${REPO}" rev-parse HEAD)"
    printf 'doc b\n' > "${REPO}/docs/b.md"
    git -C "${REPO}" add docs/b.md
    _GIT -C "${REPO}" commit -q -m c4
    C4="$(git -C "${REPO}" rev-parse HEAD)"
    # macOS: the ledger key hashes the RESOLVED path.
    REPO="$(git -C "${REPO}" rev-parse --show-toplevel)"
}

# _ledger <milestone> <sha|""|-> [tag] — the REAL producer, keyed from the
# repo's current branch.
_ledger() {
    ( cd "${REPO}" && . "${LEDGER_LIB}" && \
        branch_ledger_record "$1" "${REPO}" "$2" "${3:-}" )
}

_TOK="session-conv-X"
_evidence() { printf '%s\n' "$1" > "${HOME}/.claude/.skill-invocation-evidence-${_TOK}"; }

_fresh() {
    setup_test_env
    mkdir -p "${HOME}/.claude"
    _mk_repo
}

# ===========================================================================
# P1/P2: phase_step_satisfied, called directly.
# ===========================================================================
# _pss <step> [lib-dir] — rc of phase_step_satisfied, from inside the repo.
_pss() {
    local _lib="${2:-${PROJECT_ROOT}/hooks/lib}"
    ( cd "${REPO}" && . "${_lib}/phase-evidence.sh" >/dev/null 2>&1 && \
        phase_step_satisfied "${_TOK}" "$1" "${REPO}" ) >/dev/null 2>&1
    printf '%s' "$?"
}
_RCR="requesting-code-review"

echo "--- P1: requesting-code-review accepts credited names and a covering reviewer ---"
_fresh
assert_equals "P1 control: no evidence => 1" "1" "$(_pss "${_RCR}")"
_evidence '["requesting-code-review"]'
assert_equals "P1 control: the step's own name (existing leg) => 0" "0" "$(_pss "${_RCR}")"
_evidence '["code-review"]'
assert_equals "P1a invocation [code-review] => 0" "0" "$(_pss "${_RCR}")"
_evidence '["review-pr"]'
assert_equals "P1a invocation [review-pr] => 0" "0" "$(_pss "${_RCR}")"
_evidence '["security-review"]'
assert_equals "P1a invocation [security-review] => 0" "0" "$(_pss "${_RCR}")"
_evidence '["agent-team-review"]'
assert_equals "P1a invocation [agent-team-review] => 0" "0" "$(_pss "${_RCR}")"
_evidence '["subagent-driven-development"]'
assert_equals "P1a invocation [subagent-driven-development] => 0" "0" "$(_pss "${_RCR}")"
_evidence '["receiving-code-review"]'
assert_equals "P1b invocation [receiving-code-review] => 1" "1" "$(_pss "${_RCR}")"
_evidence '["code-reviewer"]'
assert_equals "P1b invocation [code-reviewer] (not a credited name) => 1" "1" "$(_pss "${_RCR}")"
_evidence '["simplify","verification-before-completion"]'
assert_equals "P1b invocation [simplify, verification-before-completion] => 1" "1" "$(_pss "${_RCR}")"
_evidence '[""]'
assert_equals "P1b invocation [\"\"] => 1" "1" "$(_pss "${_RCR}")"
_evidence '"code-review"'
assert_equals "P1b a scalar (non-array) evidence file => 1" "1" "$(_pss "${_RCR}")"
# An object's VALUES iterate under .[], so only the array type check stops it.
_evidence '{"x":"code-review"}'
assert_equals "P1b an object whose value is a credited name => 1" "1" "$(_pss "${_RCR}")"
rm -f "${HOME}/.claude/.skill-invocation-evidence-${_TOK}"

_ledger reviewer-returned "${C4}" "arm=allowlist"
assert_equals "P1c allowlisted reviewer at HEAD => 0" "0" "$(_pss "${_RCR}")"
_ledger reviewer-returned "${C3}" "arm=allowlist"
assert_equals "P1c allowlisted reviewer at C3, only docs since => 0" "0" "$(_pss "${_RCR}")"
_ledger reviewer-returned "${C1}" "arm=allowlist"
assert_equals "P1d stale: material change since the reviewed sha => 1" "1" "$(_pss "${_RCR}")"
_ledger reviewer-returned "${C2}" "arm=allowlist"
assert_equals "P1d stale: reviewed a docs commit, material C3 since => 1" "1" "$(_pss "${_RCR}")"
_ledger reviewer-returned "${C4}" "arm=description"
assert_equals "P1e description arm at HEAD => 1" "1" "$(_pss "${_RCR}")"
_ledger reviewer-returned "${C4}" ""
assert_equals "P1f legacy untagged record at HEAD => 1" "1" "$(_pss "${_RCR}")"
_ledger reviewer-returned "-" "arm=allowlist"
assert_equals "P1g '-' sha (dispatch commit unknown) => 1" "1" "$(_pss "${_RCR}")"

echo "--- P2: no alias leak into other steps ---"
_ledger reviewer-returned "${C4}" "arm=allowlist"
_evidence '["code-review"]'
assert_equals "P2 executing-plans with only code-review evidence + covering reviewer => 1" "1" "$(_pss executing-plans)"
assert_equals "P2 openspec-ship with only code-review evidence + covering reviewer => 1" "1" "$(_pss openspec-ship)"
assert_equals "P2 verification-before-completion with only review evidence => 1" "1" "$(_pss verification-before-completion)"
_evidence '["subagent-driven-development"]'
assert_equals "P2 control: executing-plans alias group still holds => 0" "0" "$(_pss executing-plans)"
teardown_test_env

echo "--- P1L: credited-skills.sh missing narrows, never widens ---"
_fresh
_NOLIB="${TEST_TMPDIR}/nolib"
mkdir -p "${_NOLIB}"
cp "${PROJECT_ROOT}"/hooks/lib/*.sh "${_NOLIB}/"
rm -f "${_NOLIB}/credited-skills.sh"
_evidence '["code-review"]'
assert_equals "P1L [code-review] without the lib => 1" "1" "$(_pss "${_RCR}" "${_NOLIB}")"
assert_equals "P1L control: [code-review] with the lib => 0" "0" "$(_pss "${_RCR}")"
_evidence '["agent-team-review"]'
assert_equals "P1L [agent-team-review] (one of the four) without the lib => 0" "0" "$(_pss "${_RCR}" "${_NOLIB}")"
rm -f "${HOME}/.claude/.skill-invocation-evidence-${_TOK}"
_ledger reviewer-returned "${C4}" "arm=allowlist"
assert_equals "P1L covering reviewer without the lib => 1" "1" "$(_pss "${_RCR}" "${_NOLIB}")"
assert_equals "P1L control: covering reviewer with the lib => 0" "0" "$(_pss "${_RCR}")"
teardown_test_env

# ===========================================================================
# P3: the REAL skill-gate.sh in deny mode.
# ===========================================================================
echo "--- P3: skill-gate reads the same rule ---"
# _sg <skill> — the REAL gate. The telemetry log is truncated first, so the
# allow line a cell reads was written by THIS call: an allow prints nothing,
# and nothing is also what a gate that died early prints.
_sg() {
    : > "${HOME}/.claude/.phase-gate-events.log"
    ( cd "${REPO}" && printf '{"tool_name":"Skill","tool_input":{"skill":"%s"},"transcript_path":"/tmp/proj/conv-X.jsonl"}' "$1" \
        | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" SKILL_PROJECT_ROOT="${REPO}" /bin/bash "${GATE_HOOK}" 2>/dev/null )
}
_sg_dec() {
    [ -n "$1" ] || { printf 'none'; return 0; }
    printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null
}
_sg_allowed() { cat "${HOME}/.claude/.phase-gate-events.log" 2>/dev/null; }
_sg_reason() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null; }
_p3_fresh() {
    _fresh
    printf '{"phase_enforcement":{"skill_sequencing":"deny"}}\n' > "${HOME}/.claude/skill-config.json"
    printf '{"chain":["requesting-code-review","openspec-ship"],"completed":[]}\n' \
        > "${HOME}/.claude/.skill-composition-state-${_TOK}"
}
_p3_fresh
_out="$(_sg openspec-ship)"
assert_equals "P3 control: no evidence => deny" "deny" "$(_sg_dec "${_out}")"
assert_contains "P3 control: the deny names requesting-code-review" "Step 'requesting-code-review'" "$(_sg_reason "${_out}")"
_ledger reviewer-returned "${C4}" "arm=allowlist"
_out="$(_sg openspec-ship)"
assert_equals "P3 covering reviewer => no deny" "none" "$(_sg_dec "${_out}")"
assert_contains "P3 covering reviewer => the gate reached its allow decision" \
    "decision=allow skill=openspec-ship" "$(_sg_allowed)"
_ledger reviewer-returned "${C1}" "arm=allowlist"
_out="$(_sg openspec-ship)"
assert_equals "P3 stale reviewer => deny" "deny" "$(_sg_dec "${_out}")"
assert_contains "P3 stale reviewer => logged as a deny" "decision=deny skill=openspec-ship missing=requesting-code-review" "$(_sg_allowed)"
assert_contains "P3 stale reviewer => deny names requesting-code-review" "Step 'requesting-code-review'" "$(_sg_reason "${_out}")"
_ledger reviewer-returned "${C4}" "arm=description"
_out="$(_sg openspec-ship)"
assert_equals "P3 description-arm reviewer => deny" "deny" "$(_sg_dec "${_out}")"
_evidence '["code-review"]'
_out="$(_sg openspec-ship)"
assert_equals "P3 invocation [code-review] => no deny" "none" "$(_sg_dec "${_out}")"
assert_contains "P3 invocation [code-review] => the gate reached its allow decision" \
    "decision=allow skill=openspec-ship" "$(_sg_allowed)"
_evidence '["receiving-code-review"]'
_out="$(_sg openspec-ship)"
assert_equals "P3 invocation [receiving-code-review] => deny" "deny" "$(_sg_dec "${_out}")"
teardown_test_env

# ===========================================================================
# P4: a credited-skills.sh that FAILS A COMMAND while being sourced must not
# reach skill-gate's `trap 'exit 0' ERR` (#137/#192). skill-gate sources
# phase-evidence.sh bare, so a top-level source of the lib there turns every
# deny, for every step, into a silent allow. The lib's fault may only narrow.
# ===========================================================================
echo "--- P4: a faulting credited-skills.sh cannot silence skill-gate ---"
_p3_fresh
_SGCOPY="${TEST_TMPDIR}/plugin"
mkdir -p "${_SGCOPY}"
cp -R "${PROJECT_ROOT}/hooks" "${PROJECT_ROOT}/scripts" "${_SGCOPY}/"
_sg_root() {  # <plugin-root> <skill>
    : > "${HOME}/.claude/.phase-gate-events.log"
    ( cd "${REPO}" && printf '{"tool_name":"Skill","tool_input":{"skill":"%s"},"transcript_path":"/tmp/proj/conv-X.jsonl"}' "$2" \
        | CLAUDE_PLUGIN_ROOT="$1" SKILL_PROJECT_ROOT="${REPO}" /bin/bash "${GATE_HOOK}" 2>/dev/null )
}
_out="$(_sg_root "${_SGCOPY}" openspec-ship)"
assert_equals "P4 control: the copied root denies with no evidence" "deny" "$(_sg_dec "${_out}")"
for _fault in false _acs_no_such_command_xyz; do
    awk -v f="${_fault}" 'NR==2{print f}1' "${PROJECT_ROOT}/hooks/lib/credited-skills.sh" \
        > "${_SGCOPY}/hooks/lib/credited-skills.sh"
    assert_contains "P4 fixture (${_fault}): the fault is in the lib" "${_fault}" \
        "$(sed -n 2p "${_SGCOPY}/hooks/lib/credited-skills.sh")"
    _out="$(_sg_root "${_SGCOPY}" openspec-ship)"
    assert_equals "P4 lib runs '${_fault}' mid-file => still deny" "deny" "$(_sg_dec "${_out}")"
    assert_contains "P4 lib runs '${_fault}' mid-file => the deny names requesting-code-review" \
        "Step 'requesting-code-review'" "$(_sg_reason "${_out}")"
    # A non-REVIEW step must keep denying too: the fault reached every step.
    printf '{"chain":["brainstorming","writing-plans"],"completed":[]}\n' \
        > "${HOME}/.claude/.skill-composition-state-${_TOK}"
    _out="$(_sg_root "${_SGCOPY}" writing-plans)"
    assert_equals "P4 lib runs '${_fault}' mid-file => a non-REVIEW step still denies" "deny" "$(_sg_dec "${_out}")"
    printf '{"chain":["requesting-code-review","openspec-ship"],"completed":[]}\n' \
        > "${HOME}/.claude/.skill-composition-state-${_TOK}"
done
teardown_test_env

# ===========================================================================
# G1/G2: scripts/gate-status.sh.
# ===========================================================================
_GS_TOK="session-gs-tok"
_gs() {  # [plugin-root]
    ( cd "${REPO}" && CLAUDE_PLUGIN_ROOT="${1:-${PROJECT_ROOT}}" /bin/bash "${GATE_STATUS}" 2>/dev/null )
}
_gs_line() { printf '%s\n' "$1" | grep -F "REVIEWER (returned, allowlisted)"; }
_gs_row()  { printf '%s\n' "$1" | grep -F "  $2" | head -1; }
_g_fresh() {
    _fresh
    printf '%s' "${_GS_TOK}" > "${HOME}/.claude/.skill-session-token"
    printf '{"chain":["requesting-code-review","verification-before-completion"],"completed":[]}\n' \
        > "${HOME}/.claude/.skill-composition-state-${_GS_TOK}"
    _ledger verification-before-completion ""
}

echo "--- G1: gate-status evidence line and replay rows ---"
_g_fresh
_out="$(_gs)"
assert_contains "G1 no reviewer record => line says none" "REVIEWER (returned, allowlisted): none" "${_out}"
assert_contains "G1 control: no review evidence => row 2 WOULD DENY" "WOULD DENY" "$(_gs_row "${_out}" "2 chain REVIEW gate")"
assert_contains "G1 control: no review evidence => row 5 names review" "requesting-code-review" "$(_gs_row "${_out}" "5 global fail-closed gate")"

_ledger reviewer-returned "${C4}" "arm=allowlist"
_out="$(_gs)"
assert_contains "G1 covering reviewer => covers HEAD" "@ ${C4} — covers HEAD" "$(_gs_line "${_out}")"
assert_contains "G1 covering reviewer => row 2 pass" "pass" "$(_gs_row "${_out}" "2 chain REVIEW gate")"
assert_not_contains "G1 covering reviewer => row 2 not WOULD DENY" "WOULD DENY" "$(_gs_row "${_out}" "2 chain REVIEW gate")"
assert_not_contains "G1 covering reviewer => row 5 not WOULD DENY" "WOULD DENY" "$(_gs_row "${_out}" "5 global fail-closed gate")"
assert_contains "G1 covering reviewer => would allow" "=> git push NOW: WOULD ALLOW" "${_out}"

_ledger reviewer-returned "${C3}" "arm=allowlist"
_out="$(_gs)"
assert_contains "G1 reviewer at C3, docs only since => covers HEAD" "@ ${C3} — covers HEAD" "$(_gs_line "${_out}")"
assert_contains "G1 reviewer at C3 => row 2 pass" "pass" "$(_gs_row "${_out}" "2 chain REVIEW gate")"

_ledger reviewer-returned "${C1}" "arm=allowlist"
_out="$(_gs)"
assert_contains "G1 stale reviewer => does NOT cover HEAD" \
    "@ ${C1} — does NOT cover HEAD (material change since, or not an ancestor)" "$(_gs_line "${_out}")"
assert_contains "G1 stale reviewer => row 2 WOULD DENY" "WOULD DENY" "$(_gs_row "${_out}" "2 chain REVIEW gate")"
assert_contains "G1 stale reviewer => row 5 WOULD DENY for review" "requesting-code-review" "$(_gs_row "${_out}" "5 global fail-closed gate")"

_ledger reviewer-returned "${C4}" "arm=description"
_out="$(_gs)"
assert_contains "G1 description arm => not credited" "description-matched only — not credited" "$(_gs_line "${_out}")"
assert_contains "G1 description arm => row 2 WOULD DENY" "WOULD DENY" "$(_gs_row "${_out}" "2 chain REVIEW gate")"

_ledger reviewer-returned "${C4}" ""
_out="$(_gs)"
assert_contains "G1 legacy untagged => recorded before the arm was stored" \
    "recorded before the arm was stored — not credited" "$(_gs_line "${_out}")"
assert_contains "G1 legacy untagged => row 2 WOULD DENY" "WOULD DENY" "$(_gs_row "${_out}" "2 chain REVIEW gate")"

_ledger reviewer-returned "-" "arm=allowlist"
_out="$(_gs)"
assert_contains "G1 '-' sha => cannot check, not credited" "cannot check coverage — not credited" "$(_gs_line "${_out}")"
assert_contains "G1 '-' sha => row 2 WOULD DENY" "WOULD DENY" "$(_gs_row "${_out}" "2 chain REVIEW gate")"

# A reviewer recorded on another branch is not this branch's evidence.
_ledger reviewer-returned "${C4}" "arm=allowlist"
git -C "${REPO}" checkout -q -b feature/y
_out="$(_gs)"
assert_contains "G1 reviewer on another branch's key => none here" "REVIEWER (returned, allowlisted): none" "${_out}"
assert_contains "G1 reviewer on another branch's key => row 5 WOULD DENY" "WOULD DENY" "$(_gs_row "${_out}" "5 global fail-closed gate")"
git -C "${REPO}" checkout -q feature/x
assert_equals "G1 exit 0 throughout" "0" "$( (cd "${REPO}" && /bin/bash "${GATE_STATUS}" >/dev/null 2>&1); printf '%s' "$?")"
teardown_test_env

echo "--- G2: credited-skills.sh missing => narrowing warning, no credit ---"
_g_fresh
_ledger reviewer-returned "${C4}" "arm=allowlist"
_COPY="${TEST_TMPDIR}/plugin"
mkdir -p "${_COPY}"
cp -R "${PROJECT_ROOT}/hooks" "${PROJECT_ROOT}/scripts" "${_COPY}/"
_out="$(_gs "${_COPY}")"
assert_contains "G2 control: the copied root (lib present) credits" "@ ${C4} — covers HEAD" "$(_gs_line "${_out}")"
assert_not_contains "G2 control: no narrowing warning when the lib is present" "credited-skills.sh unavailable" "${_out}"
rm -f "${_COPY}/hooks/lib/credited-skills.sh"
_out="$(_gs "${_COPY}")"
assert_contains "G2 lib missing => the narrowing warning" \
    "credited-skills.sh unavailable — REVIEW credit narrowed to the four pre-change names and no returned reviewer counts (this can only add a deny)" "${_out}"
assert_not_contains "G2 lib missing => not the generic FALL OPEN warning" "FALL OPEN" "${_out}"
assert_contains "G2 lib missing => covering reviewer not credited (row 2)" "WOULD DENY" "$(_gs_row "${_out}" "2 chain REVIEW gate")"
assert_contains "G2 lib missing => covering reviewer not credited (row 5)" "requesting-code-review" "$(_gs_row "${_out}" "5 global fail-closed gate")"
assert_not_contains "G2 lib missing => the line does not claim coverage" "covers HEAD" "$(_gs_line "${_out}")"
# Another lib missing still says FALL OPEN (the narrowing text is specific).
rm -f "${_COPY}/hooks/lib/staleness-delta.sh"
_out="$(_gs "${_COPY}")"
assert_contains "G2 control: another missing lib keeps the generic warning" "FALL OPEN" "${_out}"
teardown_test_env

echo "--- G3: a control character inside the recorded sha is not credited ---"
# The reader validates the RAW record (review_reviewer_covers rejects it), so
# gate-status must too; scrubbing first deleted the character and showed a
# forged 40-hex sha as covering.
_g_fresh
_ledger reviewer-returned "${C4}" "arm=allowlist"
_rr_file="$( cd "${REPO}" && . "${LEDGER_LIB}" && printf '%s/reviewer-returned' "$(branch_ledger_dir "${REPO}")" )"
_c4_head="$(printf '%s' "${C4}" | cut -c1-39)"; _c4_tail="$(printf '%s' "${C4}" | cut -c40)"
printf '%s\001%s 2026-10-25T00:00:00Z arm=allowlist\n' "${_c4_head}" "${_c4_tail}" > "${_rr_file}"
assert_equals "G3 fixture: the lib rejects the record" "1" \
    "$( (cd "${REPO}" && . "${LEDGER_LIB}" && . "${PROJECT_ROOT}/hooks/lib/credited-skills.sh" && \
        review_reviewer_covers "${REPO}" "${REPO}" HEAD >/dev/null 2>&1); printf '%s' "$?")"
_out="$(_gs)"
assert_not_contains "G3 control char in sha => no 'covers HEAD' claim" "covers HEAD" "$(_gs_line "${_out}")"
assert_contains "G3 control char in sha => not credited" "not credited" "$(_gs_line "${_out}")"
assert_contains "G3 control char in sha => row 2 WOULD DENY" "WOULD DENY" "$(_gs_row "${_out}" "2 chain REVIEW gate")"
assert_contains "G3 control char in sha => row 5 names review" "requesting-code-review" "$(_gs_row "${_out}" "5 global fail-closed gate")"
assert_equals "G3 the displayed line carries no control character" "0" \
    "$(_gs_line "${_out}" | tr -d '\n' | LC_ALL=C grep -c '[[:cntrl:]]')"
teardown_test_env

echo "--- G4: --help keeps the numbered gate list whole and states the reviewer leg ---"
_help="$(/bin/bash "${GATE_STATUS}" --help 2>/dev/null)"
# The six numbered gates and their 33-space continuation lines form one block;
# a line at any other indent inside it splits the list.
assert_equals "G4 gates 1-6 are one uninterrupted block" "123456" \
    "$(printf '%s\n' "${_help}" | awk '
        /^  [1-6]\. /{ if (!s) s=1; if (s==1) printf "%s", substr($1,1,1); next }
        s==1 && /^                                 [^ ]/{ next }
        s==1{ s=2 }')"
assert_contains "G4 --help states the reviewer leg" "returned allowlisted reviewer whose sha" "${_help}"
assert_contains "G4 enforcement-map states the same leg" "returned allowlisted reviewer whose sha" \
    "$(cat "${PROJECT_ROOT}/docs/enforcement-map.md")"

# ===========================================================================
# K1/K2: Check 4, the SHIP-phase REVIEW GUARD advisory.
# ===========================================================================
_k_run() {  # <command> [cwd]
    local _p
    _p="$(jq -nc --arg c "$1" '{"transcript_path":"/tmp/proj/conv-X.jsonl","tool_input":{"command":$c}}')"
    ( cd "${2:-${REPO}}" && printf '%s' "${_p}" | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${GUARD}" 2>/dev/null )
}
_k_ctx() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }
_k_fresh() {
    _fresh
    printf '{"skill":"openspec-ship","phase":"SHIP"}\n' > "${HOME}/.claude/.skill-last-invoked-${_TOK}"
    printf '{"chain":["requesting-code-review","verification-before-completion","openspec-ship"],"completed":[]}\n' \
        > "${HOME}/.claude/.skill-composition-state-${_TOK}"
}
_RG="REVIEW GUARD:"

echo "--- K1: Check 4 on a commit ---"
_k_fresh
_out="$(_k_run "git commit -m x")"
assert_not_empty "K1 control: SHIP advisories emitted" "$(_k_ctx "${_out}")"
assert_contains "K1 control: no review evidence => REVIEW GUARD" "${_RG}" "$(_k_ctx "${_out}")"
_ledger reviewer-returned "${C4}" "arm=allowlist"
_out="$(_k_run "git commit -m x")"
assert_not_empty "K1 covering reviewer: other SHIP advisories still emitted" "$(_k_ctx "${_out}")"
assert_not_contains "K1 covering reviewer => no REVIEW GUARD" "${_RG}" "$(_k_ctx "${_out}")"
_ledger reviewer-returned "${C3}" "arm=allowlist"
_out="$(_k_run "git commit -m x")"
assert_not_contains "K1 reviewer at C3, docs only since => no REVIEW GUARD" "${_RG}" "$(_k_ctx "${_out}")"
_ledger reviewer-returned "${C1}" "arm=allowlist"
_out="$(_k_run "git commit -m x")"
assert_contains "K1 stale reviewer => REVIEW GUARD" "${_RG}" "$(_k_ctx "${_out}")"
_ledger reviewer-returned "${C4}" "arm=description"
_out="$(_k_run "git commit -m x")"
assert_contains "K1 description arm => REVIEW GUARD" "${_RG}" "$(_k_ctx "${_out}")"
_ledger reviewer-returned "${C4}" ""
_out="$(_k_run "git commit -m x")"
assert_contains "K1 legacy untagged => REVIEW GUARD" "${_RG}" "$(_k_ctx "${_out}")"
_ledger reviewer-returned "-" "arm=allowlist"
_out="$(_k_run "git commit -m x")"
assert_contains "K1 '-' sha => REVIEW GUARD" "${_RG}" "$(_k_ctx "${_out}")"

# F7: the ledger key is the process cwd's root. A covering reviewer recorded
# on feature/x does not silence the advisory for a commit made from a worktree
# on feature/y (same commits, different key).
_ledger reviewer-returned "${C4}" "arm=allowlist"
_WT="${TEST_TMPDIR}/wt-y"
git -C "${REPO}" worktree add -q -b feature/y "${_WT}" feature/x
_out="$(_k_run "git commit -m x" "${_WT}")"
assert_contains "K1 F7: reviewer under another branch key (worktree cwd) => REVIEW GUARD" "${_RG}" "$(_k_ctx "${_out}")"
_out="$(_k_run "git commit -m x")"
assert_not_contains "K1 F7 control: same reviewer from its own checkout => no REVIEW GUARD" "${_RG}" "$(_k_ctx "${_out}")"
# F7: an unresolvable root (cwd outside any repo) is not satisfied.
_NOREPO="${TEST_TMPDIR}/norepo"
mkdir -p "${_NOREPO}"
_out="$(_k_run "git commit -m x" "${_NOREPO}")"
assert_contains "K1 F7: no git toplevel at the cwd => REVIEW GUARD" "${_RG}" "$(_k_ctx "${_out}")"
teardown_test_env

echo "--- K1b: credited-skills.sh missing => the reviewer is not consulted ---"
_k_fresh
_ledger reviewer-returned "${C4}" "arm=allowlist"
_KCOPY="${TEST_TMPDIR}/plugin"
mkdir -p "${_KCOPY}"
cp -R "${PROJECT_ROOT}/hooks" "${PROJECT_ROOT}/scripts" "${PROJECT_ROOT}/config" "${_KCOPY}/"
[ -d "${PROJECT_ROOT}/.claude-plugin" ] && cp -R "${PROJECT_ROOT}/.claude-plugin" "${_KCOPY}/"
_kp="$(jq -nc '{"transcript_path":"/tmp/proj/conv-X.jsonl","tool_input":{"command":"git commit -m x"}}')"
_out="$( cd "${REPO}" && printf '%s' "${_kp}" | CLAUDE_PLUGIN_ROOT="${_KCOPY}" /bin/bash "${GUARD}" 2>/dev/null )"
assert_not_contains "K1b control: the copied root (lib present) credits" "${_RG}" "$(_k_ctx "${_out}")"
# A source that defines every function and then returns non-zero: the guard
# reads it as NOT loaded (the #198 status-predicate trade), so the push gate
# gives no reviewer credit and Check 4 must not either — the functions exist,
# so only Check 4's own _CREDITED_OK test stops it.
printf 'return 1\n' >> "${_KCOPY}/hooks/lib/credited-skills.sh"
_out="$( cd "${REPO}" && printf '%s' "${_kp}" | CLAUDE_PLUGIN_ROOT="${_KCOPY}" /bin/bash "${GUARD}" 2>/dev/null )"
assert_contains "K1b lib defines everything then returns 1 => not credited (REVIEW GUARD)" "${_RG}" "$(_k_ctx "${_out}")"
rm -f "${_KCOPY}/hooks/lib/credited-skills.sh"
_out="$( cd "${REPO}" && printf '%s' "${_kp}" | CLAUDE_PLUGIN_ROOT="${_KCOPY}" /bin/bash "${GUARD}" 2>/dev/null )"
assert_contains "K1b lib missing => covering reviewer not credited (REVIEW GUARD)" "${_RG}" "$(_k_ctx "${_out}")"
teardown_test_env

echo "--- K1c: a branch-ledger.sh that did not load does not feed Check 4's reviewer leg ---"
# Same rule as the push gate's _rr_ok (which needs _LEDGER_OK): a ledger lib
# that defines everything and then returns non-zero is NOT loaded, so the
# reviewer leg on a commit must not consult it.
_k_fresh
_ledger reviewer-returned "${C4}" "arm=allowlist"
_KCOPY="${TEST_TMPDIR}/plugin"
mkdir -p "${_KCOPY}"
cp -R "${PROJECT_ROOT}/hooks" "${PROJECT_ROOT}/scripts" "${PROJECT_ROOT}/config" "${_KCOPY}/"
[ -d "${PROJECT_ROOT}/.claude-plugin" ] && cp -R "${PROJECT_ROOT}/.claude-plugin" "${_KCOPY}/"
_kp="$(jq -nc '{"transcript_path":"/tmp/proj/conv-X.jsonl","tool_input":{"command":"git commit -m x"}}')"
_out="$( cd "${REPO}" && printf '%s' "${_kp}" | CLAUDE_PLUGIN_ROOT="${_KCOPY}" /bin/bash "${GUARD}" 2>/dev/null )"
assert_not_contains "K1c control: the copied root (ledger lib loads) credits" "${_RG}" "$(_k_ctx "${_out}")"
printf 'return 1\n' >> "${_KCOPY}/hooks/lib/branch-ledger.sh"
_out="$( cd "${REPO}" && printf '%s' "${_kp}" | CLAUDE_PLUGIN_ROOT="${_KCOPY}" /bin/bash "${GUARD}" 2>/dev/null )"
assert_not_empty "K1c ledger lib returns 1: SHIP advisories still emitted" "$(_k_ctx "${_out}")"
assert_contains "K1c ledger lib defines everything then returns 1 => REVIEW GUARD" "${_RG}" "$(_k_ctx "${_out}")"
teardown_test_env

echo "--- K2: Check 4 on a push agrees with the push gate ---"
_k_fresh
_ledger verification-before-completion ""
_ledger reviewer-returned "${C4}" "arm=allowlist"
_out="$(_k_run "git push origin HEAD")"
assert_equals "K2 covering reviewer: the push gate allows" "none" \
    "$(printf '%s' "${_out}" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null)"
assert_contains "K2 covering reviewer: the push gate's reviewer note is folded in" \
    "accepted via a returned reviewer" "$(_k_ctx "${_out}")"
assert_equals "K2 the reviewer note appears once" "1" \
    "$(_k_ctx "${_out}" | grep -o "accepted via a returned reviewer" | wc -l | tr -d ' ')"
assert_not_contains "K2 covering reviewer: no REVIEW GUARD contradicting the allow" "${_RG}" "$(_k_ctx "${_out}")"
# K2b: the push SUBJECT is covered, the session checkout's HEAD is not. The
# push gate credits the reviewer against the subject (C4); Check 4 must reuse
# that decision, not re-measure the checkout's HEAD (C5, material change),
# or the advisory contradicts the gate that just allowed the push.
printf 'echo three\n' > "${REPO}/src.sh"
git -C "${REPO}" add src.sh
_GIT -C "${REPO}" commit -q -m c5
_out="$(_k_run "git push origin ${C4}:refs/heads/z")"
assert_equals "K2b subject C4 covered: the push gate allows" "none" \
    "$(printf '%s' "${_out}" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null)"
assert_contains "K2b the push gate credited the reviewer" "accepted via a returned reviewer" "$(_k_ctx "${_out}")"
assert_not_contains "K2b Check 4 agrees with the push gate (no REVIEW GUARD)" "${_RG}" "$(_k_ctx "${_out}")"
_out="$(_k_run "git commit -m x")"
assert_contains "K2b control: a commit at the uncovered checkout HEAD still warns" "${_RG}" "$(_k_ctx "${_out}")"
teardown_test_env

echo "--- K3: a path that passed Check 4 before is byte-identical ---"
_k_fresh
_ledger requesting-code-review ""
_a="$(_k_run "git commit -m x")"
_ledger reviewer-returned "${C1}" "arm=allowlist"
_b="$(_k_run "git commit -m x")"
assert_not_contains "K3 ledger-satisfied: no REVIEW GUARD" "${_RG}" "$(_k_ctx "${_a}")"
assert_equals "K3 ledger-satisfied output unchanged by a (stale) reviewer record" "${_a}" "${_b}"
teardown_test_env

print_summary
