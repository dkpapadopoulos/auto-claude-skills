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
        assert_equals "writer records schema_version" "2" \
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

# ---------------------------------------------------------------------------
# 8. Static: the leg's call sites must pass a variable the guard DEFINES.
#    Review caught `${_PROJ_ROOT}` at both sites -- a name defined nowhere in
#    the guard (it calls the root `_proot`). It expanded to empty, the lib's
#    own cwd fallback silently covered for it, and every runtime test still
#    passed: binding was computed against the hook's CWD instead of the
#    resolved root, and the corpus recorded a CWD-derived repo/branch, which
#    corrupts the pre-registered (repo, branch, session_token) episode key.
#    Runtime cannot see this class, so assert it statically.
# ---------------------------------------------------------------------------
_bad_root="$(grep -n 'review_verdict_covers_head\|review_shadow_record' "${GUARD}" 2>/dev/null | grep -c '_PROJ_ROOT' | tr -d '[:space:]')"
assert_equals "guard passes no undefined _PROJ_ROOT to the review leg" "0" "${_bad_root:-0}"

# Non-vacuity: the grep must actually be finding the call sites, or the check
# above passes because it matched nothing.
_sites="$(grep -c 'review_verdict_covers_head\|review_shadow_record' "${GUARD}" 2>/dev/null | tr -d '[:space:]')"
if [ "${_sites:-0}" -ge 2 ]; then _record_pass "found the review leg's call sites (${_sites})"
else _record_fail "found the review leg's call sites" "expected >=2, got ${_sites:-0} -- the check above is vacuous"; fi

# Every variable the call sites pass must be assigned somewhere in the guard.
_undef=""
for _v in _proot _SESSION_TOKEN; do
    grep -q "^[[:space:]]*${_v}=" "${GUARD}" 2>/dev/null || _undef="${_undef} ${_v}"
done
assert_equals "call-site variables are assigned in the guard" "" "${_undef}"

# ---------------------------------------------------------------------------
# 9. Reason classifier: not-clean AND unbound is "not-clean", never "absent".
#    Both are candidate true catches so the RATE is unaffected, but `absent`
#    tells the user to record a review when one already ran and found blocking
#    findings -- the wrong remedy, and a mislabelled corpus row.
# ---------------------------------------------------------------------------
_SHADOW="${TMP}/shadow.jsonl"
rm -f "${_SHADOW}"
# The cell that matters is (!clean AND !bound) -- the one the `absent` arm used
# to swallow. An ancestor-bound verdict is BOUND, so it exercises the already
# correct (!clean && bound) arm instead; mutation testing caught that this
# scenario left the fix uncovered. A mainline-reachable sha does not bind, so
# findings-open there is genuinely not-clean AND not-bound.
_write_verdict findings-open "${BASE_SHA}" 2
( cd "${REPO}" && printf '# c3\n' >> run.sh && git commit -qam c3 ) >/dev/null 2>&1
_seed_allow
( cd "${REPO}" && _mkinput "git push origin HEAD" \
    | REVIEW_SHADOW_LOG="${_SHADOW}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" >/dev/null 2>&1 )
if [ -f "${_SHADOW}" ]; then
    _reason="$(jq -r '.reason' "${_SHADOW}" 2>/dev/null | tail -1)"
    assert_equals "existing-but-stale verdict records reason=not-clean" "not-clean" "${_reason:-<none>}"
    _rrepo="$(jq -r '.repo' "${_SHADOW}" 2>/dev/null | tail -1)"
    if [ -n "${_rrepo}" ] && [ "${_rrepo}" != "null" ]; then
        _record_pass "shadow record carries a repo (episode key intact)"
    else
        _record_fail "shadow record carries a repo (episode key intact)" "repo was '${_rrepo}' -- episode key corrupted"
    fi
else
    _record_fail "shadow record written for a would-block" "no file at ${_SHADOW}"
fi

# Companion cell: not-clean but BOUND (ancestor). Different arm, same label --
# pinning both means neither arm can be deleted without a red test.
rm -f "${_SHADOW}"
_write_verdict findings-open "${_ANCESTOR}" 2
_seed_allow
( cd "${REPO}" && _mkinput "git push origin HEAD" \
    | REVIEW_SHADOW_LOG="${_SHADOW}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" >/dev/null 2>&1 )
