#!/usr/bin/env bash
# test-reviewer-evidence-leg.sh — the ADVISORY reviewer-evidence leg in
# hooks/openspec-guard.sh (openspec/changes/reviewer-dispatch-and-evidence).
#
# The whole proof of this leg is a DIVERGENCE, not a single assertion. Before
# the change these two ledger states produced byte-identical output (0 bytes,
# silent allow):
#
#     REVIEW + VERIFY + reviewer-ran    -> silent allow
#     REVIEW + VERIFY, NO reviewer-ran  -> silent allow
#
# After it, row 1 must stay byte-identical to the pre-change control fixture and
# row 2 must gain the advisory. Asserting only row 1 (an empty-output check) is
# vacuous: CLAUDE.md is explicit that an empty-output assertion cannot tell
# "checked and clean" from "the harness never ran". Both rows are asserted here,
# and the fixture is a pre-change capture from the REAL guard, never hand-written.
#
# BOTH milestones are seeded in every case that must REACH the leg. Seeding only
# requesting-code-review denies on the missing VERIFY milestone, and a deny drops
# the advisory by design — so the leg is never consulted and the test would pass
# for the wrong reason.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-reviewer-evidence-leg.sh ==="

GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
FIXTURE="${SCRIPT_DIR}/fixtures/reviewer-evidence/satisfied-control.json"

_OLDHOME="$HOME"
_TMPHOME="$(mktemp -d /tmp/rel-home-XXXXXX)"
export HOME="${_TMPHOME}"
mkdir -p "$HOME/.claude"
_TPATH="$HOME/t.jsonl"; touch "$_TPATH"

_REPO="$(mktemp -d /tmp/rel-repo-XXXXXX)"
# PHYSICAL path, mandatory. On macOS /tmp is a symlink to /private/tmp and
# `git rev-parse --show-toplevel` (which is how the guard derives _proot)
# returns the resolved form. Seeding the ledger under the unresolved path
# yields a DIFFERENT branch-ledger key, so the guard's own-key leg misses and
# the #131 cross-location bridge rescues it instead — every assertion still
# "passes" while measuring the bridge rather than this leg, and the satisfied
# row gains bridge advisory text it must not have.
_REPO="$(cd "$_REPO" && pwd -P)"
( cd "$_REPO" && git init -q && git config user.email t@t && git config user.name t \
  && git commit -q --allow-empty -m init ) >/dev/null 2>&1

# A copy of the plugin whose branch-ledger.sh cannot be sourced. Used for the
# fail-open-announces cases; created once, reused.
_BROKEN="$(mktemp -d /tmp/rel-broken-XXXXXX)"
cp -R "${PROJECT_ROOT}/hooks" "${_BROKEN}/hooks"
chmod 000 "${_BROKEN}/hooks/lib/branch-ledger.sh"

# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/branch-ledger.sh"

_seed_review()   { branch_ledger_record "requesting-code-review" "$_REPO"; }
_seed_verify()   { branch_ledger_record "verification-before-completion" "$_REPO"; }
_seed_reviewer() { branch_ledger_record "reviewer-ran" "$_REPO"; }
_clear()         { rm -rf "$HOME"/.claude/.skill-branch-ledger-* "$HOME"/.claude/.skill-composition-state-*; }

_payload() {
    jq -n --arg tp "$_TPATH" --arg c "$_REPO" \
      '{transcript_path:$tp,cwd:$c,tool_name:"Bash",tool_input:{command:"git push"}}'
}
# _push [plugin_root] — emits the guard's stdout for a git push. No `< /dev/null`
# anywhere near this: the payload arrives on a PIPE and a redirect would override
# it, leaving the hook reading empty input.
_push() {
    local _root="${1:-${PROJECT_ROOT}}"
    _payload | ( cd "$_REPO" && CLAUDE_PLUGIN_ROOT="${_root}" bash "${_root}/hooks/openspec-guard.sh" ) 2>/dev/null
}

# ---------------------------------------------------------------------------
# (a) ROW 2 of the divergence: REVIEW+VERIFY credited, reviewer-ran ABSENT.
#     Must emit the advisory, and must NOT deny.
# ---------------------------------------------------------------------------
_clear; _seed_review; _seed_verify
_out_missing="$(_push)"
case "${_out_missing}" in
    *"REVIEWER EVIDENCE:"*) _record_pass "missing reviewer evidence emits an advisory" ;;
    *) _record_fail "missing reviewer evidence emits an advisory" "sentinel absent: ${_out_missing}" ;;
esac

# The leg is warn-first. A permissionDecision here would be exactly the
# unmeasured deny this repo has already measured at 56-94% false-block.
if printf '%s' "${_out_missing}" | grep -qF 'permissionDecision'; then
    _record_fail "advisory leg sets NO permissionDecision" "decision emitted: ${_out_missing}"
else
    _record_pass "advisory leg sets NO permissionDecision"
fi

# ---------------------------------------------------------------------------
# (b) ROW 1 of the divergence: reviewer-ran present => byte-identical to the
#     pre-change control captured from the UNMODIFIED guard.
# ---------------------------------------------------------------------------
_clear; _seed_review; _seed_verify; _seed_reviewer
_out_satisfied="$(_push)"
if [ -f "${FIXTURE}" ]; then
    if printf '%s' "${_out_satisfied}" | diff -q - "${FIXTURE}" >/dev/null 2>&1; then
        _record_pass "satisfied path is byte-identical to the pre-change control"
    else
        _record_fail "satisfied path is byte-identical to the pre-change control" \
                     "output drifted: ${_out_satisfied}"
    fi
else
    _record_fail "satisfied path is byte-identical to the pre-change control" "control fixture missing"
fi

