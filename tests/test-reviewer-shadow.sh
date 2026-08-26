#!/usr/bin/env bash
# test-reviewer-shadow.sh — hooks/lib/reviewer-shadow.sh and its wiring into the
# ADVISORY reviewer-evidence leg (openspec/changes/reviewer-dispatch-and-evidence).
#
# TWO HALVES, and the second is the load-bearing one. The unit half drives the
# lib directly; the e2e half drives the REAL hooks/openspec-guard.sh over a real
# git repo and a real branch ledger. A unit-only suite would only ever prove the
# recorder agrees with the test's own idea of what the leg passes it — the
# stub-fixture failure mode CLAUDE.md documents for the push-gate capture
# classifier, where every assertion stayed green while the field was wrong
# end-to-end for 26 records.
#
# The corpus this feeds decides a pre-registered deny-flip, so the assertions
# that matter most are the ones proving the THREE evidence states stay distinct
# through the real guard. `stale` is the routine steady-state outcome once the
# recorder is populated (review -> fix -> commit -> push moves HEAD off the
# bound SHA), so a collapse into `present` or `missing` would not look like a
# bug — it would look like a clean corpus.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-reviewer-shadow.sh ==="

LIB="${PROJECT_ROOT}/hooks/lib/reviewer-shadow.sh"
GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
FIXTURE="${SCRIPT_DIR}/fixtures/reviewer-evidence/satisfied-control.json"

# ---------------------------------------------------------------------------
# UNIT half
# ---------------------------------------------------------------------------
_UDIR="$(mktemp -d /tmp/rsh-unit-XXXXXX)"
export REVIEWER_SHADOW_LOG="${_UDIR}/shadow.jsonl"

# shellcheck disable=SC1090
. "${LIB}"

_field() { jq -rs --argjson i "$1" --arg k "$2" '.[$i][$k]' "${REVIEWER_SHADOW_LOG}" 2>/dev/null; }

reviewer_shadow_record "push" "${_UDIR}" "session-t" "/tmp/t.jsonl" "missing" "" "literal" "unknown"
if [ -s "${REVIEWER_SHADOW_LOG}" ]; then
    _record_pass "a record is written"
else
    _record_fail "a record is written" "log empty"
fi

if jq -e 'select(.schema_version == 1 and .predicate_version == 1
                 and .gate == "push-reviewer-evidence"
                 and .action == "push"
                 and .review_credited == true
                 and .evidence_present == "missing"
                 and .review_credited_by == "literal"
                 and .is_error_field == "unknown"
                 and (.record_id | length) > 0
                 and (.ts | length) > 0)' \
     "${REVIEWER_SHADOW_LOG}" >/dev/null 2>&1; then
    _record_pass "record carries the pre-registered fields, typed"
else
    _record_fail "record carries the pre-registered fields, typed" "$(cat "${REVIEWER_SHADOW_LOG}")"
fi

# THE assertion this file exists for: four distinct evidence states, none
# collapsed. A boolean here silently destroys the measurement.
: > "${REVIEWER_SHADOW_LOG}"
reviewer_shadow_record "push" "${_UDIR}" "s" "" "present"      "aaa" "literal" "unknown"
reviewer_shadow_record "push" "${_UDIR}" "s" "" "stale"        "bbb" "literal" "unknown"
reviewer_shadow_record "push" "${_UDIR}" "s" "" "missing"      ""    "literal" "unknown"
reviewer_shadow_record "push" "${_UDIR}" "s" "" "cannot_check" ""    "literal" "unknown"
_STATES="$(jq -rs '[.[].evidence_present] | join(",")' "${REVIEWER_SHADOW_LOG}" 2>/dev/null)"
if [ "${_STATES}" = "present,stale,missing,cannot_check" ]; then
    _record_pass "evidence_present keeps four states distinct (stale is NOT folded)"
else
    _record_fail "evidence_present keeps four states distinct (stale is NOT folded)" \
                 "got: ${_STATES}"
fi