_reason2="$(jq -r '.reason' "${_SHADOW}" 2>/dev/null | tail -1)"
assert_equals "not-clean AND bound also records reason=not-clean" "not-clean" "${_reason2:-<none>}"

# And the absent cell must still say absent, or the fix would have collapsed
# every case into not-clean -- the opposite over-correction.
rm -f "${_SHADOW}" "${_ART}"
_seed_allow
( cd "${REPO}" && _mkinput "git push origin HEAD" \
    | REVIEW_SHADOW_LOG="${_SHADOW}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" >/dev/null 2>&1 )
_reason3="$(jq -r '.reason' "${_SHADOW}" 2>/dev/null | tail -1)"
assert_equals "no artifact at all still records reason=absent" "absent" "${_reason3:-<none>}"

# --- observed dispatch telemetry (spec: observed-dispatch-telemetry) ---
# A seeded reviewer-ran record must upgrade the telemetry to measured.
_ODT_RAW="$(mktemp -d /tmp/odt-repo-XXXXXX)"
( cd "$_ODT_RAW" && git init -q && git config user.email t@t && git config user.name t \
  && git commit -q --allow-empty -m init )
# D4, and this is NOT theoretical — it was measured while writing this plan.
# Seed the ledger with git's CANONICAL toplevel, never the mktemp path. On
# macOS /tmp is a symlink to /private/tmp, and branch_ledger_key hashes the RAW
# path string, so the two differ:
#     /tmp/x         -> eff78f10...
#     /private/tmp/x -> 35e951cd...
# The script reads via `git rev-parse --show-toplevel`, so seeding with the
# mktemp path writes a key it will never read, and assertion (a) fails looking
# exactly like "the derivation is broken".
_ODT_REPO="$(cd "$_ODT_RAW" && git rev-parse --show-toplevel)"
# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/branch-ledger.sh"

_odt_record() {   # $@ = extra flags for record-review-verdict.sh
    ( cd "$_ODT_REPO" && SKILL_SESSION_TOKEN="$_TOK" \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "${PROJECT_ROOT}/scripts/record-review-verdict.sh" \
        --provider local-agent --verdict clean \
        --base "$(git -C "$_ODT_REPO" rev-parse HEAD)" \
        --head "$(git -C "$_ODT_REPO" rev-parse HEAD)" "$@" ) >/dev/null 2>&1
}
_odt_field() { review_verdict_field "$_TOK" "$1" 2>/dev/null; }

# (a) an observation upgrades the telemetry and is labelled observed
branch_ledger_record "reviewer-ran" "$_ODT_REPO"
_odt_record
assert_equals "observed dispatch is recorded as observed" "observed" "$(_odt_field dispatch_evidence)"
assert_equals "observed dispatch sets attempted"          "true"     "$(_odt_field dispatch_attempted)"
assert_equals "observed dispatch sets succeeded"          "true"     "$(_odt_field dispatch_succeeded)"

# (b) with NO observation, explicit flags are recorded as asserted, never observed
find "$HOME/.claude" -maxdepth 1 -type d -name '.skill-branch-ledger-*' -exec rm -rf {} + 2>/dev/null
_odt_record --dispatch-attempted --dispatch-succeeded
assert_equals "asserted flags are labelled asserted" "asserted" "$(_odt_field dispatch_evidence)"

# (c) no observation and no flags: both false, still asserted
find "$HOME/.claude" -maxdepth 1 -type d -name '.skill-branch-ledger-*' -exec rm -rf {} + 2>/dev/null
_odt_record
assert_equals "absent dispatch is not observed"  "asserted" "$(_odt_field dispatch_evidence)"
assert_equals "absent dispatch is false"         "false"    "$(_odt_field dispatch_attempted)"

# (d) the schema version is bumped
assert_equals "writer records schema_version 2" "2" "$(_odt_field schema_version)"
rm -rf "$_ODT_RAW"

export HOME="$_OLDHOME"
rm -rf "${TMP}" "${_FAKEHOME}"
print_summary
exit $?