# The divergence itself, asserted directly. Rows 1 and 2 were identical before
# this change; if they are still identical the leg does nothing, no matter what
# either row asserts on its own.
if [ "${_out_missing}" != "${_out_satisfied}" ]; then
    _record_pass "satisfied and missing rows DIVERGE (they were identical pre-change)"
else
    _record_fail "satisfied and missing rows DIVERGE (they were identical pre-change)" \
                 "both rows produced: ${_out_satisfied}"
fi

# ---------------------------------------------------------------------------
# (c) SITE 2: the global fail-closed gate. This repo's own pushes traverse it,
#     and a leg wired only into the chain-scoped Check 1 leaves it passing on
#     the old milestone alone — the design review's severest finding.
#     No composition state => the chain block is skipped entirely.
# ---------------------------------------------------------------------------
_clear; _seed_review; _seed_verify
rm -f "$HOME"/.claude/.skill-composition-state-*
_out="$(_push)"
case "${_out}" in
    *"REVIEWER EVIDENCE:"*) _record_pass "advisory fires on the global fail-closed path (site 2)" ;;
    *) _record_fail "advisory fires on the global fail-closed path (site 2)" "sentinel absent: ${_out}" ;;
esac

# ---------------------------------------------------------------------------
# (d) SITE 1: the chain-scoped Check 1, exercised with the GLOBAL gate switched
#     off. The global block is gated on _LEDGER_OK, so an unsourceable
#     branch-ledger.sh skips it entirely while the chain block still runs off
#     .completed — the one state that isolates site 1. This simultaneously
#     covers the #198 requirement that a leg which cannot evaluate ANNOUNCES.
# ---------------------------------------------------------------------------
_clear
# Token shape is `session-<transcript basename>` (hooks/lib/session-token.sh).
_TOKEN="session-$(basename "${_TPATH}" .jsonl)"
cat > "$HOME/.claude/.skill-composition-state-${_TOKEN}" <<'EOF'
{"chain":["requesting-code-review","verification-before-completion"],
 "completed":["requesting-code-review","verification-before-completion"]}
EOF
_out="$(_push "${_BROKEN}")"
case "${_out}" in
    *"REVIEWER EVIDENCE: could not check"*)
        _record_pass "chain-scoped site 1 fires, and announces when it cannot evaluate" ;;
    *)
        _record_fail "chain-scoped site 1 fires, and announces when it cannot evaluate" \
                     "sentinel absent: ${_out}" ;;
esac
if printf '%s' "${_out}" | grep -qF 'permissionDecision'; then
    _record_fail "degraded site-1 leg sets NO permissionDecision" "decision emitted: ${_out}"
else
    _record_pass "degraded site-1 leg sets NO permissionDecision"
fi

# ---------------------------------------------------------------------------
# (e) Fail-open still emits SOMETHING with no chain at all. Silence is
#     indistinguishable from a satisfied check (#198).
# ---------------------------------------------------------------------------
_clear; _seed_review; _seed_verify
_out="$(_push "${_BROKEN}")"
if [ -n "${_out}" ]; then
    _record_pass "degraded evaluation still emits output"
else
    _record_fail "degraded evaluation still emits output" "guard fell silent"
fi

# ---------------------------------------------------------------------------
# (f) SHA-binding (design D8). A reviewer that ran against an earlier commit is
#     not evidence for this diff; without the binding the sub-signal would be
#     weaker than the milestone it supplements.
# ---------------------------------------------------------------------------
_clear; _seed_reviewer
( cd "$_REPO" && git commit -q --allow-empty -m later ) >/dev/null 2>&1
_seed_review; _seed_verify
_out="$(_push)"
case "${_out}" in
    *"REVIEWER EVIDENCE: stale"*) _record_pass "reviewer-ran recorded at an older SHA reports stale" ;;
    *) _record_fail "reviewer-ran recorded at an older SHA reports stale" "no staleness text: ${_out}" ;;
esac

# ---------------------------------------------------------------------------
# (g) Population is narrow: where REVIEW is NOT credited the existing deny legs
#     own the outcome and this leg must say nothing. A deny that also carried
#     reviewer text would mean the leg had leaked onto the enforcement path.
# ---------------------------------------------------------------------------
_clear
_out="$(_push)"
case "${_out}" in
    *"REVIEWER EVIDENCE:"*)
        _record_fail "silent where REVIEW is not credited at all" "leg fired on a deny: ${_out}" ;;
    *) _record_pass "silent where REVIEW is not credited at all" ;;
esac
case "${_out}" in
    *'"permissionDecision"'*"deny"*) _record_pass "un-credited REVIEW still DENIES (deny legs unchanged)" ;;
    *) _record_fail "un-credited REVIEW still DENIES (deny legs unchanged)" "expected a deny, got: ${_out}" ;;
esac

# ---------------------------------------------------------------------------
# (h) Structural pin: BOTH call sites must exist in the guard. The predicate is
#     shared precisely so neither site can be dropped silently; a future edit
#     removing one would otherwise pass (c) or (d) alone.
# ---------------------------------------------------------------------------
_SITES="$(grep -c '^ *_reviewer_ran_ok$' "${GUARD}" 2>/dev/null || echo 0)"
if [ "${_SITES}" -ge 2 ] 2>/dev/null; then
    _record_pass "the shared predicate is called from both gate sites"
else
    _record_fail "the shared predicate is called from both gate sites" "found ${_SITES} call site(s)"
fi

chmod 644 "${_BROKEN}/hooks/lib/branch-ledger.sh" 2>/dev/null || true
rm -rf "${_BROKEN}" "${_REPO}" "${_TMPHOME}" 2>/dev/null || true
export HOME="$_OLDHOME"
print_summary
exit $?