# design D7: proxy-credited episodes must be segmentable or the flip is decided
# on pooled data.
: > "${REVIEWER_SHADOW_LOG}"
reviewer_shadow_record "push" "${_UDIR}" "s" "" "missing" "" "agent-team-execution" "unknown"
reviewer_shadow_record "push" "${_UDIR}" "s" "" "missing" "" "literal" "unknown"
if [ "$(jq -rs '[.[] | select(.review_credited_by == "agent-team-execution")] | length' \
        "${REVIEWER_SHADOW_LOG}" 2>/dev/null)" = "1" ]; then
    _record_pass "proxy-credited episodes are segmentable"
else
    _record_fail "proxy-credited episodes are segmentable" "$(cat "${REVIEWER_SHADOW_LOG}")"
fi

# The blocking precondition (Pre-registration): present-vs-absent must survive
# into the record, and "unknown" must be its own third value — not a default
# that reads as a confirmed assumption.
: > "${REVIEWER_SHADOW_LOG}"
reviewer_shadow_record "push" "${_UDIR}" "s" "" "present" "a" "literal" "present"
reviewer_shadow_record "push" "${_UDIR}" "s" "" "present" "a" "literal" "absent"
reviewer_shadow_record "push" "${_UDIR}" "s" "" "present" "a" "literal" ""
_IEF="$(jq -rs '[.[].is_error_field] | join(",")' "${REVIEWER_SHADOW_LOG}" 2>/dev/null)"
if [ "${_IEF}" = "present,absent,unknown" ]; then
    _record_pass "is_error_field records present / absent / unknown distinctly"
else
    _record_fail "is_error_field records present / absent / unknown distinctly" "got: ${_IEF}"
fi

# An unrecognised value must degrade to "unknown", never be written through: a
# caller typo would otherwise mint a new category and split the corpus silently.
: > "${REVIEWER_SHADOW_LOG}"
reviewer_shadow_record "push" "${_UDIR}" "s" "" "yes" "a" "some-other-skill" "maybe"
if [ "$(_field 0 evidence_present)" = "unknown" ] \
   && [ "$(_field 0 review_credited_by)" = "unknown" ] \
   && [ "$(_field 0 is_error_field)" = "unknown" ]; then
    _record_pass "out-of-vocabulary values degrade to unknown"
else
    _record_fail "out-of-vocabulary values degrade to unknown" "$(cat "${REVIEWER_SHADOW_LOG}")"
fi

# Append-only, with unique ids: an episode collapse over (repo, branch, token)
# needs every consultation to survive as its own row.
: > "${REVIEWER_SHADOW_LOG}"
reviewer_shadow_record "push" "${_UDIR}" "s" "" "missing" "" "literal" "unknown"
reviewer_shadow_record "push" "${_UDIR}" "s" "" "missing" "" "literal" "unknown"
reviewer_shadow_record "push" "${_UDIR}" "s" "" "missing" "" "literal" "unknown"
if [ "$(wc -l < "${REVIEWER_SHADOW_LOG}" | tr -d ' ')" = "3" ] \
   && [ "$(jq -rs '[.[].record_id] | unique | length' "${REVIEWER_SHADOW_LOG}" 2>/dev/null)" = "3" ]; then
    _record_pass "records append with unique ids"
else
    _record_fail "records append with unique ids" "$(cat "${REVIEWER_SHADOW_LOG}")"
fi

# The log carries repo/branch/session_token, so it must not be world-readable.
_PERM="$(ls -l "${REVIEWER_SHADOW_LOG}" 2>/dev/null | cut -c1-10)"
case "${_PERM}" in
    -rw-------) _record_pass "log is created 0600" ;;
    *) _record_fail "log is created 0600" "mode: ${_PERM}" ;;
esac

# The recorder runs on the gate path, which has a one-JSON-object stdout
# contract: a single stray byte would corrupt the hook's output.
_NOISE="$(reviewer_shadow_record "push" "${_UDIR}" "s" "" "missing" "" "literal" "unknown" 2>/dev/null)"
if [ -z "${_NOISE}" ]; then
    _record_pass "recorder writes nothing to stdout"
else
    _record_fail "recorder writes nothing to stdout" "emitted: ${_NOISE}"
fi

