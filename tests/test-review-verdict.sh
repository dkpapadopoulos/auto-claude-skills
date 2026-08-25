#!/usr/bin/env bash
# test-review-verdict.sh — REVIEW verdict artifact + reader lib (#197).
#
# The push gate's REVIEW leg records INVOCATION, never WORK: Skill(...) returns
# the instruction body, so PostToolUse ^Skill$ fires BEFORE any reviewer could
# have run. This suite pins the split: STATUS may be satisfied by a Skill
# return, but a clean review VERDICT must require a recorded review.
#
# Bash 3.2 compatible (macOS default). Fail-open is asserted in both
# directions: an absent/malformed artifact must never block, and a missing lib
# must leave the gate's deny decisions byte-identical.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB="${PROJECT_ROOT}/hooks/lib/review-verdict.sh"
GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
WRITER="${PROJECT_ROOT}/scripts/record-review-verdict.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-review-verdict.sh ==="

if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required for this test" >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# 0. Artifacts exist
# ---------------------------------------------------------------------------
if [ -f "${LIB}" ]; then _record_pass "reader lib exists"
else _record_fail "reader lib exists" "no file at ${LIB}"; fi
if [ -f "${WRITER}" ]; then _record_pass "writer exists"
else _record_fail "writer exists" "no file at ${WRITER}"; fi

# Everything below needs the lib; bail loudly rather than vacuously passing.
if [ ! -f "${LIB}" ]; then
    _record_fail "lib present so the rest of the suite can run" "aborting remaining assertions"
    print_summary
    exit 1
fi

# shellcheck disable=SC1090
. "${LIB}"

for _fn in review_verdict_artifact_path review_verdict_is_clean \
           review_verdict_covers_head review_verdict_field; do
    if command -v "${_fn}" >/dev/null 2>&1; then _record_pass "lib defines ${_fn}"
    else _record_fail "lib defines ${_fn}" "function undefined after sourcing"; fi
done

# ---------------------------------------------------------------------------
# Fixture repo + isolated HOME
# ---------------------------------------------------------------------------
TMP="$(mktemp -d /tmp/revverdict-XXXXXX)"
REPO="${TMP}/repo"; mkdir -p "${REPO}"
# macOS /tmp is a symlink and branch-ledger keys hash the PHYSICAL toplevel.
REPO="$(cd "${REPO}" && pwd -P)"
(
  cd "${REPO}"
  git -c init.defaultBranch=main init -q
  git config user.email t@t; git config user.name t
  mkdir -p hooks/lib config
  printf 'substrate: local\ncommands:\n  - name: tests\n    run: true\n' > .verify.yml
  echo '{}' > config/default-triggers.json
  echo readme > README.md
  # A material (non-docs) source file: the verdict leg's population excludes
  # docs/*, openspec/* and *.md, so a README-only branch is correctly silent
  # and would make every guard assertion below vacuous.
  printf '#!/bin/bash\necho hi\n' > run.sh
  git add -A; git commit -qm base
  git checkout -qb feat
  echo "# c1" >> run.sh; git commit -qam c1
)
BASE_SHA="$(git -C "${REPO}" rev-parse main)"
HEAD_SHA="$(git -C "${REPO}" rev-parse HEAD)"

_OLDHOME="$HOME"
_FAKEHOME="$(mktemp -d /tmp/revverdict-home-XXXXXX)"
export HOME="${_FAKEHOME}"; mkdir -p "$HOME/.claude"
_TOK="session-t"
_ART="$HOME/.claude/.skill-review-verdict-${_TOK}"

_bool() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }

_write_verdict() { # <verdict> <head_sha> [unresolved_blocking]
    jq -nc --arg v "$1" --arg h "$2" --arg b "${BASE_SHA}" \
           --argjson ub "${3:-0}" \
        '{schema_version:1,provider:"local-agent",reviewed_base_sha:$b,
          reviewed_head_sha:$h,changed_file_digest:"deadbeefcafe",
          changed_file_count:1,findings_total:0,unresolved_blocking:$ub,
          verdict:$v,dispatch_attempted:true,dispatch_succeeded:true,
          ts:"2026-08-25T00:00:00Z",writer:"test"}' > "${_ART}"
}

# ---------------------------------------------------------------------------
# 1. Fail-open: absent / malformed / wrong-shape artifacts are never clean
# ---------------------------------------------------------------------------
rm -f "${_ART}"
assert_equals "absent artifact => not clean"    "1" "$(_bool review_verdict_is_clean "${_TOK}")"

printf 'not json at all\n' > "${_ART}"
assert_equals "malformed artifact => not clean" "1" "$(_bool review_verdict_is_clean "${_TOK}")"