# It must never break its caller. Run in a subshell so a stray exit is caught
# here rather than killing the suite.
( . "${LIB}"; REVIEWER_SHADOW_LOG="/nonexistent-dir/x.jsonl" \
  reviewer_shadow_record "push" "/tmp" "s" "" "missing" "" "literal" "unknown" ) >/dev/null 2>&1
if [ "$?" = "0" ]; then
    _record_pass "unwritable log degrades with return 0"
else
    _record_fail "unwritable log degrades with return 0" "non-zero return"
fi

rm -rf "${_UDIR}" 2>/dev/null || true
unset REVIEWER_SHADOW_LOG

# ---------------------------------------------------------------------------
# SOURCE-TIME SAFETY — the property that currently holds by ACCIDENT.
#
# hooks/lib/reviewer-shadow.sh is sourced at TOP LEVEL of openspec-guard.sh,
# ABOVE every deny check, in a hook carrying `trap 'exit 0' ERR` (line 6).
# Measured under real /bin/bash 3.2.57:
#
#   healthy source                       -> execution continues, deny checks run
#   lib unreadable (chmod 000)           -> continues
#   lib absent entirely                  -> continues
#   lib with a FAILING top-level command -> TRAP FIRES, everything below SKIPPED
#
# That last row is the issue-#192 residual, and in THIS hook "everything below"
# is the push gate's entire deny path: a push that should DENY is silently
# ALLOWED. The `|| true` on the source line does NOT protect against it — it
# covers the `.` builtin's own exit status, while this trap fires *during* the
# sourced file's execution (the same distinction tests/test-hook-source-guards.sh
# documents as explicitly out of its scope).
#
# So the guard's source form cannot make this safe. Only the lib's CONTENTS can,
# and nothing pinned them: the lib is safe today solely because its top level is
# two literal constant assignments and two function definitions. A later
# top-level `_X="$(command)"` or `command -v` probe would silently disable the
# push gate's enforcement, and no other test in this repo would notice.
#
# Three assertions, because a static lint alone can rot into agreeing with
# itself: (1) the real lib is clean, (2) a RED CONTROL proving the lint can
# still fail, and (3) an EMPIRICAL pin of the underlying trap behaviour, so the
# lint's rationale is measured rather than asserted from a comment.
# ---------------------------------------------------------------------------
_LINTDIR="$(mktemp -d /tmp/rsh-lint-XXXXXX)"

# _toplevel_bad <file> — print every top-level statement that is not a literal
# assignment, a function opener, or a closing brace. Non-comment, non-blank and
# non-indented is the definition of top-level here; the quoted-literal form is
# allowed only when it contains no $, no backtick and no embedded quote, so no
# expansion or command substitution can hide inside it.
_toplevel_bad() {
    grep -vE '^[[:space:]]*(#|$)' "$1" 2>/dev/null \
      | grep -vE '^[[:space:]]' \
      | grep -vE '^[A-Za-z_][A-Za-z0-9_]*=[A-Za-z0-9_.:/-]*$|^[A-Za-z_][A-Za-z0-9_]*="[^"$`]*"$|^[a-z_][a-z0-9_]*\(\)[[:space:]]*\{$|^\}$'
    return 0
}

_BAD="$(_toplevel_bad "${LIB}")"
if [ -z "${_BAD}" ]; then
    _record_pass "lib has no failing-capable top-level statements"
else
    _record_fail "lib has no failing-capable top-level statements" \
"This lib is sourced at top level in openspec-guard.sh ABOVE every deny check, in a hook with trap 'exit 0' ERR. A top-level statement that can FAIL (command substitution, a command -v probe, any command at all) trips that trap DURING the source and silently skips the whole push-gate deny path — an allowed push that should have been denied. The source line's || true does not cover this. Keep the top level to literal assignments and function definitions; put anything that can fail INSIDE a function. Offending line(s): ${_BAD}"
fi

# RED CONTROL. Without it a broken lint reads exactly like a clean lib — the
# vacuity this whole change has already hit once (assertion (e) of
# test-reviewer-evidence-leg.sh, and the push-gate capture classifier before it).
cp "${LIB}" "${_LINTDIR}/mutated.sh"
printf '%s\n' '_X="$(false)"' >> "${_LINTDIR}/mutated.sh"
_BADCTL="$(_toplevel_bad "${_LINTDIR}/mutated.sh")"
case "${_BADCTL}" in
    *'_X="$(false)"'*) _record_pass "red control: the lint flags an injected top-level command" ;;
    *) _record_fail "red control: the lint flags an injected top-level command" \
                    "lint is vacuous — injected line not reported (got: ${_BADCTL})" ;;
esac

# EMPIRICAL pin of WHY. Reproduces the guard's shape — trap + the exact guarded
# source form from openspec-guard.sh — under real /bin/bash, and checks whether
# the code BELOW the source still runs. Real /bin/bash on purpose: the model's
# shell is zsh and the trap semantics under test are bash's.
_probe_reaches() {
    /bin/bash -c '
        trap "exit 0" ERR
        [ -f "$1" ] && . "$1" 2>/dev/null || true
        printf REACHED
    ' _ "$1" 2>/dev/null
}
cp "${LIB}" "${_LINTDIR}/clean.sh"
cp "${LIB}" "${_LINTDIR}/failing.sh"
printf '%s\n' 'nosuchcommand_xyz_probe' >> "${_LINTDIR}/failing.sh"
_R_CLEAN="$(_probe_reaches "${_LINTDIR}/clean.sh")"
_R_FAIL="$(_probe_reaches "${_LINTDIR}/failing.sh")"
if [ "${_R_CLEAN}" = "REACHED" ] && [ "${_R_FAIL}" != "REACHED" ]; then
    _record_pass "measured: a failing top-level statement skips everything below the source"
else
    _record_fail "measured: a failing top-level statement skips everything below the source" \
                 "clean='${_R_CLEAN}' (want REACHED), failing='${_R_FAIL}' (want empty). If the failing case now reaches, the ERR-trap residual (#192) changed and this lint's rationale must be re-derived before it is relaxed."
fi

rm -rf "${_LINTDIR}" 2>/dev/null || true

# ---------------------------------------------------------------------------
# E2E half — the REAL guard, a real repo, a real ledger.
# ---------------------------------------------------------------------------
_OLDHOME="$HOME"
_TMPHOME="$(mktemp -d /tmp/rsh-home-XXXXXX)"
export HOME="${_TMPHOME}"
mkdir -p "$HOME/.claude"
_TPATH="$HOME/t.jsonl"; touch "$_TPATH"
_TOKEN="session-$(basename "${_TPATH}" .jsonl)"

# PHYSICAL path, mandatory — see the note in test-reviewer-evidence-leg.sh: an
# unresolved /tmp path yields a different branch-ledger key, so the own-key leg
# misses and the #131 bridge rescues it, and every assertion measures the bridge.
_REPO="$(mktemp -d /tmp/rsh-repo-XXXXXX)"
_REPO="$(cd "$_REPO" && pwd -P)"
( cd "$_REPO" && git init -q && git config user.email t@t && git config user.name t \
  && git commit -q --allow-empty -m init ) >/dev/null 2>&1

# A plugin copy whose branch-ledger.sh cannot be sourced — the cannot_check row.
_BROKEN="$(mktemp -d /tmp/rsh-broken-XXXXXX)"
cp -R "${PROJECT_ROOT}/hooks" "${_BROKEN}/hooks"
chmod 000 "${_BROKEN}/hooks/lib/branch-ledger.sh"

# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/branch-ledger.sh"

_LOG="$HOME/shadow.jsonl"
_clear() {
    rm -rf "$HOME"/.claude/.skill-branch-ledger-* "$HOME"/.claude/.skill-composition-state-* \
           "$HOME"/.claude/.skill-invocation-evidence-* 2>/dev/null || true
    rm -f "${_LOG}" 2>/dev/null || true
}
_seed_review()   { branch_ledger_record "requesting-code-review" "$_REPO"; }
_seed_verify()   { branch_ledger_record "verification-before-completion" "$_REPO"; }
_seed_reviewer() { branch_ledger_record "reviewer-ran" "$_REPO"; }