printf '[]\n' > "${_ART}"
assert_equals "non-object artifact => not clean" "1" "$(_bool review_verdict_is_clean "${_TOK}")"

# ---------------------------------------------------------------------------
# 2. THE REGRESSION (#197). A Skill return credits STATUS via the completion
#    hook's ledger/invocation record. It must NOT produce a review verdict.
#    This is the assertion the whole issue is about: if it ever passes with a
#    bare Skill return, the status/verdict split has collapsed.
# ---------------------------------------------------------------------------
rm -f "${_ART}"
# Simulate exactly what a successful Skill return leaves behind: composition
# state with the milestone completed, plus a branch-ledger record.
jq -nc '{chain:["requesting-code-review","verification-before-completion"],
         completed:["requesting-code-review"]}' \
    > "$HOME/.claude/.skill-composition-state-${_TOK}"
printf '["requesting-code-review"]\n' > "$HOME/.claude/.skill-invocation-evidence-${_TOK}"
if [ -f "${PROJECT_ROOT}/hooks/lib/branch-ledger.sh" ]; then
    # shellcheck disable=SC1090
    . "${PROJECT_ROOT}/hooks/lib/branch-ledger.sh" 2>/dev/null || true
    ( cd "${REPO}" && command -v branch_ledger_record >/dev/null 2>&1 \
        && branch_ledger_record "requesting-code-review" "${REPO}" ) 2>/dev/null || true
fi
assert_equals "STATUS satisfied but NO review verdict => not clean" \
    "1" "$(_bool review_verdict_is_clean "${_TOK}")"
assert_equals "STATUS satisfied but NO review verdict => covers_head false" \
    "1" "$(_bool review_verdict_covers_head "${_TOK}" "${REPO}")"

# ---------------------------------------------------------------------------
# 3. A recorded review binds; a bad one does not
# ---------------------------------------------------------------------------
_write_verdict clean "${HEAD_SHA}"
assert_equals "clean verdict at HEAD => clean"        "0" "$(_bool review_verdict_is_clean "${_TOK}")"
assert_equals "clean verdict at HEAD => covers head"  "0" "$(_bool review_verdict_covers_head "${_TOK}" "${REPO}")"

_write_verdict findings-open "${HEAD_SHA}" 3
assert_equals "findings-open => NOT clean"            "1" "$(_bool review_verdict_is_clean "${_TOK}")"

_write_verdict could-not-review "${HEAD_SHA}"
assert_equals "could-not-review => NOT clean"         "1" "$(_bool review_verdict_is_clean "${_TOK}")"

# unresolved_blocking > 0 must never read clean even if verdict says so —
# a provider that disagrees with itself is not evidence.
_write_verdict clean "${HEAD_SHA}" 2
assert_equals "clean+unresolved_blocking>0 => NOT clean" "1" "$(_bool review_verdict_is_clean "${_TOK}")"

# ---------------------------------------------------------------------------
# 4. Subject binding: ancestor binds, mainline/unrelated does not
# ---------------------------------------------------------------------------
_ANCESTOR="${HEAD_SHA}"
( cd "${REPO}" && echo "# c2" >> run.sh && git commit -qam c2 )
_NEWHEAD="$(git -C "${REPO}" rev-parse HEAD)"
_write_verdict clean "${_ANCESTOR}"
assert_equals "branch-local ancestor binds"     "0" "$(_bool review_verdict_covers_head "${_TOK}" "${REPO}")"

_write_verdict clean "${BASE_SHA}"
assert_equals "mainline-reachable sha does NOT bind" "1" "$(_bool review_verdict_covers_head "${_TOK}" "${REPO}")"

_write_verdict clean "0000000000000000000000000000000000000000"
assert_equals "unrelated sha does NOT bind"     "1" "$(_bool review_verdict_covers_head "${_TOK}" "${REPO}")"