_payload() {
    jq -n --arg tp "$_TPATH" --arg c "$_REPO" \
      '{transcript_path:$tp,cwd:$c,tool_name:"Bash",tool_input:{command:"git push"}}'
}
# No `< /dev/null` anywhere near this: the payload arrives on a PIPE and a
# redirect would override it, leaving the hook reading empty input.
_push() {
    local _root="${1:-${PROJECT_ROOT}}" _log="${2:-${_LOG}}"
    _payload | ( cd "$_REPO" && CLAUDE_PLUGIN_ROOT="${_root}" REVIEWER_SHADOW_LOG="${_log}" \
        bash "${_root}/hooks/openspec-guard.sh" ) 2>/dev/null
}
_state() { jq -rs '.[-1].evidence_present // "NONE"' "${_LOG}" 2>/dev/null || printf 'NONE'; }

# (1) reviewer-ran ABSENT — the would-advise the corpus is built from.
_clear; _seed_review; _seed_verify
_out_missing="$(_push)"
if [ "$(_state)" = "missing" ]; then
    _record_pass "e2e: a would-advise records evidence_present=missing"
else
    _record_fail "e2e: a would-advise records evidence_present=missing" \
                 "state $(_state); log: $(cat "${_LOG}" 2>/dev/null)"
fi

# (2) reviewer-ran bound to an OLDER commit. This is the steady-state row: if it
#     reports `present` or `missing` the corpus cannot answer the question the
#     deny-flip turns on.
_clear; _seed_reviewer
( cd "$_REPO" && git commit -q --allow-empty -m later ) >/dev/null 2>&1
_seed_review; _seed_verify
_push >/dev/null
if [ "$(_state)" = "stale" ]; then
    _record_pass "e2e: SHA-trailing reviewer evidence records stale, not present"
else
    _record_fail "e2e: SHA-trailing reviewer evidence records stale, not present" \
                 "state $(_state); log: $(cat "${_LOG}" 2>/dev/null)"
fi

# (3) reviewer-ran at HEAD — the satisfied row. Recorded too: without the
#     satisfied episodes the corpus has no denominator.
_clear; _seed_review; _seed_verify; _seed_reviewer
_out_satisfied="$(_push)"
if [ "$(_state)" = "present" ]; then
    _record_pass "e2e: satisfied consultations are recorded as present"
else
    _record_fail "e2e: satisfied consultations are recorded as present" \
                 "state $(_state); log: $(cat "${_LOG}" 2>/dev/null)"
fi

# (4) Un-checkable, not absent. Recording this as `missing` would count an
#     infrastructure failure as non-compliance — the direction that biases the
#     pre-registered rate toward clearing the flip.
_clear
cat > "$HOME/.claude/.skill-composition-state-${_TOKEN}" <<'EOF'
{"chain":["requesting-code-review","verification-before-completion"],
 "completed":["requesting-code-review","verification-before-completion"]}
EOF
_push "${_BROKEN}" >/dev/null
if [ "$(_state)" = "cannot_check" ]; then
    _record_pass "e2e: an unusable ledger records cannot_check, not missing"
else
    _record_fail "e2e: an unusable ledger records cannot_check, not missing" \
                 "state $(_state); log: $(cat "${_LOG}" 2>/dev/null)"
fi

# (5) Attribution comes from the invocation-evidence array, since the ledger
#     stores every proxy under the canonical name (design D7).
_clear
printf '%s\n' '["agent-team-execution"]' > "$HOME/.claude/.skill-invocation-evidence-${_TOKEN}"
_seed_review; _seed_verify
_push >/dev/null
if [ "$(jq -rs '.[-1].review_credited_by' "${_LOG}" 2>/dev/null)" = "agent-team-execution" ]; then
    _record_pass "e2e: proxy attribution is resolved from invocation evidence"
else
    _record_fail "e2e: proxy attribution is resolved from invocation evidence" \
                 "log: $(cat "${_LOG}" 2>/dev/null)"
fi

# (6) Population is narrow: where REVIEW is not credited the deny legs own the
#     outcome, the leg says nothing, and NOTHING may enter the corpus — a record
#     there would inflate the denominator with episodes the leg never judged.
_clear
_push >/dev/null
if [ ! -s "${_LOG}" ]; then
    _record_pass "e2e: no record where REVIEW is not credited at all"
else
    _record_fail "e2e: no record where REVIEW is not credited at all" "$(cat "${_LOG}")"
fi

# (7) A push some OTHER leg denied records nothing. The leg is consulted where
#     the REVIEW milestone is credited, which is above the VERIFY,
#     verify-hardening, global fail-closed, phase-enforcement and
#     routing-governance denies. Such a push was blocked regardless of anything
#     this advisory leg said, so it can never be a false block attributable to
#     THIS leg — recorded, it enters the corpus as a k=0 "no false block" row,
#     shrinks the Clopper-Pearson upper bound and biases the pre-registered
#     deny-flip TOWARD turning denial on. Same rule, same reasoning as the
#     merge exclusion; rows are not retro-classifiable, so a wrong-predicate
#     row discards the corpus rather than being fixable later.
#
#     REVIEW credited but VERIFY not => the global fail-closed gate denies,
#     downstream of the consultation.
_clear; _seed_review
_out_denied="$(_push)"
if printf '%s' "${_out_denied}" | grep -qF '"permissionDecision"' && [ ! -s "${_LOG}" ]; then
    _record_pass "e2e: a push denied by another leg records no row"
else
    _record_fail "e2e: a push denied by another leg records no row" \
                 "gate output: $(printf '%s' "${_out_denied}" | tr -d '\n' | cut -c1-140); log: $(cat "${_LOG}" 2>/dev/null)"
fi

# (8) The paired half of (7), and it is NOT redundant with (1): (7) alone is
#     satisfied by a fix that suppresses EVERY row, which would silently empty
#     the corpus. An allowed push whose advisory is the operative outcome must
#     record exactly one row — not zero, and not one per consultation site.
_clear; _seed_review; _seed_verify
_push >/dev/null
_ROWCOUNT="$(wc -l < "${_LOG}" 2>/dev/null | tr -d ' ')"
if [ "${_ROWCOUNT}" = "1" ]; then
    _record_pass "e2e: an allowed advisory push records exactly one row"
else
    _record_fail "e2e: an allowed advisory push records exactly one row" \
                 "rows=${_ROWCOUNT}; log: $(cat "${_LOG}" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# The gate itself must be undisturbed. These re-assert the leg's own controls
# with the recorder wired in — telemetry that changes a gate decision is worse
# than no telemetry.
# ---------------------------------------------------------------------------
if [ -f "${FIXTURE}" ]; then
    if printf '%s' "${_out_satisfied}" | diff -q - "${FIXTURE}" >/dev/null 2>&1; then
        _record_pass "recorder leaves the satisfied path byte-identical to the control"
    else
        _record_fail "recorder leaves the satisfied path byte-identical to the control" \
                     "output drifted: ${_out_satisfied}"
    fi
else
    _record_fail "recorder leaves the satisfied path byte-identical to the control" \
                 "control fixture missing"
fi

if printf '%s' "${_out_missing}" | grep -qF 'permissionDecision'; then
    _record_fail "recorder adds no permissionDecision to the advisory row" \
                 "decision emitted: ${_out_missing}"
else
    _record_pass "recorder adds no permissionDecision to the advisory row"
fi

# An unwritable shadow log must cost a record and nothing else. This is the one
# assertion that proves the diagnostic cannot become an enforcement side effect.
_clear; _seed_review; _seed_verify
_out_ok="$(_push)"
_clear; _seed_review; _seed_verify
_out_broken_log="$(_push "${PROJECT_ROOT}" "/nonexistent-dir/x.jsonl")"
if [ "${_out_ok}" = "${_out_broken_log}" ] && [ -n "${_out_ok}" ]; then
    _record_pass "an unwritable shadow log leaves the gate output unchanged"
else
    _record_fail "an unwritable shadow log leaves the gate output unchanged" \
                 "with log: ${_out_ok} / without: ${_out_broken_log}"
fi

chmod 644 "${_BROKEN}/hooks/lib/branch-ledger.sh" 2>/dev/null || true
rm -rf "${_BROKEN}" "${_REPO}" "${_TMPHOME}" 2>/dev/null || true
export HOME="$_OLDHOME"
print_summary
exit $?