# ---------------------------------------------------------------------------
# 5. Writer round-trips through the reader
# ---------------------------------------------------------------------------
if [ -f "${WRITER}" ]; then
    rm -f "${_ART}"
    ( cd "${REPO}" && SKILL_SESSION_TOKEN="${_TOK}" bash "${WRITER}" \
        --provider local-agent --verdict clean \
        --base "${BASE_SHA}" --head "${_NEWHEAD}" \
        --findings 4 --unresolved-blocking 0 ) >/dev/null 2>&1
    if [ -f "${_ART}" ]; then
        _record_pass "writer produced an artifact"
        assert_equals "writer output is clean per the reader" "0" "$(_bool review_verdict_is_clean "${_TOK}")"
        assert_equals "writer records the provider" "local-agent" \
            "$(review_verdict_field "${_TOK}" provider 2>/dev/null)"
        assert_equals "writer records schema_version" "1" \
            "$(review_verdict_field "${_TOK}" schema_version 2>/dev/null)"
    else
        _record_fail "writer produced an artifact" "no file at ${_ART} after invoking ${WRITER}"
    fi
    # A writer must refuse to invent a clean verdict with no subject.
    rm -f "${_ART}"
    ( cd "${REPO}" && SKILL_SESSION_TOKEN="${_TOK}" bash "${WRITER}" \
        --provider local-agent --verdict clean ) >/dev/null 2>&1
    out="$( [ -f "${_ART}" ] && review_verdict_field "${_TOK}" verdict 2>/dev/null || echo "<absent>" )"
    if [ "${out}" = "clean" ]; then
        _record_fail "writer refuses a subject-less clean verdict" \
            "wrote verdict=clean with no --base/--head; that is an unbound claim"
    else
        _record_pass "writer refuses a subject-less clean verdict (got: ${out})"
    fi
fi

# ---------------------------------------------------------------------------
# 6. Guard e2e: advisory emitted, NEVER a deny; missing lib changes nothing
# ---------------------------------------------------------------------------
_TPATH="$HOME/t.jsonl"; touch "$_TPATH"   # basename "t" -> token "session-t"
_mkinput() {
    jq -n --arg tp "$_TPATH" --arg cmd "${1:-git push origin HEAD}" \
        '{"transcript_path":$tp,"tool_input":{"command":$cmd}}'
}
# NO ACSM_SKIP_PUSH_GATE here. That env sets _PUSHGATE_SKIP=true, which skips
# the ENTIRE composition-state region -- Checks 1, 1b, 2 and 0 -- so a bypassed
# run can never exercise this leg. (The evaluator-surface advisory is emitted
# outside that region, which is why its suite can use the bypass and this one
# cannot.) Instead the push is made GENUINELY allowable: both gating milestones
# completed and a clean verification verdict seeded at HEAD.
_seed_allow() {
    jq -nc '{chain:["requesting-code-review","verification-before-completion"],
             completed:["requesting-code-review","verification-before-completion"]}' \
        > "$HOME/.claude/.skill-composition-state-${_TOK}"
    jq -nc --arg s "$(git -C "${REPO}" rev-parse HEAD)" \
        '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}' \
        > "$HOME/.claude/.skill-project-verified-${_TOK}"
}
_run_guard() {
    _seed_allow
    ( cd "${REPO}" && _mkinput "${1:-git push origin HEAD}" \
        | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" 2>/dev/null )
}

rm -f "${_ART}"
out="$(_run_guard)"
assert_contains     "no-verdict push emits a review advisory" "REVIEW VERDICT" "${out:-<empty>}"
assert_not_contains "review advisory never denies"            '"deny"'         "${out:-}"

_write_verdict clean "${_NEWHEAD}"
out="$(_run_guard)"
assert_not_contains "clean verdict at HEAD => no review advisory" "REVIEW VERDICT" "${out:-}"

# ---------------------------------------------------------------------------
# 7. Fail-open: with the reader lib ABSENT the gate must not deny and must not
#    claim a review is missing. Spec scenario "Missing reader library degrades
#    silently, never blocks". Done here rather than by deleting the file from
#    the repo, because the suite aborts early without the lib -- so that path
#    can never assert this. The lib is moved aside and restored under a trap so
#    a mid-test failure cannot leave the repo missing a gate file.
# ---------------------------------------------------------------------------
_LIB_HIDDEN="${TMP}/review-verdict.sh.hidden"
_restore_lib() { [ -f "${_LIB_HIDDEN}" ] && mv -f "${_LIB_HIDDEN}" "${LIB}"; }
trap _restore_lib EXIT INT TERM
rm -f "${_ART}"
if mv "${LIB}" "${_LIB_HIDDEN}" 2>/dev/null; then
    out="$(_run_guard)"
    assert_not_contains "lib absent => gate does not deny"            '"deny"'         "${out:-}"
    assert_not_contains "lib absent => no false 'no review' claim"    "was credited"   "${out:-}"
    assert_contains     "lib absent => says it could not check"       "could not check" "${out:-<empty>}"
    _restore_lib
    if [ -f "${LIB}" ]; then _record_pass "reader lib restored after the fail-open case"
    else _record_fail "reader lib restored after the fail-open case" "still at ${_LIB_HIDDEN}"; fi
else
    _record_fail "could move the lib aside for the fail-open case" "mv failed; fail-open path untested"
fi
trap - EXIT INT TERM

export HOME="$_OLDHOME"
rm -rf "${TMP}" "${_FAKEHOME}"
print_summary
exit $?
